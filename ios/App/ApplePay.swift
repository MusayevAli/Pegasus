#if os(iOS)
import SwiftUI
import PassKit
import Observation
import TripFitCore

struct ServerQuote: Decodable {
    struct Item: Decodable { var label: String; var amountMinor: Int }
    var id: String; var currency: String; var totalMinor: Int; var expiresAt: String
    var inventorySource: String; var items: [Item]
}
struct PaymentState: Decodable {
    var state: String; var authorization: String; var capture: String; var issuance: String; var reference: String?
}

struct NativeApplePayButton: UIViewRepresentable {
    var action: () -> Void
    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }
    func updateUIView(_ uiView: PKPaymentButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

/// A real PassKit path, gated by a server-validated LIVE quote and device capability.
/// Never converts fixture inventory into a chargeable offer.
@MainActor @Observable final class ApplePayCoordinator: NSObject, PKPaymentAuthorizationControllerDelegate {
    var status = "Apple Pay requires a configured merchant, supported device, payment processor and live airline offer. Complete the demo without credentials."
    var busy = false
    var canPresent = false
    private var quote: ServerQuote?
    private var controller: PKPaymentAuthorizationController?
    private weak var store: BookingStore?
    private var authorized = false
    private var quoteRevision = -1
    private var merchant: String { Bundle.main.object(forInfoDictionaryKey: "ApplePayMerchantID") as? String ?? "" }
    private var country: String { Bundle.main.object(forInfoDictionaryKey: "ApplePayCountryCode") as? String ?? "TR" }
    private let networks: [PKPaymentNetwork] = [.visa, .masterCard, .amex]

    func prepare(store: BookingStore) async {
        self.store = store
        guard !merchant.isEmpty, !merchant.contains("YOUR"), PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks) else { return }
        guard let itinerary = store.itinerary, let localQuote = store.quote else { return }
        busy = true; defer { busy = false }
        let revision = store.revision
        do {
            let selection = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.selection))
            let remote = try await BackendAPI(baseURL: store.analytics.baseURL, token: store.analytics.uploadToken).post("/api/quotes", body: ["journeyID": itinerary.id, "adults": store.request.adults, "children": store.request.children, "roundTrip": store.request.returnDate != nil, "selection": selection], as: ServerQuote.self)
            guard revision == store.revision, remote.currency == "EUR", remote.totalMinor == localQuote.totalCents, remote.items.reduce(0, { $0 + $1.amountMinor }) == remote.totalMinor else { throw BackendError.invalidResponse }
            quote = remote; quoteRevision = revision
            canPresent = remote.inventorySource == "live"
            if !canPresent { status = "Server quote verified. Inventory is demo, so Apple Pay remains unavailable for this booking. No real charge can occur." }
        } catch { status = "Live quote verification unavailable. Your offline demo can still finish." }
    }
    func present(store: BookingStore) async {
        guard !busy, canPresent, let quote, quoteRevision == store.revision else { return }
        guard let expiry = QuoteExpiry.date(quote.expiresAt), expiry > Date() else { canPresent = false; status = "Quote expired. Return to review to refresh it."; return }
        busy = true; authorized = false; self.store = store
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchant; request.countryCode = country; request.currencyCode = quote.currency
        request.supportedNetworks = networks; request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems = quote.items.map { PKPaymentSummaryItem(label: $0.label, amount: NSDecimalNumber(value: $0.amountMinor).dividing(by: 100), type: .final) }
        request.paymentSummaryItems.append(PKPaymentSummaryItem(label: "Pegasus TripFit", amount: NSDecimalNumber(value: quote.totalMinor).dividing(by: 100), type: .final))
        let c = PKPaymentAuthorizationController(paymentRequest: request); c.delegate = self; controller = c
        store.analytics.emit("checkout_started", "checkout.apple_pay", ["totalMinor": .int(quote.totalMinor)])
        c.present { [weak self] presented in Task { @MainActor in
            if !presented { self?.busy = false; self?.status = "Apple Pay couldn't open. Please try again."; self?.store?.analytics.emit("checkout_failed", "checkout.apple_pay", ["code": .string("wallet_unavailable")]) }
        } }
    }
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        guard let store, let quote, quoteRevision == store.revision else { completion(PKPaymentAuthorizationResult(status: .failure, errors: nil)); return }
        authorized = true
        Task { @MainActor in
            do {
                let result = try await BackendAPI(baseURL: store.analytics.baseURL, token: store.analytics.uploadToken).post("/api/payments", body: ["quoteID": quote.id, "idempotencyKey": store.paymentAttempt, "mode": "apple_pay", "paymentToken": payment.token.paymentData.base64EncodedString()], as: PaymentState.self)
                let success = result.authorization == "authorized"
                status = "Payment authorisation: \(result.authorization). Capture: \(result.capture). Ticket issuance: \(result.issuance)."
                // A wallet success is only authorization. Provider-confirmed issued bookings
                // must arrive from an authenticated airline adapter; no demo trip is promoted.
                completion(PKPaymentAuthorizationResult(status: success ? .success : .failure, errors: nil))
                if !success { store.analytics.emit("checkout_failed", "checkout.apple_pay", ["code": .string("provider_declined")]) }
            } catch {
                status = "Payment could not be confirmed. No ticket has been shown as issued. Retry uses the same idempotency key."
                store.analytics.emit("checkout_failed", "checkout.apple_pay", ["code": .string("payment_unconfirmed")])
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
            }
        }
    }
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in Task { @MainActor in
            guard let self else { return }; self.busy = false; self.controller = nil
            if !self.authorized { self.status = "Apple Pay cancelled. Your booking is unchanged."; self.store?.analytics.emit("checkout_cancelled", "checkout.apple_pay") }
        } }
    }
}

#else
import SwiftUI
import Observation
@MainActor @Observable final class ApplePayCoordinator {
    var status = "Native Mac preview. Apple Pay is implemented for the iOS target; demo inventory cannot be charged."
    var busy = false
    var canPresent = false
    func prepare(store: BookingStore) async {}
    func present(store: BookingStore) async {}
}
struct NativeApplePayButton: View {
    var action: () -> Void
    var body: some View { EmptyView() }
}
#endif
