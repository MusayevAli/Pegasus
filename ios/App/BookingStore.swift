import Foundation
import Observation
import TripFitCore

enum BookingStep: String, Codable, CaseIterable {
    case search, itinerary, configuration, baggage, seats, meals, review, checkout, confirmation, trips
    var title: String { switch self {
    case .search: "Your next chapter."; case .itinerary: "A good journey starts here."
    case .configuration: "Make it your trip."; case .baggage: "Room for what matters."
    case .seats: "Your place in the sky."; case .meals: "Something to look forward to."
    case .review: "Everything, just right."; case .checkout: "Ready when you are."
    case .confirmation: "You're all set."; case .trips: "My trips."
    } }
}
struct SavedTrip: Codable, Identifiable {
    var id: String
    var created: Date
    var request: SearchRequest
    var itinerary: Itinerary
    var selection: BookingSelection
    var totalCents: Int
}
private struct Draft: Codable {
    var request: SearchRequest; var needs: TripNeeds; var itinerary: Itinerary?
    var selection: BookingSelection; var step: BookingStep
    var paymentAttempt: String?
    var completedTripID: String?
}

@MainActor @Observable final class BookingStore {
    var request = Catalog.demoSearch(.barcelonaFamily)
    var needs = Catalog.demoNeeds(.barcelonaFamily)
    var itinerary: Itinerary?
    var selection = BookingSelection()
    var step: BookingStep = .search
    var results: [Itinerary] = []
    var rejected: [RejectedItinerary] = []
    var error: String?
    var notice: String?
    var loading = false
    var revision = 0
    var recommendations: [Recommendation] = []
    var dismissed = Set<String>()
    var expanded = Set<String>()
    var seen = Set<String>()
    var undoSelections: [String: BookingSelection] = [:]
    var appliedRecommendations: [String: Recommendation] = [:]
    var trips: [SavedTrip] = []
    var completedTrip: SavedTrip?
    var aiEnabled = false
    var aiBusy = false
    var aiCards: [GuidanceCard] = []
    var aiStatus = "Local guidance · no AI connection needed"
    var aiTripPlan: AITripPlan?
    var aiPlanBusy = false
    var aiPlanStatus = "Describe your trip to preview changes. Your choices stay unchanged until you apply."
    var aiConnection: AIConnection?
    private var aiPlanUndo: AIPlanUndo?
    private var aiPlanRequestID = UUID()
    var canUndoAIPlan: Bool { aiPlanUndo != nil && completedTrip == nil }
    var paymentBusy = false
    var paymentAttempt = UUID().uuidString
    let analytics = Analytics()

