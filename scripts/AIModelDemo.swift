import Foundation
import TripFitCore

private struct MockAIClient: AIPlanningClient {
    var needs: AIPlanNeeds = AIPlanNeeds()
    var delayMilliseconds = 0
    var failure = false
    var stale = false
    func aiConnection() async throws -> AIConnection { AIConnection(configured: true, model: "test-fixture-model", features: ["trip_plan"]) }
    func tripPlan(_ request: AIPlanRequest) async throws -> AITripPlan {
        if delayMilliseconds > 0 { try await Task.sleep(for: .milliseconds(delayMilliseconds)) }
        if failure { throw URLError(.timedOut) }
        return AITripPlan(revision: request.revision + (stale ? 1 : 0), source: "openai", model: "test-fixture-model", summary: "Structured response fixture for model tests; no live AI request.", needs: needs, clarifications: [], notice: "Test fixture")
    }
}

private actor RecordingAIClient: AIPlanningClient {
    var captured: AIPlanRequest?
    var needs: AIPlanNeeds
    init(needs: AIPlanNeeds = AIPlanNeeds()) { self.needs = needs }
    func aiConnection() async throws -> AIConnection { AIConnection(configured: true, model: "test-fixture-model", features: ["trip_plan"]) }
    func tripPlan(_ request: AIPlanRequest) async throws -> AITripPlan {
        captured = request
        return AITripPlan(revision: request.revision, source: "openai", model: "test-fixture-model", summary: "Captured request fixture", needs: needs, clarifications: [], notice: "Test fixture")
    }
}

