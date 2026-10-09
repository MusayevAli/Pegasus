import Foundation
import TripFitCore

/// Runs the exact native observable models, without a SwiftUI renderer or iOS Simulator.
/// This is an integration test of models/persistence/networking, not a native UI test.
@main struct NativeModelDemo {
    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let keys = ["tripfitDraft", "tripfitTrips", "analyticsConsent", "analyticsQueue", "analyticsState", "backendURL", "uploadToken"]
        let backup = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        for key in keys { defaults.removeObject(forKey: key) }
        defer { for key in keys { if let value = backup[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.set(true, forKey: "analyticsConsent")
        let offline = ProcessInfo.processInfo.environment["TRIPFIT_OFFLINE_TEST"] == "1"
        let backend = offline ? "offline://local-model-test" : ProcessInfo.processInfo.environment["TRIPFIT_BACKEND_URL"] ?? "http://127.0.0.1:3001"
        defaults.set(backend, forKey: "backendURL")
        try verifyAnalyticsRelaunch(defaults: defaults)
        guard let milliseconds = QuoteExpiry.date("2026-10-03T20:30:45.123Z"), let seconds = QuoteExpiry.date("2026-10-03T20:30:45Z") else { throw Failure.failed("Quote expiration must accept both server timestamp precisions") }
        try check(abs(milliseconds.timeIntervalSince(seconds) - 0.123) < 0.000_001, "Fractional quote expiration lost its precision")
        try check(QuoteExpiry.date("invalid") == nil, "Malformed quote expiration must remain invalid")
        var store = BookingStore()
        store.analytics.inactivitySeconds = 0.10
        store.demo(.barcelonaFamily)
        guard let itinerary = store.results.first else { throw Failure.failed("No family inventory") }
        store.choose(itinerary)
        guard let family = store.recommendations.first(where: { $0.selection.bundle == .family }) else { throw Failure.failed("No eligible cheaper family bundle") }
        store.visible(family); store.expand(family); store.apply(family)
        try check(store.total == 77700, "Expected €777 family total including return upgrades")
        store.navigate(.baggage)
        let baselineExtras = store.selection.extras
        store.setBag("peg-cabin", passenger: "adult-1", segment: "family-in")
        store.removeBag("peg-checked25", passenger: "adult-1", segment: "family-in")
        try check(store.selection.extras.contains { $0.passengerID == "adult-1" && $0.segmentID == "family-in" && $0.productID == "peg-cabin" }, "Removing a checked bag also removed the unrelated cabin bag")
        try check(store.selection.extras.filter { $0.passengerID != "adult-1" || $0.segmentID != "family-in" } == baselineExtras.filter { $0.passengerID != "adult-1" || $0.segmentID != "family-in" }, "Removing a bag changed another traveller or flight")
        store.setBag("peg-checked25", passenger: "adult-1", segment: "family-in")
        store.removeBag("peg-cabin", passenger: "adult-1", segment: "family-in")
        try check(store.selection.extras.contains { $0.passengerID == "adult-1" && $0.segmentID == "family-in" && $0.productID == "peg-checked25" }, "Removing a cabin bag also removed the unrelated checked bag")
        store.setBag("peg-cabin", passenger: "adult-1", segment: "family-in")
        store.setBag(nil, passenger: "adult-1", segment: "family-in")
        try check(!store.selection.extras.contains { $0.passengerID == "adult-1" && $0.segmentID == "family-in" }, "Included-allowance action must still remove all paid bags for its selected scope")
        store.setBag("peg-checked25", passenger: "adult-1", segment: "family-in")
        try check(Set(store.selection.extras) == Set(baselineExtras) && store.total == 77700, "Baggage regression test did not restore the original booking")
        try await Task.sleep(for: .milliseconds(220))
        store.analytics.checkpoint()
        let beforeBackground = store.analytics.queue.count
        store.analytics.setForeground(false)
        try await Task.sleep(for: .milliseconds(120))
        store.analytics.checkpoint()
        // setForeground checkpoints the visible tail; the later background checkpoint adds nothing.
        let afterBackground = store.analytics.queue.count
        try await Task.sleep(for: .milliseconds(120))
        store.analytics.checkpoint()
        try check(store.analytics.queue.count == afterBackground, "Background time must not accrue")
        try check(afterBackground >= beforeBackground, "Event queue changed unexpectedly")
        store.analytics.setForeground(true)
        store.navigate(.seats); store.navigate(.meals); store.navigate(.review)
        let reviewedTotal = store.total
        try check(Validation.review(request: store.request, itinerary: itinerary, selection: store.selection).filter { $0.severity == .error }.isEmpty, "Review must be valid")
        store.navigate(.checkout)
        let pendingAttempt = store.paymentAttempt
        store = BookingStore()
        try check(store.step == .review && store.completedTrip == nil, "Pending checkout must resume at review")
        try check(store.paymentAttempt == pendingAttempt && store.total == reviewedTotal, "Pending checkout relaunch changed the payment attempt or total")
        store.navigate(.checkout)
        await store.completeDemo()
        await store.completeDemo() // Duplicate submission must not create a second booking.
        try check(store.step == .confirmation, "Flow did not reach confirmation")
        try check(store.trips.count == 1, "Duplicate checkout created another trip")
        try check(store.completedTrip?.totalCents == reviewedTotal, "Confirmation total changed")
        try check(store.completedTrip?.id.hasPrefix("DEMO-") == true, "Demo reference missing")
        let firstReference = store.completedTrip!.id
        let firstFlowID = store.analytics.flowID
        store = BookingStore()
        try check(store.step == .confirmation && store.completedTrip?.id == firstReference, "Completed booking relaunch did not restore its confirmation")
        try check(store.paymentAttempt == pendingAttempt, "Completed booking relaunch changed its payment attempt")
        await store.completeDemo()
        try check(store.trips.count == 1 && store.completedTrip?.id == firstReference, "Completed booking relaunch allowed a duplicate trip")
        if let draftData = defaults.data(forKey: "tripfitDraft"), var legacyDraft = try JSONSerialization.jsonObject(with: draftData) as? [String: Any] {
            legacyDraft.removeValue(forKey: "paymentAttempt")
            legacyDraft.removeValue(forKey: "completedTripID")
            defaults.set(try JSONSerialization.data(withJSONObject: legacyDraft), forKey: "tripfitDraft")
            store = BookingStore()
            try check(store.step == .confirmation && store.completedTrip?.id == firstReference, "A legacy completed draft could not recover its saved confirmation")
            await store.completeDemo()
            try check(store.trips.count == 1, "Migrating a legacy completed draft allowed a duplicate trip")
        } else { throw Failure.failed("Completed draft could not be read for migration verification") }
        guard let data = defaults.data(forKey: "tripfitTrips") else { throw Failure.failed("Trip was not persisted") }
        let saved = try JSONDecoder().decode([SavedTrip].self, from: data)
        try check(saved.count == 1 && saved[0].totalCents == reviewedTotal, "Saved trip did not match confirmation")
        store.navigate(.trips)
        store = BookingStore()
        try check(store.step == .trips && store.completedTrip?.id == firstReference, "My Trips relaunch did not preserve the completed booking")
        let completedAttempt = store.paymentAttempt
        store.request = Catalog.demoSearch(.soloLight)
        store.needs = Catalog.demoNeeds(.soloLight)
        store.performSearch()
        try check(store.completedTrip == nil && store.paymentAttempt != completedAttempt, "A fresh search kept the prior booking completion or payment attempt")
        try check(store.analytics.flowID != firstFlowID, "A fresh search after completion did not start a new analytics flow")
        guard let nextItinerary = store.results.first else { throw Failure.failed("Fresh search has no inventory") }
        store.choose(nextItinerary)
        store.navigate(.review); store.navigate(.checkout)
        await store.completeDemo()
        try check(store.step == .confirmation && store.trips.count == 2, "Fresh search could not complete another booking")
        try check(store.completedTrip?.id != firstReference && store.completedTrip?.totalCents == 4500, "Fresh booking reused the old reference or total")
        guard let finalTripData = defaults.data(forKey: "tripfitTrips") else { throw Failure.failed("Second trip was not persisted") }
        try check(try JSONDecoder().decode([SavedTrip].self, from: finalTripData).count == 2, "Second booking was not saved")
        await store.analytics.flush()
        let sessionID = store.analytics.sessionID
        var responseKeys: [String] = []
        if offline {
            try check(store.analytics.queue.contains { $0.name == "demo_booking_completed" }, "Offline completion event was not queued")
        } else {
            try check(store.analytics.queue.isEmpty, "Analytics did not upload: \(store.analytics.status)")
            let (responseData, response) = try await URLSession.shared.data(from: URL(string: backend + "/api/sessions/" + sessionID)!)
            try check((response as? HTTPURLResponse)?.statusCode == 200, "Dashboard cannot read the emitted session")
            guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else { throw Failure.failed("Invalid session response") }
            responseKeys = Array(json.keys).sorted()
            let encoded = String(data: responseData, encoding: .utf8) ?? ""
            try check(encoded.contains("demo_booking_completed"), "Dashboard timeline has no completion")
        }
        let report: [String: Any] = [
            "verification": "Headless execution of actual native Swift models; iOS UI and Simulator not tested",
            "sessionId": sessionID,
            "flowId": firstFlowID,
            "demoReference": firstReference,
            "secondFlowId": store.analytics.flowID,
            "secondDemoReference": store.completedTrip?.id ?? "",
            "secondBookingTotalCents": store.completedTrip?.totalCents ?? 0,
            "totalCents": reviewedTotal,
            "currency": "EUR",
            "persistedTrips": store.trips.count,
            "dashboardSessionResponseKeys": responseKeys,
            "analyticsUploaded": !offline,
            "offlineQueueCount": store.analytics.queue.count,
            "baggageToggleScopeVerified": true,
            "quoteExpiryPrecisionVerified": true,
            "analyticsRelaunchIdentityVerified": true,
            "analyticsOptOutResetVerified": true,
            "pendingCheckoutAttemptRestored": true,
            "completionRelaunchIdempotencyVerified": true,
            "legacyCompletedDraftMigrationVerified": true,
            "freshSearchAfterCompletionVerified": true,
            "duplicateCheckoutProtected": true,
            "backgroundTimingVerified": true,
            "noChargeOrRealTicket": true
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: reportData, encoding: .utf8)!)
        store.analytics.enabled = false
    }
    @MainActor static func verifyAnalyticsRelaunch(defaults: UserDefaults) throws {
        var original: Analytics? = Analytics()
        original?.startFlow()
        original?.emit("search_submitted", "search.submit")
        original?.view("review")
        let sessionID = original!.sessionID, flowID = original!.flowID
        let queuedIDs = original!.queue.map(\.id)
        let previousSequence = original!.queue.map(\.sequence).max()!
        original = nil

        var restored: Analytics? = Analytics()
        try check(restored!.sessionID == sessionID && restored!.flowID == flowID, "Analytics identity changed while restoring an unfinished booking")
        try check(restored!.queue.map(\.id) == queuedIDs, "Relaunch lost or replaced queued event IDs")
        restored?.view("review")
        restored?.emit("checkout_started", "checkout.demo")
        try check(restored!.queue.last!.sequence > previousSequence, "Relaunch reused an event sequence number")
        try check(Set(restored!.queue.map(\.sequence)).count == restored!.queue.count, "Restored session contains duplicate sequence numbers")
        try check(restored!.queue.last!.sessionId == sessionID && restored!.queue.last!.flowId == flowID, "Resumed checkout belongs to a different flow than its search")
        restored?.enabled = false
        try check(restored!.queue.isEmpty && defaults.data(forKey: "analyticsState") == nil && defaults.data(forKey: "analyticsQueue") == nil, "Opt-out left local analytics or stable identity behind")
        try check(restored!.sessionID != sessionID && restored!.flowID != flowID, "Opt-out did not rotate analytics identity")
        restored?.enabled = true
        restored?.emit("screen_viewed", "screen.search")
        try check(restored!.queue.count == 1 && restored!.queue[0].sequence == 1, "New consent recovered old queue or sequence")
        try check(restored!.queue[0].sessionId != sessionID, "New consent linked to the previous analytics identity")
        restored?.enabled = false
        restored = nil
        defaults.set(true, forKey: "analyticsConsent")
    }
    static func check(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.failed(message) } }
    enum Failure: Error { case failed(String) }
}
