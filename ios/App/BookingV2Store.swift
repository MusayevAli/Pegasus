import Foundation
import Observation

private struct V2Draft: Codable {
    var intent: V2SearchIntent; var stage: V2BookingStage; var selectedOffer: V2FlightOffer?; var selection: V2Selection
    var quote: V2Quote?; var passengers: [V2Passenger]; var completedOrderId: String?; var checkoutAttempt: String
    var reviewedQuoteId: String?; var pendingCheckout: V2CheckoutBody?; var providerID: String?
}
private struct V2IntentBody: Encodable { var intent: V2SearchIntent; var provider: String }
private struct V2ExtractionBody: Encodable { var revision: Int; var text: String; var context: V2DeviceContext; var currentIntent: V2SearchIntent? }
private struct V2QuoteBody: Encodable {
    var revision: Int; var offerId: String; var intent: V2SearchIntent; var selection: V2Selection?
    enum CodingKeys: String, CodingKey { case revision, offerId, intent, selection }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(revision, forKey: .revision); try c.encode(offerId, forKey: .offerId); try c.encode(intent, forKey: .intent); try c.encode(selection, forKey: .selection) }
}
private struct V2ImageBody: Encodable { var revision: Int; var imageBase64: String; var mimeType: String; var context: V2DeviceContext? }
private struct V2CompareBody: Encodable { var revision: Int; var intent: V2SearchIntent; var offerIds: [String]; var provider: String }
private struct V2PackingBody: Encodable { var intent: V2SearchIntent; var selection: V2Selection; var measurements: [V2PackingMeasurement]; var items: [V2PackingItem] }
private struct V2CheckoutBody: Codable { var quoteId: String; var idempotencyKey: String; var travellerNames: [String]; var paymentMode = "demo"; var simulateOutcome: String }

@MainActor @Observable final class BookingV2Store {
    let analytics: Analytics
    var stage: V2BookingStage = .search
    var intent = V2SearchIntent()
    private(set) var providerID: String
    var providers: [V2InventoryProvider] = []
    var selectedProvider: V2InventoryProvider? { providers.first { $0.id == providerID } }
    @ObservationIgnored var onConfirmedSearch: ((V2SearchIntent) -> Void)?
    @ObservationIgnored var onDemoOrder: ((V2SearchIntent, V2Selection) -> Void)?
    var offers: [V2FlightOffer] = []
    var selectedOffer: V2FlightOffer?
    var quote: V2Quote?
    var services: [V2AncillaryProduct] = []
    var bundles: [V2FareBundle] = []
    var seatMaps: [V2SeatMap] = []
    var passengers: [V2Passenger] = []
    var selection = V2Selection()
    var orders: [V2Order] = []
    var completedOrder: V2Order?
    var capabilities: V2Capabilities?
    var airports: [V2Airport] = []
    var routes: [V2Route] = []
    var alternatives: [V2Alternative] = []
    var comparison: V2Comparison?
    var compareIds: [String] = []
    var packingAssessment: V2PackingAssessment?
    var packingOptions: [V2PackingOption] = []
    var packingQuestions: [String] = []
    var tripImport: V2TripImport?
    var importedTrip: V2TripImport? { get { tripImport } set { tripImport = newValue } }
    var error: String?
    var notice: String?
    var aiStatus = "Describe a trip or use the fields below."
    var aiBusy = false
    var busy = false
    var busyMessage = ""
    var checkoutBusy = false
    var priceChanged = false
    var lastAIRequestId: String?
    var lastAIModel: String?
    var checkoutAttempt = UUID().uuidString
    var hasPendingCheckout: Bool { pendingCheckout != nil && completedOrder == nil }
    var canUndoPacking: Bool { packingUndo != nil && completedOrder == nil }
    var total: V2Money? { quote?.total ?? selectedOffer?.totalPrice }
    var readyForReview: Bool { selectedOffer?.effectiveCapabilities.quote == true && selectedOffer?.effectiveCapabilities.checkout == true && selectedOffer?.source == "sample" && !passengers.isEmpty && passengers.allSatisfy(\.isValid) && quote?.isValid == true && !busy }
    var isOffline = false
    @ObservationIgnored private var defaults: UserDefaults
    @ObservationIgnored private var injectedClient: (any BookingV2Client)?
    @ObservationIgnored private var requests: [String: (UUID, Task<Data, Error>)] = [:]
    @ObservationIgnored private var editSearchTask: Task<Void, Never>?
    private var operations = Set<String>()
    private var packingUndo: V2Selection?
    private var packingProposed: V2Selection?
    private var packingOfferId: String?
    private var packingRecommendationId: String?
    private var packingRecommendationVersion: Int?
    private var packingRecommendationAction: String?
    private var packingRevision = -1
    private var reviewedQuoteId: String?
    private var pendingCheckout: V2CheckoutBody?
    private var compatibleSelection: (String, V2Selection)?
    private var client: any BookingV2Client { injectedClient ?? BookingV2HTTPClient(baseURL: analytics.baseURL, token: analytics.uploadToken) }

    init(analytics: Analytics, client: (any BookingV2Client)? = nil, defaults: UserDefaults = .standard, providerID: String = "pegasus_mcp") {
        self.providerID = providerID
        self.analytics = analytics; self.injectedClient = client; self.defaults = defaults
        if let data = defaults.data(forKey: "bookingV2Orders"), let saved = try? JSONDecoder().decode([V2Order].self, from: data) { orders = saved }
        if let data = defaults.data(forKey: "bookingV2Draft"), let saved = try? JSONDecoder().decode(V2Draft.self, from: data) {
            self.providerID = saved.providerID ?? saved.selectedOffer?.provider ?? providerID
            intent = saved.intent; selection = saved.selection; selectedOffer = saved.selectedOffer; quote = saved.quote; passengers = saved.passengers
            checkoutAttempt = saved.checkoutAttempt; reviewedQuoteId = saved.reviewedQuoteId; pendingCheckout = saved.pendingCheckout
            completedOrder = orders.first { $0.id == saved.completedOrderId }
            stage = completedOrder == nil ? (saved.stage == .confirmation ? .review : saved.stage) : (saved.stage == .trips ? .trips : .confirmation)
        } else { analytics.startFlow() }
        syncPassengers()
    }