@main struct AIModelDemo {
    @MainActor static var assertions = 0
    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let keys = ["tripfitDraft", "tripfitTrips", "analyticsConsent", "analyticsQueue", "analyticsState", "backendURL", "uploadToken"]
        let backup = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { for key in keys { if let value = backup[key] ?? nil { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set(false, forKey: "analyticsConsent")
        defaults.set("offline://ai-model-tests", forKey: "backendURL")

        let familyNeeds = AIPlanNeeds(giftsOnReturn: true, stayTogether: true, noAlcohol: true, checkedBagEachWay: true, mealsEachFlight: true)
        let family = try fresh(.barcelonaFamily)
        let originalSelection = family.selection, originalNeeds = family.needs
        await family.checkAIConnection(client: MockAIClient())
        try check(family.aiConnection?.configured == true && family.aiConnection?.model == "test-fixture-model", "Configured AI status did not decode")
        let recording = RecordingAIClient(needs: familyNeeds)
        await family.makeAITripPlan(note: "Confirmed family needs", client: recording)
        let captured = try require(await recording.captured, "Plan request was not captured")
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(captured)) as! [String: Any]
        let allowedPreferences = Set(["light", "gifts", "business", "sports", "together", "budget", "vegetarian", "no_alcohol", "child_meal"])
        try check(Set(payload["preferences"] as? [String] ?? []).isSubset(of: allowedPreferences), "Serialized plan request has unsupported backend preference values")
        try check(Set(captured.preferences) == Set(["gifts", "together", "no_alcohol", "child_meal"]), "Existing family preferences were not mapped to the backend contract")
        try check(family.selection == originalSelection && family.needs == originalNeeds && family.total == 49500, "Requesting an AI plan silently changed a purchase or preference")
        let plan = try require(family.aiTripPlan, "Family plan missing")
        let proposal = try require(family.proposal(for: plan), "Family proposal invalid")
        try check(proposal.totalCents == 77700 && proposal.deltaCents == 28200, "Family total differs from deterministic catalogue €777")
        try check(proposal.selection.bundle == .family && proposal.selection.seats.count == 6 && proposal.selection.meals.count == 6, "Family proposal missed bundle, travellers or flights")
        try check(proposal.changes.contains { $0.contains("Child 1") && $0.contains("Return BCN–SAW") } && proposal.changes.contains { $0.contains("Adult 2") && $0.contains("Outbound SAW–BCN") }, "Preview omitted passenger/flight scope")
        try check(!family.canUndoAIPlan, "Unapplied plan must not create undo state")
        family.applyAITripPlan(plan)
        try check(family.total == 77700 && family.canUndoAIPlan, "Explicit apply did not commit the validated proposal")
        family.setSeat("4F", passenger: "adult-1", segment: "family-out")
        family.setBag("peg-cabin", passenger: "adult-2", segment: "family-out")
        family.preference("noAlcohol") { family.needs.noAlcohol = false }
        family.undoAITripPlan()
        try check(family.selection.seats == [SeatSelection(passengerID: "adult-1", segmentID: "family-out", seatID: "4F")], "Undo lost a later manually chosen seat")
        try check(family.selection.extras == [ExtraSelection(passengerID: "adult-2", segmentID: "family-out", productID: "peg-cabin")], "Undo lost a later unrelated cabin bag or kept generated checked bags")
        try check(family.selection.meals.isEmpty && family.selection.bundle == .basic && !family.needs.noAlcohol && !family.canUndoAIPlan, "Undo failed to restore original purchases or preserve a later preference")

        let solo = try fresh(.soloLight)
        solo.setBag("peg-cabin", passenger: "adult-1", segment: "solo-out")
        solo.setSeat("4A", passenger: "adult-1", segment: "solo-out")
        solo.setMeal("peg-meal-classic", passenger: "adult-1", segment: "solo-out")
        let lightPlan = fixture(revision: solo.revision, needs: AIPlanNeeds(travellingLight: true))
        let light = try require(solo.proposal(for: lightPlan), "Light plan missing")
        try check(light.totalCents == 7400 && light.deltaCents == -1800 && light.selection.extras.isEmpty, "Light plan did not remove the unneeded cabin purchase")
        try check(light.selection.seats == solo.selection.seats && light.selection.meals == solo.selection.meals, "Light plan removed unrelated seats or meals")
        let noMeals = try require(solo.proposal(for: fixture(revision: solo.revision, needs: AIPlanNeeds(travellingLight: true, mealsEachFlight: false))), "Explicit no-meal proposal missing")
        try check(noMeals.selection.meals.isEmpty && noMeals.selection.seats == solo.selection.seats && noMeals.totalCents == 6000, "Explicit no-meal choice must remove only meals while preserving seats")
        let plainSolo = try fresh(.soloLight)
        try check(plainSolo.proposal(for: fixture(revision: plainSolo.revision, needs: AIPlanNeeds(travellingLight: true)))?.totalCents == 4500, "Included solo allowance must stay €45")

        let vegetarian = try fresh(.barcelonaFamily)
        vegetarian.setMeal("peg-meal-classic", passenger: "adult-1", segment: "family-out")
        vegetarian.setMeal("peg-meal-classic", passenger: "child-1", segment: "family-out")
        let veggie = try require(vegetarian.proposal(for: fixture(revision: vegetarian.revision, needs: AIPlanNeeds(vegetarian: true))), "Vegetarian proposal missing")
        try check(veggie.selection.meals.first { $0.passengerID == "adult-1" }?.productID == "peg-meal-veggie", "Adult vegetarian request did not replace the adult meal")
        try check(veggie.selection.meals.first { $0.passengerID == "child-1" }?.productID == "peg-meal-classic", "Adult vegetarian request changed a child's manual meal")
        try check(veggie.selection.extras.isEmpty && veggie.selection.seats.isEmpty && veggie.selection.meals.count == 2, "Dietary preference generated unrelated purchases")

        let unchanged = try fresh(.barcelonaFamily)
        let empty = fixture(revision: unchanged.revision, needs: AIPlanNeeds())
        let noteRecorder = RecordingAIClient()
        await unchanged.makeAITripPlan(note: String(repeating: "x", count: 650), client: noteRecorder)
        let truncated = try require(await noteRecorder.captured, "Long note request missing")
        try check(truncated.note.count == 600, "Plan note must respect the backend 600-character limit")
        let emptyProposal = try require(unchanged.proposal(for: empty), "Empty plan should return an unchanged preview")
        try check(emptyProposal.selection == unchanged.selection && emptyProposal.needs == unchanged.needs && emptyProposal.deltaCents == 0 && emptyProposal.changes.isEmpty, "No explicit needs unexpectedly changed booking")
        let alcoholOnly = try require(unchanged.proposal(for: fixture(revision: unchanged.revision, needs: AIPlanNeeds(noAlcohol: false))), "Alcohol-only preference missing")
        try check(alcoholOnly.selection == unchanged.selection && alcoholOnly.totalCents == unchanged.total, "A preference about alcohol generated baggage or meal purchases")
        unchanged.applyAITripPlan(empty)
        try check(!unchanged.canUndoAIPlan, "Applying an empty plan should be a no-op")

        let stale = try fresh(.soloLight)
        let oldPlan = fixture(revision: stale.revision, needs: AIPlanNeeds(travellingLight: true))
        stale.setSeat("4B", passenger: "adult-1", segment: "solo-out")
        let manual = stale.selection
        try check(stale.proposal(for: oldPlan) == nil, "Stale proposal was not rejected")
        stale.applyAITripPlan(oldPlan)
        try check(stale.selection == manual && !stale.canUndoAIPlan, "Stale apply mutated the booking")
        let pending = Task { @MainActor in await stale.makeAITripPlan(note: "Travel light", client: MockAIClient(needs: AIPlanNeeds(travellingLight: true), delayMilliseconds: 100)) }
        try await Task.sleep(for: .milliseconds(20))
        stale.setBag("peg-cabin", passenger: "adult-1", segment: "solo-out")
        await pending.value
        try check(stale.aiTripPlan == nil && stale.aiPlanStatus.contains("changed"), "A late response survived a booking revision change")
        await stale.makeAITripPlan(note: "Travel light", client: MockAIClient(needs: AIPlanNeeds(travellingLight: true), stale: true))
        try check(stale.aiTripPlan == nil, "A backend response with the wrong revision was accepted")

        let invalid = try fresh(.soloLight)
        let badNeeds = AIPlanNeeds(packingItems: ["passport_photo"])
        try check(!AIPlanner.validate(fixture(revision: invalid.revision, needs: badNeeds)), "Unknown packing category was accepted")
        await invalid.makeAITripPlan(note: "hello", client: MockAIClient(needs: badNeeds))
        try check(invalid.aiTripPlan?.source == "local" && invalid.selection == BookingSelection(), "Malformed output did not fall back locally without purchases")
        let malformedJSON = Data("{\"revision\":0,\"source\":\"openai\",\"summary\":\"x\",\"needs\":{\"travellingLight\":\"yes\",\"packingItems\":[]},\"clarifications\":[],\"notice\":\"x\"}".utf8)
        try check((try? JSONDecoder().decode(AITripPlan.self, from: malformedJSON)) == nil, "Wrong JSON field types decoded as a valid plan")
        let conflict = fixture(revision: invalid.revision, needs: AIPlanNeeds(travellingLight: true, checkedBagEachWay: true))
        try check(invalid.proposal(for: conflict) == nil, "Conflicting light/checked preferences became a purchase proposal")

        let fallback = try fresh(.barcelonaFamily)
        let familyText = "We need checked bags and meals for everyone on each flight, seats together and space for gifts on the return. No alcohol."
        await fallback.makeAITripPlan(note: familyText, client: MockAIClient(failure: true))
        let local = try require(fallback.aiTripPlan, "Local fallback plan missing")
        try check(local.source == "local" && local.model == nil && local.notice.contains("not an AI"), "Local helper is being presented as live AI")
        try check(fallback.proposal(for: local)?.totalCents == 77700, "Local family sample does not match catalogue price")
        let negative = AIPlanner.localPlan(note: "No gifts. Not vegetarian. Don't sit together. No checked bags. No meals.", revision: 0)
        try check(negative.needs.giftsOnReturn == false && negative.needs.vegetarian == false && negative.needs.stayTogether == false && negative.needs.checkedBagEachWay == false && negative.needs.mealsEachFlight == false, "Local helper reversed a negative preference")
        let soloText = AIPlanner.localPlan(note: "I am travelling light with one small backpack. No checked bags and no meals. Keep my existing seat choices.", revision: plainSolo.revision)
        try check(plainSolo.proposal(for: soloText)?.totalCents == 4500, "Local solo sample should keep the included allowance")
        let beforeDismiss = fallback.selection
        fallback.dismissAITripPlan()
        try check(fallback.aiTripPlan == nil && fallback.selection == beforeDismiss, "Dismiss changed a purchase")
        let retained = try fresh(.barcelonaFamily)
        retained.analytics.enabled = true
        let retainedPlan = fixture(revision: retained.revision, needs: familyNeeds)
        retained.applyAITripPlan(retainedPlan)
        retained.setSeat("4F", passenger: "adult-1", segment: "family-out")
        await retained.completeDemo()
        try check(retained.analytics.queue.contains { event in
            if event.name == "recommendation_retained", case .string(let id) = event.properties["recommendationId"] { return id == retainedPlan.id }; return false
        }, "An AI plan with retained applied scopes was missing its confirmation event")
        retained.analytics.enabled = false
        let reversed = try fresh(.soloLight)
        reversed.setBag("peg-cabin", passenger: "adult-1", segment: "solo-out")
        reversed.analytics.enabled = true
        let reversedPlan = fixture(revision: reversed.revision, needs: AIPlanNeeds(travellingLight: true))
        reversed.applyAITripPlan(reversedPlan)
        reversed.undoAITripPlan()
        await reversed.completeDemo()
        try check(!reversed.analytics.queue.contains { event in
            if event.name == "recommendation_retained", case .string(let id) = event.properties["recommendationId"] { return id == reversedPlan.id }; return false
        }, "An undone AI plan was counted as retained")
        reversed.analytics.enabled = false
        let httpTest = ProcessInfo.processInfo.environment["TRIPFIT_AI_HTTP_TEST"] == "1"
        if httpTest {
            let baseURL = ProcessInfo.processInfo.environment["TRIPFIT_BACKEND_URL"] ?? "http://127.0.0.1:3001"
            let api = BackendAPI(baseURL: baseURL)
            let connection = try await api.aiConnection()
            try check(!connection.configured && connection.features.contains("trip_plan"), "HTTP fallback test expects a backend without OpenAI credentials and with trip_plan support")
            let httpStore = try fresh(.barcelonaFamily)
            let httpRequest = AIPlanRequest(revision: httpStore.revision, note: familyText, journeyId: "family", passengerTypes: ["adult", "adult", "child"], segmentIds: ["family-out", "family-in"], preferences: ["gifts", "together", "no_alcohol", "child_meal"])
            let serverPlan = try await api.tripPlan(httpRequest)
            try check(serverPlan.source == "local" && serverPlan.needs.checkedBagEachWay == true && serverPlan.needs.mealsEachFlight == true && serverPlan.needs.stayTogether == true && serverPlan.needs.giftsOnReturn == true, "Actual HTTP response lost confirmed family scope")
            await httpStore.makeAITripPlan(note: familyText, client: api)
            try check(httpStore.aiTripPlan == serverPlan, "BookingStore silently fell back on the client instead of accepting the backend HTTP response")
            try check(httpStore.selection == BookingSelection() && httpStore.proposal(for: serverPlan)?.totalCents == 77700, "Actual HTTP plan mutated purchases or changed the family catalogue total")
        }
        let result: [String: Any] = ["verification": httpTest ? "Native AI models with mocked responses and actual local backend HTTP fallback; no live OpenAI request" : "Mocked structured responses against actual native AI planning models; no live OpenAI request", "assertions": assertions, "familyTotalCents": 77700, "soloTotalCents": 4500, "currency": "EUR", "staleResponsesRejected": true, "explicitApplyRequired": true, "undoPreservesManualChoices": true, "malformedOutputFallback": true, "localHelperNegationsVerified": true, "serializedBackendContractVerified": true, "retainedAndReversedLifecycleVerified": true, "actualHTTPContractVerified": httpTest]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
    @MainActor static func fresh(_ preset: DemoJourney) throws -> BookingStore {
        UserDefaults.standard.removeObject(forKey: "tripfitDraft")
        UserDefaults.standard.removeObject(forKey: "tripfitTrips")
        let store = BookingStore(); store.demo(preset)
        guard let itinerary = store.results.first else { throw Failure.failed("Demo inventory missing") }
        store.choose(itinerary)
        return store
    }
    static func fixture(revision: Int, needs: AIPlanNeeds) -> AITripPlan { AITripPlan(revision: revision, source: "openai", model: "test-fixture-model", summary: "Test plan", needs: needs, clarifications: [], notice: "Mocked response") }
    @MainActor static func check(_ condition: Bool, _ message: String) throws { assertions += 1; if !condition { throw Failure.failed(message) } }
    static func require<T>(_ value: T?, _ message: String) throws -> T { guard let value else { throw Failure.failed(message) }; return value }
    enum Failure: Error { case failed(String) }
}