    init() {
        if let data = UserDefaults.standard.data(forKey: "tripfitTrips"), let t = try? JSONDecoder().decode([SavedTrip].self, from: data) { trips = t }
        if let data = UserDefaults.standard.data(forKey: "tripfitDraft"), let d = try? JSONDecoder().decode(Draft.self, from: data) {
            request = d.request; needs = d.needs; itinerary = d.itinerary; selection = d.selection
            if let attempt = d.paymentAttempt, !attempt.isEmpty { paymentAttempt = attempt }
            completedTrip = trips.first { trip in
                trip.id == d.completedTripID || (d.paymentAttempt != nil && trip.id == "DEMO-" + String(paymentAttempt.prefix(8)).uppercased())
            }
            // Older completed drafts predate the identity fields. Recover only an exact saved
            // confirmation, never an unrelated trip merely because My Trips was open.
            if completedTrip == nil, d.completedTripID == nil, d.paymentAttempt == nil, d.step == .confirmation {
                completedTrip = trips.first { $0.request == d.request && $0.itinerary == d.itinerary && $0.selection == d.selection }
            }
            if completedTrip != nil { step = d.step == .trips ? .trips : .confirmation }
            else { step = (d.step == .checkout || d.step == .confirmation) ? .review : d.step }
        }
        results = Catalog.search(request).itineraries
        if completedTrip == nil { refreshRecommendations() }
        analytics.view(step.rawValue)
        persist()
    }
    var passengers: [Passenger] { request.passengers }
    var quote: Quote? { itinerary.map { Pricing.quote(itinerary: $0, passengers: passengers, selection: selection) } }
    var total: Int { quote?.totalCents ?? 0 }
    var imageName: String { request.destination == "BCN" ? "barcelona" : request.destination == "AYT" ? "antalya" : "istanbul" }
    func persist() {
        let d = Draft(request: request, needs: needs, itinerary: itinerary, selection: selection, step: step, paymentAttempt: paymentAttempt, completedTripID: completedTrip?.id)
        // Save the trip before its draft reference. A interrupted draft write can recover it
        // from the unchanged payment attempt rather than create another booking.
        if let data = try? JSONEncoder().encode(trips) { UserDefaults.standard.set(data, forKey: "tripfitTrips") }
        if let data = try? JSONEncoder().encode(d) { UserDefaults.standard.set(data, forKey: "tripfitDraft") }
    }
    func navigate(_ next: BookingStep, back: Bool = false) {
        analytics.interact()
        if back { analytics.emit("back_navigation", "navigation.back", ["previousScreen": .string(step.rawValue)]) }
        else if next != .trips && next != .search { analytics.emit("step_completed", "navigation.continue") }
        step = next; analytics.view(next.rawValue); persist()
    }
    func back() {
        let previous: [BookingStep: BookingStep] = [.itinerary:.search,.configuration:.itinerary,.baggage:.configuration,.seats:.baggage,.meals:.seats,.review:.configuration,.checkout:.review,.confirmation:.search,.trips:.search]
        navigate(previous[step] ?? .search, back: true)
    }
    func demo(_ preset: DemoJourney) {
        request = Catalog.demoSearch(preset); needs = Catalog.demoNeeds(preset)
        beginNewBooking()
        performSearch()
    }
    func performSearch() {
        if completedTrip != nil { beginNewBooking() }
        error = nil; analytics.interact()
        let result = Catalog.search(request)
        analytics.emit("search_submitted", "search.submit", ["origin": .string(request.origin), "destination": .string(request.destination), "partySize": .int(passengers.count)])
        results = result.itineraries; rejected = result.rejected
        let blockers = result.issues.filter { $0.severity == .error }
        if !blockers.isEmpty { error = blockers.map(\.message).joined(separator: "\n"); analytics.emit("validation_error", "search.form", ["code": .string("search_invalid")]); return }
        if let prior = itinerary { itinerary = results.first { $0.id == prior.id } }
        if itinerary == nil { selection = BookingSelection() }
        reconcile()
        analytics.emit(results.isEmpty ? "no_results" : "results_shown", "search.results", ["resultCount": .int(results.count), "origin": .string(request.origin), "destination": .string(request.destination)])
        navigate(.itinerary)
    }
    func choose(_ offer: Itinerary) {
        if itinerary?.id != offer.id { selection = BookingSelection(); undoSelections = [:]; appliedRecommendations = [:] }
        itinerary = offer; reconcile()
        analytics.emit("offer_selected", "itinerary.select", ["journeyId": .string(offer.id), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
        refreshRecommendations(); navigate(.configuration)
    }
    func reconcile() {
        if let itinerary { selection = Validation.reconcile(selection, passengers: passengers, itinerary: itinerary) }
        let p = Set(passengers.map(\.id)); let s = Set(itinerary?.segments.map(\.id) ?? [])
        selection.extras.removeAll { !p.contains($0.passengerID) || !s.contains($0.segmentID) }
        selection.seats.removeAll { !p.contains($0.passengerID) || !s.contains($0.segmentID) }
        selection.meals.removeAll { !p.contains($0.passengerID) || !s.contains($0.segmentID) }
        if !passengers.contains(where: \.isChild), selection.bundle == .family { selection.bundle = .basic }
        changed()
    }
    func changed() {
        revision += 1; paymentAttempt = UUID().uuidString; aiCards = []
        if let aiTripPlan, aiTripPlan.revision != revision { aiPlanStatus = "Your booking changed. Generate an updated plan before applying." }
        for (id, rec) in appliedRecommendations where !retained(rec) {
            analytics.emit("recommendation_reversed", "recommendation.manual_edit", recProperties(rec))
            appliedRecommendations.removeValue(forKey: id); undoSelections.removeValue(forKey: id)
        }
        persist()
    }
    func preference(_ id: String, change: () -> Void) {
        analytics.interact(); change(); changed(); refreshRecommendations()
        analytics.emit("preference_changed", "preference.\(id)", ["choice": .string(id)])
    }
    func refreshRecommendations() {
        guard let itinerary else { recommendations = []; return }
        recommendations = Pricing.recommend(itinerary: itinerary, passengers: passengers, selection: selection, needs: needs)
        recommendations.removeAll { appliedRecommendations[$0.id] != nil }
        recommendations.insert(contentsOf: appliedRecommendations.values.sorted { $0.id < $1.id }, at: 0)
        for rec in recommendations where !seen.contains("generated:" + rec.id) {
            seen.insert("generated:" + rec.id)
            analytics.emit("recommendation_generated", "recommendation.card", recProperties(rec))
        }
    }
    func recProperties(_ rec: Recommendation) -> [String: EventValue] {
        let type = rec.id.hasPrefix("keep-allowance") ? "keep_allowance" : rec.type == "bundles" ? "bundle" : rec.type == "connections" ? "connection" : rec.type
        return ["recommendationId": .string(rec.id), "recommendationType": .string(type), "extrasMinor": .int(quote?.extrasCents ?? 0)]
    }
    func visible(_ rec: Recommendation) {
        guard !seen.contains(rec.id) else { return }; seen.insert(rec.id)
        analytics.emit("recommendation_visible", "recommendation.card", recProperties(rec))
    }
    func expand(_ rec: Recommendation) { expanded.insert(rec.id); analytics.emit("recommendation_expanded", "recommendation.details", recProperties(rec)) }
    func apply(_ rec: Recommendation) {
        analytics.interact(); undoSelections[rec.id] = selection; appliedRecommendations[rec.id] = rec
        analytics.emit("recommendation_accepted", "recommendation.apply", recProperties(rec))
        selection = rec.selection; changed()
        analytics.emit("recommendation_applied", "recommendation.apply", recProperties(rec)); notice = "Updated. You can undo this choice."
    }
    func undo(_ rec: Recommendation) {
        guard let old = undoSelections.removeValue(forKey: rec.id) else { return }
        appliedRecommendations.removeValue(forKey: rec.id)
        if selection.bundle == rec.selection.bundle { selection.bundle = old.bundle }
        selection.extras = undoScoped(current: selection.extras, before: old.extras, applied: rec.selection.extras) { item in item.passengerID + ":" + item.segmentID + ":" + (Catalog.baggageProducts.first { $0.id == item.productID }?.kind ?? item.productID) }
        selection.seats = undoScoped(current: selection.seats, before: old.seats, applied: rec.selection.seats) { $0.passengerID + ":" + $0.segmentID }
        selection.meals = undoScoped(current: selection.meals, before: old.meals, applied: rec.selection.meals) { $0.passengerID + ":" + $0.segmentID }
        changed(); analytics.emit("recommendation_reversed", "recommendation.undo", recProperties(rec))
    }
    func dismiss(_ rec: Recommendation) { dismissed.insert(rec.id); analytics.emit("recommendation_dismissed", "recommendation.dismiss", recProperties(rec)) }
    func setBundle(_ bundle: FareBundle) {
        selection.bundle = bundle; changed(); refreshRecommendations(); analytics.emit("offer_compared", "fare.bundle", ["productId": .string(bundle.rawValue), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
    }
    func setBag(_ product: String?, passenger: String, segment: String) {
        let kind = Catalog.baggageProducts.first { $0.id == product }?.kind
        let ids = Set(Catalog.baggageProducts.filter { $0.kind == kind }.map(\.id))
        selection.extras.removeAll { $0.passengerID == passenger && $0.segmentID == segment && (product == nil || ids.contains($0.productID)) }
        if let product { selection.extras.append(ExtraSelection(passengerID: passenger, segmentID: segment, productID: product)) }
        changed(); refreshRecommendations(); analytics.interact()
        analytics.emit("baggage_changed", "baggage.selector", ["productId": .string(product ?? "included"), "segmentId": .string(segment), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
    }
    /// Deselect one displayed product without clearing another bag kind or traveller/flight scope.
    func removeBag(_ product: String, passenger: String, segment: String) {
        selection.extras.removeAll { $0.passengerID == passenger && $0.segmentID == segment && $0.productID == product }
        changed(); refreshRecommendations(); analytics.interact()
        analytics.emit("baggage_changed", "baggage.selector", ["productId": .string(product), "choice": .string("removed"), "segmentId": .string(segment), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
    }
    func setSeat(_ seat: String?, passenger: String, segment: String) {
        selection.seats.removeAll { $0.passengerID == passenger && $0.segmentID == segment }
        if let seat { selection.seats.append(SeatSelection(passengerID: passenger, segmentID: segment, seatID: seat)) }
        changed(); refreshRecommendations(); analytics.interact()
        analytics.emit("seat_changed", "seats.map", ["segmentId": .string(segment), "choice": .string(seat ?? "none"), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
    }
    func setMeal(_ meal: String?, passenger: String, segment: String) {
        selection.meals.removeAll { $0.passengerID == passenger && $0.segmentID == segment }
        if let meal { selection.meals.append(MealSelection(passengerID: passenger, segmentID: segment, productID: meal)) }
        changed(); refreshRecommendations(); analytics.interact()
        analytics.emit("meal_changed", "meals.card", ["segmentId": .string(segment), "productId": .string(meal ?? "none"), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
    }
    func completeDemo() async {
        guard !paymentBusy, completedTrip == nil, let itinerary, let quote else { return }
        guard quote.isValid else { error = quote.issues.map(\.message).joined(separator: "\n"); return }
        let blockers = Validation.review(request: request, itinerary: itinerary, selection: selection).filter { $0.severity == .error }
        guard blockers.isEmpty else { error = blockers.map(\.message).joined(separator: "\n"); return }
        paymentBusy = true; defer { paymentBusy = false }
        analytics.emit("checkout_started", "checkout.demo", ["totalMinor": .int(quote.totalCents)])
        let trip = SavedTrip(id: "DEMO-" + String(paymentAttempt.prefix(8)).uppercased(), created: Date(), request: request, itinerary: itinerary, selection: selection, totalCents: quote.totalCents)
        if !trips.contains(where: { $0.id == trip.id }) { trips.insert(trip, at: 0) }
        completedTrip = trip
        for rec in appliedRecommendations.values {
            if retained(rec) { analytics.emit("recommendation_retained", "checkout.confirmation", recProperties(rec)) }
        }
        if let aiPlanUndo, retainedAIPlan(aiPlanUndo) {
            analytics.emit("recommendation_retained", "checkout.confirmation", ["recommendationId": .string(aiPlanUndo.id), "recommendationType": .string("bundle"), "extrasMinor": .int(quote.extrasCents)])
        }
        analytics.checkpoint()
        analytics.emit("demo_booking_completed", "checkout.demo", ["totalMinor": .int(quote.totalCents), "extrasMinor": .int(quote.extrasCents), "completed": .bool(true)])
        navigate(.confirmation); persist(); await analytics.flush()
    }
    func reset() {
        analytics.checkpoint(); request = Catalog.demoSearch(.barcelonaFamily); needs = Catalog.demoNeeds(.barcelonaFamily)
        beginNewBooking()
        navigate(.search)
    }
    private func beginNewBooking() {
        itinerary = nil; selection = BookingSelection(); completedTrip = nil; error = nil; notice = nil
        recommendations = []; undoSelections = [:]; appliedRecommendations = [:]; dismissed = []; seen = []; expanded = []; aiCards = []
        paymentAttempt = UUID().uuidString; revision += 1; step = .search
        aiTripPlan = nil; aiPlanUndo = nil; aiPlanRequestID = UUID(); aiPlanBusy = false
        analytics.startFlow()
        persist()
    }
    func checkAIConnection(client: (any AIPlanningClient)? = nil) async {
        do {
            let connection = try await (client ?? BackendAPI(baseURL: analytics.baseURL, token: analytics.uploadToken)).aiConnection()
            guard (connection.model?.count ?? 0) <= 120, connection.features.count <= 10 else { throw BackendError.invalidResponse }
            aiConnection = connection
            if aiTripPlan == nil {
                aiPlanStatus = connection.configured ? "AI is configured. Review a plan before making any changes." : "AI is not configured. The local text helper is available for a preview."
            }
        } catch {
            aiConnection = AIConnection(configured: false, model: nil, features: [])
            if aiTripPlan == nil { aiPlanStatus = "AI connection unavailable. The local text helper can still prepare a preview." }
        }
    }
    func makeAITripPlan(note: String, client: (any AIPlanningClient)? = nil) async {
        guard !aiPlanBusy else { return }
        guard let itinerary, completedTrip == nil else { aiPlanStatus = "Choose an itinerary before designing your trip."; return }
        let text = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        let sentRevision = revision, requestID = UUID()
        aiPlanRequestID = requestID; aiPlanBusy = true; aiTripPlan = nil
        defer { if aiPlanRequestID == requestID { aiPlanBusy = false } }
        aiPlanStatus = "Preparing a plan to review. Nothing is being purchased."
        var preferences: [String] = []
        if needs.noAlcohol { preferences.append("no_alcohol") }
        if needs.travellingLight { preferences.append("light") }
        if needs.giftsOnReturn { preferences.append("gifts") }
        if needs.stayTogether { preferences.append("together") }
        if needs.packingItems.contains("vegetarian") { preferences.append("vegetarian") }
        if needs.packingItems.contains("sports") { preferences.append("sports") }
        if needs.childMeals { preferences.append("child_meal") }
        let request = AIPlanRequest(revision: sentRevision, note: text, journeyId: itinerary.id, passengerTypes: passengers.map { $0.isChild ? "child" : "adult" }, segmentIds: itinerary.segments.map(\.id), preferences: preferences)
        do {
            let plan = text.isEmpty ? AIPlanner.localPlan(note: "", revision: sentRevision) : try await (client ?? BackendAPI(baseURL: analytics.baseURL, token: analytics.uploadToken)).tripPlan(request)
            guard aiPlanRequestID == requestID else { return }
            guard revision == sentRevision, plan.revision == sentRevision else { aiPlanStatus = "Your booking changed while the plan was prepared. Generate an updated plan."; return }
            guard AIPlanner.validate(plan) else { throw BackendError.invalidResponse }
            aiTripPlan = plan
            aiPlanStatus = plan.isAI ? "AI plan ready to review. No changes applied." : "Local text helper preview · not AI. No changes applied."
        } catch {
            guard aiPlanRequestID == requestID else { return }
            guard revision == sentRevision else { aiPlanStatus = "Your booking changed. Generate an updated plan."; return }
            aiTripPlan = AIPlanner.localPlan(note: text, revision: sentRevision)
            aiPlanStatus = "AI unavailable or response invalid. Local text helper preview · not AI. No changes applied."
        }
        if let plan = aiTripPlan { analytics.emit("recommendation_generated", "trip_designer.plan", ["recommendationId": .string(plan.id), "recommendationType": .string("bundle"), "choice": .string(plan.source)]) }
    }
    func proposal(for plan: AITripPlan) -> AITripProposal? {
        guard let itinerary, completedTrip == nil else { return nil }
        return AIPlanner.proposal(plan: plan, revision: revision, itinerary: itinerary, passengers: passengers, selection: selection, needs: needs)
    }
    func applyAITripPlan(_ plan: AITripPlan) {
        guard let itinerary, let proposal = proposal(for: plan) else { aiPlanStatus = "This plan is stale or invalid. Review your preferences and generate an updated plan."; return }
        guard proposal.selection != selection || proposal.needs != needs else { aiPlanStatus = "Your choices already match this plan. Nothing changed."; return }
        aiPlanUndo = AIPlanUndo(id: plan.id, itineraryID: itinerary.id, beforeSelection: selection, beforeNeeds: needs, appliedSelection: proposal.selection, appliedNeeds: proposal.needs)
        analytics.emit("recommendation_accepted", "trip_designer.apply", ["recommendationId": .string(plan.id), "recommendationType": .string("bundle")])
        selection = proposal.selection; needs = proposal.needs; aiTripPlan = nil
        changed(); refreshRecommendations()
        analytics.emit("recommendation_applied", "trip_designer.apply", ["recommendationId": .string(plan.id), "recommendationType": .string("bundle"), "totalMinor": .int(total), "extrasMinor": .int(quote?.extrasCents ?? 0)])
        aiPlanStatus = "Plan applied. You can undo it while keeping later manual changes."
    }
    func undoAITripPlan() {
        guard completedTrip == nil else { aiPlanStatus = "This booking is complete. Its confirmed choices are unchanged."; return }
        guard let previous = aiPlanUndo, let itinerary, previous.itineraryID == itinerary.id else { aiPlanUndo = nil; aiPlanStatus = "This itinerary has changed. There is no matching plan to undo."; return }
        aiPlanUndo = nil
        if selection.bundle == previous.appliedSelection.bundle { selection.bundle = previous.beforeSelection.bundle }
        selection.extras = undoScoped(current: selection.extras, before: previous.beforeSelection.extras, applied: previous.appliedSelection.extras) { item in item.passengerID + ":" + item.segmentID + ":" + (Catalog.baggageProducts.first { $0.id == item.productID }?.kind ?? item.productID) }
        selection.seats = undoScoped(current: selection.seats, before: previous.beforeSelection.seats, applied: previous.appliedSelection.seats) { $0.passengerID + ":" + $0.segmentID }
        selection.meals = undoScoped(current: selection.meals, before: previous.beforeSelection.meals, applied: previous.appliedSelection.meals) { $0.passengerID + ":" + $0.segmentID }
        selection = Validation.reconcile(selection, passengers: passengers, itinerary: itinerary)
        for field in [\TripNeeds.travellingLight, \.giftsOnReturn, \.stayTogether, \.childMeals, \.noAlcohol] {
            if needs[keyPath: field] == previous.appliedNeeds[keyPath: field] { needs[keyPath: field] = previous.beforeNeeds[keyPath: field] }
        }
        let before = Set(previous.beforeNeeds.packingItems), applied = Set(previous.appliedNeeds.packingItems)
        for item in before.symmetricDifference(applied) where needs.packingItems.contains(item) == applied.contains(item) {
            needs.packingItems.removeAll { $0 == item }
            if before.contains(item) { needs.packingItems.append(item) }
        }
        aiTripPlan = nil; changed(); refreshRecommendations()
        analytics.emit("recommendation_reversed", "trip_designer.undo", ["recommendationId": .string(previous.id), "recommendationType": .string("bundle")])
        aiPlanStatus = "Plan undone. Later manual choices have been preserved."
    }
    func dismissAITripPlan() {
        if let plan = aiTripPlan { analytics.emit("recommendation_dismissed", "trip_designer.dismiss", ["recommendationId": .string(plan.id), "recommendationType": .string("bundle")]) }
        aiTripPlan = nil; aiPlanRequestID = UUID(); aiPlanBusy = false
        aiPlanStatus = "Plan dismissed. Your choices are unchanged."
    }
    func requestGuidance() async {
        guard aiEnabled, !needs.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let itinerary else { refreshRecommendations(); return }
        aiBusy = true; defer { aiBusy = false }; let sentRevision = revision
        do {
            let api = BackendAPI(baseURL: analytics.baseURL, token: analytics.uploadToken)
            let response = try await api.post("/api/ai/guidance", body: ["revision": sentRevision, "note": String(needs.note.prefix(500)), "journeyId": itinerary.id, "passengerTypes": passengers.map { $0.isChild ? "child" : "adult" }, "segmentIds": itinerary.segments.map(\.id), "preferences": needs.noAlcohol ? ["no_alcohol"] : []], as: GuidanceResponse.self)
            guard response.revision == revision else { return }
            let allowed = Set(["peg-cabin","peg-checked20","peg-checked25","peg-meal-child","peg-meal-veggie","peg-meal-classic","basic","family","flex","standardSeat","extraLegroom"])
            let types = Set(["baggage","meals","seating","bundle","connection","keep_allowance"])
            aiCards = response.cards.filter { types.contains($0.type) && $0.requiresConfirmation && Set($0.productIds).isSubset(of: allowed) && Set($0.passengerIds).isSubset(of: Set(passengers.map(\.id))) && Set($0.segmentIds).isSubset(of: Set(itinerary.segments.map(\.id))) }
            aiStatus = response.source == "openai" ? "AI guidance · choices need your approval" : "Local fallback · AI unavailable"
        } catch { aiStatus = "AI unavailable · local recommendations are ready"; refreshRecommendations() }
    }
    private func retained(_ rec: Recommendation) -> Bool {
        guard let before = undoSelections[rec.id] else { return false }
        if before == rec.selection { return selection == rec.selection }
        if before.bundle != rec.selection.bundle && selection.bundle != rec.selection.bundle { return false }
        let bags = changesRetained(current: selection.extras, before: before.extras, applied: rec.selection.extras) { item in
            let kind = Catalog.baggageProducts.first { $0.id == item.productID }?.kind ?? item.productID
            return item.passengerID + ":" + item.segmentID + ":" + kind
        }
        let seats = changesRetained(current: selection.seats, before: before.seats, applied: rec.selection.seats) { $0.passengerID + ":" + $0.segmentID }
        let meals = changesRetained(current: selection.meals, before: before.meals, applied: rec.selection.meals) { $0.passengerID + ":" + $0.segmentID }
        return bags && seats && meals
    }
    private func retainedAIPlan(_ plan: AIPlanUndo) -> Bool {
        guard itinerary?.id == plan.itineraryID else { return false }
        if plan.beforeSelection.bundle != plan.appliedSelection.bundle && selection.bundle == plan.appliedSelection.bundle { return true }
        if anyChangesRetained(current: selection.extras, before: plan.beforeSelection.extras, applied: plan.appliedSelection.extras, key: { item in item.passengerID + ":" + item.segmentID + ":" + (Catalog.baggageProducts.first { $0.id == item.productID }?.kind ?? item.productID) }) { return true }
        if anyChangesRetained(current: selection.seats, before: plan.beforeSelection.seats, applied: plan.appliedSelection.seats, key: { $0.passengerID + ":" + $0.segmentID }) { return true }
        if anyChangesRetained(current: selection.meals, before: plan.beforeSelection.meals, applied: plan.appliedSelection.meals, key: { $0.passengerID + ":" + $0.segmentID }) { return true }
        for field in [\TripNeeds.travellingLight, \.giftsOnReturn, \.stayTogether, \.childMeals, \.noAlcohol] {
            if plan.beforeNeeds[keyPath: field] != plan.appliedNeeds[keyPath: field] && needs[keyPath: field] == plan.appliedNeeds[keyPath: field] { return true }
        }
        let before = Set(plan.beforeNeeds.packingItems), applied = Set(plan.appliedNeeds.packingItems)
        return before.symmetricDifference(applied).contains { needs.packingItems.contains($0) == applied.contains($0) }
    }
}

func euros(_ cents: Int) -> String { (Decimal(cents) / 100).formatted(.currency(code: "EUR")) }

/// Reverse only scopes still equal to the applied proposal; preserve later manual edits.
private func undoScoped<T: Equatable>(current: [T], before: [T], applied: [T], key: (T) -> String) -> [T] {
    var result = current
    for scope in Set((before + applied).map(key)) {
        let prior = before.filter { key($0) == scope }, proposal = applied.filter { key($0) == scope }
        if prior != proposal && current.filter({ key($0) == scope }) == proposal {
            result.removeAll { key($0) == scope }; result += prior
        }
    }
    return result
}
private func changesRetained<T: Equatable>(current: [T], before: [T], applied: [T], key: (T) -> String) -> Bool {
    Set((before + applied).map(key)).allSatisfy { scope in
        let old = before.filter { key($0) == scope }, proposal = applied.filter { key($0) == scope }
        return old == proposal || current.filter { key($0) == scope } == proposal
    }
}
private func anyChangesRetained<T: Equatable>(current: [T], before: [T], applied: [T], key: (T) -> String) -> Bool {
    Set((before + applied).map(key)).contains { scope in
        let old = before.filter { key($0) == scope }, proposal = applied.filter { key($0) == scope }
        return old != proposal && current.filter { key($0) == scope } == proposal
    }
}