    func initialize() async {
        error = nil
        do {
            let catalog: V2Catalog = try await send("catalog", path: "/api/v2/catalog", method: "GET")
            applyCatalog(catalog); isOffline = false
            if let data = try? JSONEncoder().encode(catalog) { defaults.set(data, forKey: "bookingV2Catalog") }
            if let response: V2ProvidersResponse = try? await send("providers", path: "/api/v2/providers", method: "GET") { providers = response.providers }
            if selectedOffer?.effectiveCapabilities.quote == true && completedOrder == nil { await reloadServices(); if pendingCheckout == nil { await requote() } else { notice = "A previous demo checkout is unconfirmed. Retry to recover the same attempt." } }
        } catch {
            isOffline = true
            if let data = defaults.data(forKey: "bookingV2Catalog"), let catalog = try? JSONDecoder().decode(V2Catalog.self, from: data) { applyCatalog(catalog); notice = "Offline. Cached sample details are available; reconnect to validate prices and book." }
            else { self.error = message(error) }
        }
    }
    private func applyCatalog(_ catalog: V2Catalog) { capabilities = catalog.capabilities; airports = catalog.airports; bundles = catalog.bundles; routes = catalog.routes }
    func editIntent(_ mutate: (inout V2SearchIntent) -> Void) {
        cancelEditingRequests(); aiStatus = ""
        if completedOrder != nil { analytics.startFlow() }
        let previous = intent
        mutate(&intent); intent.revision += 1
        invalidateBooking(preserveCompatible: sameNeeds(previous, intent)); offers = []; syncPassengers(); error = nil
        let changed = changedIntentFields(previous, intent)
        intent.unresolved.removeAll { unresolved in changed.contains(unresolved.field) || (unresolved.field == "year" && !changed.isDisjoint(with: ["outboundDate", "returnDate", "dateWindow"])) }
        analytics.emit("preference_changed", "search.fields", ["revision": .int(intent.revision)])
        persist()
        if stage != .search && stage != .trips {
            stage = .results
            editSearchTask?.cancel()
            editSearchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return }; self?.editSearchTask = nil; await self?.search()
            }
        }
    }
    func setProvider(_ id: String) {
        guard ["pegasus_mcp", "sample"].contains(id), id != providerID else { return }
        providerID = id
        editIntent { _ in }
        compatibleSelection = nil; notice = selectedProvider?.notice; persist()
    }
    func setLocked(_ field: String, _ locked: Bool) {
        editIntent { intent in intent.lockedFields.removeAll { $0 == field }; if locked { intent.lockedFields.append(field) } }
    }
    var missingFields: [V2UnresolvedField] {
        var fields: [V2UnresolvedField] = []
        func add(_ field: String, _ question: String) { fields.append(V2UnresolvedField(field: field, question: question, choices: [])) }
        if intent.originAirport?.count != 3 { add("originAirport", "Where are you flying from?") }
        if intent.destinationAirports.isEmpty { add("destinationAirports", "Choose a destination airport.") }
        if intent.outboundDate == nil && intent.dateWindow == nil { add("outboundDate", "Choose a departure date, including the year.") }
        if intent.tripType == "round_trip" && intent.returnDate == nil && intent.durationNights == nil { add("returnDate", "Choose a return date or trip duration.") }
        if intent.adults < 1 || intent.adults > 8 || intent.partySize > 9 { add("adults", "Choose 1–9 travellers, including an adult.") }
        if intent.childAges.contains(where: { $0 == nil || !(2...11).contains($0 ?? -1) }) { add("childAges", "Enter each child's age, 2–11 years, on the departure date.") }
        if intent.budgetMinor != nil && intent.budgetScope == nil { add("budgetScope", "Is the budget for everyone or per person?") }
        if (intent.checkedBags ?? 0) > 0 {
            if intent.baggageScope == nil { add("baggageScope", "Is this bag count for the whole party or each traveller?") }
            if intent.baggageDirection == nil { add("baggageDirection", "Which direction needs checked bags?") }
        }
        if let incoming = intent.incomingFlight, !incoming.confirmed { add("incomingFlight", "Confirm the incoming flight's airport and local arrival time.") }
        for item in intent.unresolved where !fields.contains(where: { $0.field == item.field }) { fields.append(item) }
        return fields
    }
    func interpret(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancelInterpretation(); if completedOrder != nil { analytics.startFlow() }; error = nil; aiBusy = true; aiStatus = "Reading your trip preferences…"
        let revision = intent.revision, previous = intent
        let id = begin("interpret", "Understanding your trip")
        defer { end(id) }
        analytics.emit("ai_request_started", "search.intent", ["revision": .int(revision)])
        do {
            let response: V2AIExtraction = try await send("interpret", path: "/api/v2/ai/search-intent", body: V2ExtractionBody(revision: revision, text: String(trimmed.prefix(2000)), context: .current, currentIntent: previous))
            guard intent.revision == revision, response.revision == revision, response.source == "openai" else { return }
            intent = try preservingLocked(response.intent, previous: previous)
            intent.revision = revision + 1; invalidateBooking(); syncPassengers(); aiBusy = false
            aiStatus = response.summary; recordAI(response.requestId, model: response.model)
            persist(); await search()
        } catch {
            guard revision == intent.revision else { return }
            if !isCancellation(error) { aiStatus = "AI unavailable. You can retry or use the fields below."; self.error = message(error); analytics.emit("ai_request_finished", "search.intent", ["validationOutcome": .string("failed")]) }
        }
    }
    func cancelInterpretation() { cancel("interpret"); aiBusy = false; if aiStatus.contains("Reading") { aiStatus = "Cancelled. Your fields are unchanged." } }
    func search() async {
        editSearchTask?.cancel(); error = nil; alternatives = []; comparison = nil
        if completedOrder != nil { analytics.startFlow(); invalidateBooking(preserveCompatible: false) }
        guard missingFields.isEmpty else { offers = []; go(.results); return }
        let revision = intent.revision, request = intent, requestedProvider = providerID
        let operation = begin("search", "Finding flights")
        defer { end(operation) }
        analytics.emit("search_submitted", "search.submit", ["origin": .string(intent.originAirport ?? ""), "destination": .string(intent.destinationAirports.first ?? ""), "partySize": .int(intent.partySize), "revision": .int(revision)])
        do {
            let response: V2SearchResponse = try await send("search", path: "/api/v2/flights/search", body: V2IntentBody(intent: request, provider: requestedProvider))
            guard revision == intent.revision, response.revision == revision else { return }
            guard requestedProvider == providerID, response.source == (requestedProvider == "sample" ? "sample" : "live"), response.offers.allSatisfy({ $0.provider == requestedProvider && $0.source == response.source }) else { throw V2APIError.invalidResponse }
            offers = response.offers; intent.unresolved = response.unresolved; notice = response.notice; isOffline = false
            if requestedProvider == "sample", let data = try? JSONEncoder().encode(response) { defaults.set(data, forKey: cacheKey(request)) }
            if response.unresolved.isEmpty { onConfirmedSearch?(request) }
            analytics.emit(offers.isEmpty ? "no_results" : "results_shown", "search.results", ["resultCount": .int(offers.count), "inventorySource": .string(response.source)])
            go(.results)
            if offers.isEmpty && response.unresolved.isEmpty { await loadAlternatives() }
        } catch {
            guard revision == intent.revision, !isCancellation(error) else { return }
            isOffline = true
            if requestedProvider == "sample", let data = defaults.data(forKey: cacheKey(request)), let response = try? JSONDecoder().decode(V2SearchResponse.self, from: data) {
                offers = response.offers; notice = "Offline: previously fetched sample results. Reconnect before selecting and repricing."; go(.results)
            } else { offers = []; self.error = message(error); go(.results) }
        }
    }
    func loadAlternatives() async {
        let revision = intent.revision
        do {
            let response: V2AlternativesResponse = try await send("alternatives", path: "/api/v2/search/alternatives", body: V2IntentBody(intent: intent, provider: providerID))
            guard revision == intent.revision, response.revision == revision else { return }
            guard response.alternatives.allSatisfy({ $0.offer.provider == providerID && $0.offer.source == (providerID == "sample" ? "sample" : "live") }) else { throw V2APIError.invalidResponse }
            alternatives = Array(response.alternatives.prefix(3)); notice = response.notice
        } catch { if revision == intent.revision && !isCancellation(error) { notice = "No supported alternatives could be loaded. Adjust your fields and retry." } }
    }
    func chooseAlternative(_ alternative: V2Alternative) async {
        guard alternative.intent.revision == intent.revision + 1, alternatives.contains(alternative) else { error = "Search fields changed. Refresh alternatives before choosing one."; return }
        cancelEditingRequests()
        guard !alternative.changes.contains(where: { intent.lockedFields.contains($0.field) }) else { error = "Unlock the affected requirement before choosing this alternative."; return }
        let revision = intent.revision + 1
        intent = alternative.intent; intent.revision = revision; invalidateBooking(); syncPassengers()
        analytics.emit("alternative_selected", "search.alternative", ["offerId": .string(alternative.offer.id), "recommendationId": .string(alternative.id)])
        await search()
    }
    func select(_ offer: V2FlightOffer) async {
        guard offer.provider == providerID, offer.source == (providerID == "sample" ? "sample" : "live") else { error = "The inventory source changed. Search again before selecting this flight."; return }
        guard offer.available else { error = "This flight is sold out. Choose another option."; return }
        cancelEditingRequests(); error = nil
        let prior = selectedOffer
        let savedSelection = prior?.id == offer.id ? selection : (compatibleSelection?.0 == offer.id ? compatibleSelection?.1 : nil)
        selectedOffer = offer; quote = nil; reviewedQuoteId = nil; completedOrder = nil
        if prior?.id != offer.id { selection = V2Selection(); services = []; seatMaps = []; packingUndo = nil; packingOptions = [] }
        checkoutAttempt = UUID().uuidString; pendingCheckout = nil
        if !offer.effectiveCapabilities.quote {
            selection = V2Selection(); services = []; seatMaps = []; bundles = []; compatibleSelection = nil
            notice = "Flight price from Pegasus. Bags, seats and meals are not priced here. Continue on Pegasus to confirm availability and the final amount."
            analytics.emit("offer_selected", "itinerary.select", ["offerId": .string(offer.id), "inventorySource": .string(offer.source)])
            go(.configuration); return
        }
        let operation = begin("select", "Checking this flight")
        defer { end(operation) }
        let revision = intent.revision
        do {
            let response: V2Quote = try await send("quote", path: "/api/v2/quotes", body: V2QuoteBody(revision: revision, offerId: offer.id, intent: intent, selection: savedSelection.map { compatible($0, with: offer) }))
            guard selectedOffer?.id == offer.id, revision == intent.revision else { return }
            try acceptQuote(response)
            await reloadServices()
            analytics.emit("offer_selected", "itinerary.select", ["offerId": .string(offer.id), "totalMinor": .int(response.total.amountMinor), "inventorySource": .string(response.source)])
            go(.configuration)
        } catch { if !isCancellation(error) { self.error = message(error) } }
    }
    func reloadServices() async {
        guard let offer = selectedOffer, offer.effectiveCapabilities.ancillaries || offer.effectiveCapabilities.seats else { return }
        let revision = intent.revision
        let ages = intent.childAges.compactMap { $0 }.map(String.init).joined(separator: ",")
        let path = "/api/v2/offers/\(offer.id)/services?adults=\(intent.adults)&childAges=\(ages)"
        do {
            let response: V2OfferServices = try await send("services", path: path, method: "GET")
            guard selectedOffer?.id == response.offerId, revision == intent.revision else { return }
            services = response.products; bundles = response.bundles; seatMaps = response.seatMaps
            syncPassengers(response.passengers)
        } catch { if !isCancellation(error) { self.error = message(error) } }
    }
    func requote() async {
        guard let offer = selectedOffer, offer.effectiveCapabilities.quote, completedOrder == nil else { return }
        let revision = intent.revision, requested = selection, priorTotal = quote?.total.amountMinor
        let operation = begin("quote", "Updating the total")
        defer { end(operation) }
        do {
            let response: V2Quote = try await send("quote", path: "/api/v2/quotes", body: V2QuoteBody(revision: revision, offerId: offer.id, intent: intent, selection: requested))
            guard revision == intent.revision, selectedOffer?.id == offer.id, selection == requested else { return }
            try acceptQuote(response)
            priceChanged = priorTotal != nil && priorTotal != response.total.amountMinor
            analytics.emit("quote_updated", "configuration.total", ["quoteId": .string(response.id), "totalMinor": .int(response.total.amountMinor)])
            persist()
        } catch { if revision == intent.revision && !isCancellation(error) { quote = nil; self.error = message(error) } }
    }
    private func acceptQuote(_ response: V2Quote) throws {
        guard response.source == selectedOffer?.source, response.provider == selectedOffer?.provider, response.offerId == selectedOffer?.id, response.revision == intent.revision, response.isValid, response.total.currency == "EUR" else { throw V2APIError.invalidResponse }
        quote = response; selection = response.selection; syncPassengers(response.passengers); isOffline = false; persist()
    }
    func setBundle(_ bundleId: String) async { guard supportsAncillaries() else { return }; selection.bundleId = bundleId; selectionChanged("offer_compared", component: "fare.bundle", product: bundleId); await requote() }
    func setBag(_ productId: String?, passengerId: String, segmentId: String, kind: String = "checked") async {
        guard supportsAncillaries() else { return }
        let types = Set(services.filter { $0.type == kind }.map(\.id))
        selection.bags.removeAll { $0.passengerId == passengerId && $0.segmentId == segmentId && types.contains($0.productId) }
        if let productId { selection.bags.append(.init(passengerId: passengerId, segmentId: segmentId, productId: productId)) }
        selectionChanged("baggage_changed", component: "baggage.selector", product: productId ?? "included"); await requote()
    }
    func setMeal(_ productId: String?, passengerId: String, segmentId: String) async {
        guard supportsAncillaries() else { return }
        selection.meals.removeAll { $0.passengerId == passengerId && $0.segmentId == segmentId }
        if let productId { selection.meals.append(.init(passengerId: passengerId, segmentId: segmentId, productId: productId)) }
        selectionChanged("meal_changed", component: "meals.selector", product: productId ?? "none"); await requote()
    }
    func setSeat(_ seatId: String?, passengerId: String, segmentId: String) async {
        guard selectedOffer?.effectiveCapabilities.seats == true else { error = "Seat inventory is unavailable here. Check seats on Pegasus."; return }
        selection.seats.removeAll { $0.passengerId == passengerId && $0.segmentId == segmentId }
        if let seatId { selection.seats.append(.init(passengerId: passengerId, segmentId: segmentId, seatId: seatId)) }
        selectionChanged("seat_changed", component: "seats.map", product: seatId ?? "none"); await requote()
    }
    func applyFamilySeats(segmentId: String) async {
        guard selectedOffer?.effectiveCapabilities.seats == true else { error = "Seat inventory is unavailable here. Check seats on Pegasus."; return }
        guard let map = seatMaps.first(where: { $0.segmentId == segmentId }), map.familyAvailable, map.suggestedFamilySeats.count >= passengers.count else { error = "No eligible adjacent arrangement is available on this flight."; return }
        selection.seats.removeAll { $0.segmentId == segmentId }
        for (passenger, seat) in zip(passengers, map.suggestedFamilySeats) { selection.seats.append(.init(passengerId: passenger.id, segmentId: segmentId, seatId: seat)) }
        selectionChanged("seat_changed", component: "seats.family", product: "adjacent"); await requote()
    }
    private func selectionChanged(_ event: String, component: String, product: String) {
        intent.revision += 1; reviewedQuoteId = nil; pendingCheckout = nil; checkoutAttempt = UUID().uuidString; packingOptions = []; error = nil
        analytics.interact(); analytics.emit(event, component, ["productId": .string(product), "revision": .int(intent.revision)]); persist()
    }
    func updatePassenger(_ passenger: V2Passenger) { if let i = passengers.firstIndex(where: { $0.id == passenger.id }) { passengers[i] = passenger; reviewedQuoteId = nil; persist() } }
    func review() async {
        error = nil
        guard selectedOffer?.effectiveCapabilities.quote == true, selectedOffer?.effectiveCapabilities.checkout == true, selectedOffer?.source == "sample" else { error = "Continue on Pegasus to review a live booking and its final price."; return }
        guard passengers.allSatisfy(\.isValid) else { error = "Enter each traveller's first and last name, and each child's age."; return }
        if pendingCheckout != nil, quote != nil { go(.review); return }
        let before = quote?.total.amountMinor
        await requote()
        guard let quote, quote.isValid else { return }
        priceChanged = before != nil && before != quote.total.amountMinor
        reviewedQuoteId = quote.id; go(.review)
    }
    func checkoutDemo(simulateOutcome: String = "success") async {
        guard !checkoutBusy, completedOrder == nil else { return }
        guard selectedOffer?.source == "sample", selectedOffer?.effectiveCapabilities.checkout == true else { error = "Live booking continues on Pegasus. No payment or ticket is created in this app."; return }
        guard let quote, pendingCheckout != nil || (quote.isValid && quote.selection == selection && quote.revision == intent.revision && reviewedQuoteId == quote.id) else { error = "Review a current, valid quote before completing the booking."; await review(); return }
        guard passengers.allSatisfy(\.isValid) else { error = "Complete the traveller names and child ages first."; return }
        let body = pendingCheckout ?? V2CheckoutBody(quoteId: quote.id, idempotencyKey: checkoutAttempt, travellerNames: passengers.map(\.fullName), simulateOutcome: simulateOutcome)
        pendingCheckout = body; persist()
        checkoutBusy = true; let operation = begin("checkout", "Completing your demo booking")
        defer { checkoutBusy = false; end(operation) }
        analytics.view("checkout"); emitPackingRetention(); analytics.emit("checkout_started", "checkout.demo", ["quoteId": .string(quote.id), "totalMinor": .int(quote.total.amountMinor)])
        do {
            let order: V2Order = try await send("checkout", path: "/api/v2/checkout", body: body)
            guard order.quoteId == quote.id, order.total == quote.total, !order.ticketIssued, order.fulfilmentStatus == "not_issued" else { throw V2APIError.invalidResponse }
            pendingCheckout = nil
            if order.state == "confirmed_demo" {
                if !orders.contains(where: { $0.id == order.id }) { orders.insert(order, at: 0) }
                completedOrder = order
                onDemoOrder?(confirmedTripIntent(order.itinerary), selection)
                analytics.emit("demo_booking_completed", "checkout.demo", ["orderId": .string(order.id), "totalMinor": .int(order.total.amountMinor), "extrasMinor": .int(quote.extrasPrice.amountMinor), "completed": .bool(true)])
                go(.confirmation); emitPackingRetention(); await analytics.flush()
            } else {
                error = order.state == "cancelled" ? "Demo checkout cancelled. Your choices are saved." : "Demo checkout failed. Your choices are saved; retry when ready."
                analytics.emit(order.state == "cancelled" ? "checkout_cancelled" : "checkout_failed", "checkout.demo", ["orderId": .string(order.id)])
                // These are terminal attempts. A deliberate retry receives a new idempotency key.
                checkoutAttempt = UUID().uuidString; persist()
            }
        } catch {
            if case V2APIError.rejected(let status, _) = error, (400...499).contains(status), status != 408, status != 429 { pendingCheckout = nil; reviewedQuoteId = nil; checkoutAttempt = UUID().uuidString }
            self.error = message(error); persist(); analytics.emit("checkout_failed", "checkout.demo", ["code": .string("unconfirmed")])
        }
    }
    func compareSelected(_ ids: [String]) async {
        error = nil
        guard ids.count == 2, Set(ids).count == 2 else { error = "Select two different flights to compare."; return }
        let revision = intent.revision; compareIds = ids
        let operation = begin("compare", "Comparing these flights"); defer { end(operation) }
        do {
            let response: V2Comparison = try await send("compare", path: "/api/v2/ai/compare", body: V2CompareBody(revision: revision, intent: intent, offerIds: ids, provider: providerID))
            guard revision == intent.revision, response.revision == revision, Set(response.offers.map(\.id)) == Set(ids) else { return }
            guard response.offers.allSatisfy({ $0.provider == providerID && $0.source == (providerID == "sample" ? "sample" : "live") }) else { throw V2APIError.invalidResponse }
            comparison = response; analytics.emit("comparison_opened", "itinerary.compare", ["resultCount": .int(2)])
        } catch { if revision == intent.revision && !isCancellation(error) { self.error = message(error) } }
    }
    func cancelPackingOptions() { cancel("packing-options"); packingOptions = []; packingQuestions = []; packingRevision = -1 }
    func cancelPhotoRequests() { cancel("packing"); cancel("import"); cancelPackingOptions(); packingAssessment = nil; tripImport = nil; aiBusy = false }
    func analysePacking(_ data: Data, mimeType: String = "image/jpeg") async {
        error = nil
        guard validImage(data, mimeType: mimeType) else { return }
        let revision = intent.revision; let operation = begin("packing", "Looking at your packing photo"); defer { end(operation) }
        do {
            let result: V2PackingAssessment = try await send("packing", path: "/api/v2/ai/packing", body: V2ImageBody(revision: revision, imageBase64: data.base64EncodedString(), mimeType: mimeType, context: nil))
            guard revision == intent.revision, result.revision == revision, result.source == "openai" else { return }
            packingAssessment = result; recordAI(result.requestId, model: result.model)
        } catch { if revision == intent.revision && !isCancellation(error) { self.error = "AI unavailable. Add packing details manually or retry."; packingAssessment = nil } }
    }
    func loadPackingOptions(measurements: [V2PackingMeasurement], items: [V2PackingItem]) async {
        error = nil
        guard let offer = selectedOffer, supportsAncillaries() else { return }
        let revision = intent.revision; let operation = begin("packing-options", "Checking bag options"); defer { end(operation) }
        do {
            let response: V2PackingOptionsResponse = try await send("packing-options", path: "/api/v2/offers/\(offer.id)/packing-options", body: V2PackingBody(intent: intent, selection: selection, measurements: measurements, items: items))
            guard revision == intent.revision, selectedOffer?.id == offer.id else { return }
            packingOptions = response.options; packingQuestions = response.questions; packingRevision = revision; notice = response.notice
            for option in response.options { analytics.emit("recommendation_generated", "baggage.packing", ["recommendationId": .string(option.id), "recommendationType": .string("baggage"), "recommendationVersion": .int(revision)]) }
        } catch { if !isCancellation(error) { self.error = message(error) } }
    }
    func applyPackingOption(_ option: V2PackingOption) async {
        guard supportsAncillaries() else { return }
        guard packingRevision == intent.revision, packingOptions.contains(where: { $0 == option }) else { error = "Your choices changed. Check packing options again."; return }
        packingUndo = selection; packingProposed = option.selection; packingOfferId = selectedOffer?.id
        packingRecommendationId = option.id; packingRecommendationVersion = intent.revision; packingRecommendationAction = option.action
        selection = option.selection
        analytics.emit("recommendation_accepted", "baggage.packing", ["recommendationId": .string(option.id), "recommendationType": .string("baggage"), "recommendationVersion": .int(packingRecommendationVersion ?? intent.revision)])
        selectionChanged("baggage_changed", component: "baggage.packing", product: option.id); await requote()
        if quote != nil { analytics.emit("recommendation_applied", "baggage.packing", ["recommendationId": .string(option.id), "recommendationType": .string("baggage"), "recommendationVersion": .int(packingRecommendationVersion ?? intent.revision)]) }
    }
    func undoPackingOption() async {
        guard let old = packingUndo, let applied = packingProposed, packingOfferId == selectedOffer?.id else { return }
        if selection.bundleId == applied.bundleId { selection.bundleId = old.bundleId }
        selection.bags = undoV2(current: selection.bags, before: old.bags, applied: applied.bags) { item in item.passengerId + ":" + item.segmentId + ":" + (services.first(where: { $0.id == item.productId })?.type ?? item.productId) }
        selection.seats = undoV2(current: selection.seats, before: old.seats, applied: applied.seats) { $0.passengerId + ":" + $0.segmentId }
        selection.meals = undoV2(current: selection.meals, before: old.meals, applied: applied.meals) { $0.passengerId + ":" + $0.segmentId }
        if let id = packingRecommendationId { analytics.emit("recommendation_reversed", "baggage.packing", ["recommendationId": .string(id), "recommendationType": .string("baggage"), "recommendationVersion": .int(packingRecommendationVersion ?? 0)]) }
        packingUndo = nil; packingProposed = nil; packingRecommendationId = nil; packingRecommendationVersion = nil; packingRecommendationAction = nil
        selectionChanged("baggage_changed", component: "baggage.packing", product: "packing_undo"); await requote()
    }
    var retainsPackingRecommendation: Bool {
        guard packingRecommendationId != nil, let applied = packingProposed, let before = packingUndo, packingOfferId == selectedOffer?.id else { return false }
        let bundleKept = before.bundleId != applied.bundleId && selection.bundleId == applied.bundleId
        let bagKept = applied.bags.contains { !before.bags.contains($0) && selection.bags.contains($0) }
        // Accepting "keep" is a measurable outcome even when it changes no product.
        // Seats and meals may be edited later without changing the accepted bag allowance.
        let bagKeys: (V2BagSelection) -> String = { $0.passengerId + ":" + $0.segmentId + ":" + $0.productId }
        let keepAllowance = packingRecommendationAction == "keep" && selection.bundleId == applied.bundleId && Set(selection.bags.map(bagKeys)) == Set(applied.bags.map(bagKeys))
        return bundleKept || bagKept || keepAllowance
    }
    private func emitPackingRetention() {
        guard retainsPackingRecommendation, let id = packingRecommendationId else { return }
        analytics.emit("recommendation_retained", "baggage.packing", ["recommendationId": .string(id), "recommendationType": .string("baggage"), "recommendationVersion": .int(packingRecommendationVersion ?? 0)])
    }
    func importTrip(_ data: Data, mimeType: String = "image/jpeg") async {
        error = nil
        guard validImage(data, mimeType: mimeType) else { return }
        let revision = intent.revision; let operation = begin("import", "Reading the screenshot"); defer { end(operation) }
        do {
            let result: V2TripImport = try await send("import", path: "/api/v2/ai/trip-import", body: V2ImageBody(revision: revision, imageBase64: data.base64EncodedString(), mimeType: mimeType, context: .current))
            guard revision == intent.revision, result.revision == revision, result.source == "openai" else { return }
            tripImport = result; recordAI(result.requestId, model: result.model)
        } catch { if revision == intent.revision && !isCancellation(error) { self.error = "AI unavailable. Enter the trip details manually or retry."; tripImport = nil } }
    }
    func applyImport(_ imported: V2TripImport, bufferMinutes: Int) async {
        guard imported.revision == intent.revision else { error = "Search fields changed. Import again to avoid replacing your edits."; return }
        guard imported.unresolved.isEmpty, (0...1440).contains(bufferMinutes) else { error = "Confirm missing screenshot details before applying."; return }
        var next = intent
        var importNotice: String?
        if var incoming = imported.incomingFlight {
            guard imported.kind == "incoming_flight" else { error = "Choose whether this screenshot describes an event or an incoming flight."; return }
            guard incoming.confirmed else { error = "Confirm the incoming flight first."; return }
            guard !incoming.airline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let arrivalAirport = airports.first(where: { $0.code == incoming.arrivalAirport }),
                  let arrivalDate = V2Dates.instant(incoming.arrivalAt), (60...1440).contains(bufferMinutes) else {
                error = "Enter the incoming airline, a supported arrival airport, a valid arrival date/time with time zone, and a connection buffer of 60–1440 minutes."; return
            }
            incoming.minimumConnectionMinutes = bufferMinutes
            next.incomingFlight = incoming; next.originAirport = incoming.arrivalAirport; next.outboundDate = V2Dates.localDay(arrivalDate, zone: arrivalAirport.timeZone)
            next.tripType = "one_way"; next.returnDate = nil; next.dateWindow = nil; next.durationNights = nil
        } else {
            guard imported.kind == "event", let day = imported.localDate, let year = imported.year, let zone = imported.timeZone,
                  let airport = imported.airportCandidates.first, airports.contains(where: { $0.code == airport }),
                  let time = imported.localTime, let timeZone = TimeZone(identifier: zone) else {
                error = "Confirm the event airport, date, year, local time and time zone."; return
            }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd HH:mm"; formatter.isLenient = false
            guard day.hasPrefix(String(year) + "-"), let event = formatter.date(from: day + " " + time), formatter.string(from: event) == day + " " + time else { error = "Check the event date and time."; return }
            let deadline = ISO8601DateFormatter().string(from: event.addingTimeInterval(-Double(bufferMinutes * 60)))
            next.destinationAirports = [airport]; next.arrivalDeadline = deadline; next.outboundDate = day; next.dateWindow = nil; next.durationNights = nil
            importNotice = "Arrival buffer: \(bufferMinutes) minutes, supplied by you. Airport arrival is not venue arrival."
        }
        guard changedIntentFields(intent, next).isDisjoint(with: Set(intent.lockedFields)) else {
            error = "Unlock the affected requirement before applying this screenshot."; return
        }
        editIntent { $0 = next }
        error = nil; if let importNotice { notice = importNotice }
        tripImport = nil; analytics.emit("trip_imported", "search.import", ["choice": .string(imported.kind)]); await search()
    }
    func back() { let previous: [V2BookingStage: V2BookingStage] = [.results: .search, .configuration: .results, .review: .configuration, .confirmation: .search, .trips: .search]; analytics.emit("back_navigation", "navigation.back", ["previousScreen": .string(stage == .results ? "itinerary" : stage.rawValue)]); go(previous[stage] ?? .search) }
    func reset() { cancelEditingRequests(); completedOrder = nil; intent = V2SearchIntent(); invalidateBooking(preserveCompatible: false); syncPassengers(); offers = []; alternatives = []; comparison = nil; tripImport = nil; packingAssessment = nil; error = nil; notice = nil; analytics.startFlow(); go(.search) }
    func showTrips() { go(.trips) }
    func persist() {
        let draft = V2Draft(intent: intent, stage: stage, selectedOffer: selectedOffer, selection: selection, quote: quote, passengers: passengers, completedOrderId: completedOrder?.id, checkoutAttempt: checkoutAttempt, reviewedQuoteId: reviewedQuoteId, pendingCheckout: pendingCheckout, providerID: providerID)
        if let data = try? JSONEncoder().encode(orders) { defaults.set(data, forKey: "bookingV2Orders") }
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: "bookingV2Draft") }
    }
    private func syncPassengers(_ supplied: [V2PassengerScope]? = nil) {
        let scopes = supplied ?? (0..<max(0, intent.adults)).map { V2PassengerScope(id: "adult-\($0 + 1)", type: "adult", age: nil) } + intent.childAges.enumerated().map { V2PassengerScope(id: "child-\($0.offset + 1)", type: "child", age: $0.element) }
        passengers = scopes.map { scope in var person = passengers.first { $0.id == scope.id } ?? V2Passenger(id: scope.id, type: scope.type, age: scope.age); person.type = scope.type; person.age = scope.age; return person }
    }
    private func invalidateBooking(preserveCompatible: Bool = false) {
        if preserveCompatible, let selectedOffer, completedOrder == nil { compatibleSelection = (selectedOffer.id, selection) }
        else if !preserveCompatible { compatibleSelection = nil }
        selectedOffer = nil; quote = nil; reviewedQuoteId = nil; pendingCheckout = nil; selection = V2Selection(); services = []; seatMaps = []; packingOptions = []; packingUndo = nil; completedOrder = nil; checkoutAttempt = UUID().uuidString
    }
    private func changedIntentFields(_ before: V2SearchIntent, _ after: V2SearchIntent) -> Set<String> {
        guard let old = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(before)) as? NSDictionary,
              let new = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? NSDictionary else { return [] }
        return Set((old.allKeys.compactMap { $0 as? String }).filter { key in
            guard !["revision", "unresolved", "lockedFields"].contains(key) else { return false }
            let a = old[key] as? NSObject, b = new[key] as? NSObject
            return a != b
        })
    }
    private func sameNeeds(_ a: V2SearchIntent, _ b: V2SearchIntent) -> Bool { a.checkedBags == b.checkedBags && a.baggageScope == b.baggageScope && a.baggageDirection == b.baggageDirection && a.meals == b.meals && a.vegetarian == b.vegetarian && a.keepTogether == b.keepTogether }
    private func compatible(_ value: V2Selection, with offer: V2FlightOffer) -> V2Selection {
        let ids = Set(passengers.map(\.id)), segments = Set(offer.itinerary.segments.filter { !$0.independentlyBooked }.map(\.id))
        var result = value
        result.bags.removeAll { !ids.contains($0.passengerId) || !segments.contains($0.segmentId) }
        result.seats.removeAll { !ids.contains($0.passengerId) || !segments.contains($0.segmentId) }
        result.meals.removeAll { !ids.contains($0.passengerId) || !segments.contains($0.segmentId) }
        return result
    }
    private func confirmedTripIntent(_ itinerary: V2Itinerary) -> V2SearchIntent {
        var confirmed = intent
        let outbound = itinerary.segments.filter { $0.direction == "outbound" && !$0.independentlyBooked }
        if let first = outbound.first, let date = V2Dates.instant(first.departureAt) {
            confirmed.originAirport = first.origin.code; confirmed.outboundDate = V2Dates.localDay(date, zone: first.origin.timeZone)
            if let last = outbound.last { confirmed.destinationAirports = [last.destination.code] }
            confirmed.dateWindow = nil; confirmed.durationNights = nil
        }
        if let first = itinerary.segments.first(where: { $0.direction == "return" }), let date = V2Dates.instant(first.departureAt) { confirmed.returnDate = V2Dates.localDay(date, zone: first.origin.timeZone) }
        else { confirmed.returnDate = nil; confirmed.tripType = "one_way" }
        return confirmed
    }
    private func supportsAncillaries() -> Bool {
        guard selectedOffer?.effectiveCapabilities.ancillaries == true else { error = "Baggage and meal pricing is unavailable here. Confirm extras on Pegasus."; return false }
        return true
    }
    private func go(_ next: V2BookingStage) { stage = next; analytics.view(next == .results ? "itinerary" : next.rawValue); persist() }
    private func validImage(_ data: Data, mimeType: String) -> Bool { guard !data.isEmpty, data.count <= 4_000_000, ["image/jpeg", "image/png", "image/webp"].contains(mimeType) else { error = "Choose a JPEG, PNG or WebP photo smaller than 4 MB."; return false }; return true }
    private func recordAI(_ id: String, model: String) { lastAIRequestId = id; lastAIModel = model; analytics.emit("ai_request_finished", "ai.result", ["requestId": .string(id), "modelId": .string(model), "validationOutcome": .string("valid")]) }
    private func preservingLocked(_ incoming: V2SearchIntent, previous: V2SearchIntent) throws -> V2SearchIntent {
        var new = try JSONSerialization.jsonObject(with: JSONEncoder().encode(incoming)) as! [String: Any]
        let old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as! [String: Any]
        for field in previous.lockedFields { if let value = old[field] { new[field] = value } else { new.removeValue(forKey: field) } }
        new["lockedFields"] = previous.lockedFields
        return try JSONDecoder().decode(V2SearchIntent.self, from: JSONSerialization.data(withJSONObject: new))
    }
    private func begin(_ name: String, _ message: String) -> String { let id = name + UUID().uuidString; operations.insert(id); busy = true; if ["interpret", "packing", "import"].contains(name) { aiBusy = true }; busyMessage = message; analytics.beginLoading(); return id }
    private func end(_ id: String) { operations.remove(id); busy = !operations.isEmpty; aiBusy = operations.contains { $0.hasPrefix("interpret") || $0.hasPrefix("packing") || $0.hasPrefix("import") }; if !busy { busyMessage = "" }; analytics.endLoading() }
    private func cancel(_ name: String) { requests.removeValue(forKey: name)?.1.cancel() }
    private func cancelEditingRequests() { editSearchTask?.cancel(); for name in ["interpret", "search", "quote", "services", "compare", "alternatives", "packing", "packing-options", "import"] { cancel(name) }; aiBusy = false }
    private func send<Response: Decodable>(_ key: String, path: String, method: String = "POST") async throws -> Response { try await sendData(key, path: path, method: method, body: nil) }
    private func send<Body: Encodable, Response: Decodable>(_ key: String, path: String, body: Body) async throws -> Response { try await sendData(key, path: path, method: "POST", body: JSONEncoder().encode(body)) }
    private func sendData<Response: Decodable>(_ key: String, path: String, method: String, body: Data?) async throws -> Response {
        cancel(key); let token = UUID(), api = client
        let task = Task { try await api.request(path: path, method: method, body: body) }
        requests[key] = (token, task)
        defer { if requests[key]?.0 == token { requests.removeValue(forKey: key) } }
        let data = try await task.value; try Task.checkCancellation()
        guard !task.isCancelled, requests[key]?.0 == token else { throw CancellationError() }
        return try JSONDecoder().decode(Response.self, from: data)
    }
    private func isCancellation(_ error: Error) -> Bool { error is CancellationError || (error as? URLError)?.code == .cancelled }
    private func message(_ error: Error) -> String { if let value = error as? LocalizedError, let description = value.errorDescription { return description }; return "The service is unavailable. Your edits are saved. Check the backend connection and retry." }
    private func cacheKey(_ intent: V2SearchIntent) -> String { var normalized = intent; normalized.revision = 0; let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; return "bookingV2Search." + providerID + "." + ((try? encoder.encode(normalized).base64EncodedString()) ?? "") }
}
private func undoV2<T: Equatable>(current: [T], before: [T], applied: [T], key: (T) -> String) -> [T] {
    var result = current
    for scope in Set((before + applied).map(key)) where current.filter({ key($0) == scope }) == applied.filter({ key($0) == scope }) {
        if before.filter({ key($0) == scope }) != applied.filter({ key($0) == scope }) { result.removeAll { key($0) == scope }; result += before.filter { key($0) == scope } }
    }
    return result
}
