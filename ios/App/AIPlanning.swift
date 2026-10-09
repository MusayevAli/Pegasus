import Foundation
import TripFitCore

struct AIConnection: Codable, Equatable, Sendable {
    var configured: Bool
    var model: String?
    var features: [String]
}

struct AIPlanNeeds: Codable, Equatable, Sendable {
    var travellingLight: Bool? = nil
    var giftsOnReturn: Bool? = nil
    var stayTogether: Bool? = nil
    var noAlcohol: Bool? = nil
    var vegetarian: Bool? = nil
    var checkedBagEachWay: Bool? = nil
    var mealsEachFlight: Bool? = nil
    var packingItems: [String] = []
    var hasExplicitNeeds: Bool {
        [travellingLight, giftsOnReturn, stayTogether, noAlcohol, vegetarian, checkedBagEachWay, mealsEachFlight].contains { $0 != nil } || !packingItems.isEmpty
    }
}

struct AIPlanClarification: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var question: String
    var choices: [String]
}

struct AITripPlan: Codable, Identifiable, Equatable, Sendable {
    var revision: Int
    var source: String
    var model: String?
    var summary: String
    var needs: AIPlanNeeds
    var clarifications: [AIPlanClarification]
    var notice: String
    var id: String { "trip-plan-\(revision)-\(source)" }
    var isAI: Bool { source == "openai" }
}

struct AITripProposal: Equatable, Sendable {
    var selection: BookingSelection
    var needs: TripNeeds
    var totalCents: Int
    var deltaCents: Int
    var changes: [String]
    var warnings: [String]
}

struct AIPlanRequest: Codable, Sendable {
    var revision: Int
    var note: String
    var journeyId: String
    var passengerTypes: [String]
    var segmentIds: [String]
    var preferences: [String]
}

protocol AIPlanningClient: Sendable {
    func tripPlan(_ request: AIPlanRequest) async throws -> AITripPlan
    func aiConnection() async throws -> AIConnection
}

struct AIPlanUndo: Sendable {
    var id: String
    var itineraryID: String
    var beforeSelection: BookingSelection
    var beforeNeeds: TripNeeds
    var appliedSelection: BookingSelection
    var appliedNeeds: TripNeeds
}

enum AIPlanner {
    static let packingCategories = Set(["clothes", "laptop", "gifts", "sports", "liquids"])
    static let clarificationIDs = Set(["packing", "meals", "seating"])
    static let clarificationChoices = Set(["travel_light", "checked_bag", "vegetarian", "meals", "no_meal", "together", "skip"])

    static func validate(_ plan: AITripPlan) -> Bool {
        plan.revision >= 0 && ["openai", "local"].contains(plan.source) &&
        !plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && plan.summary.count <= 1200 && plan.notice.count <= 2000 &&
        (plan.model?.count ?? 0) <= 120 && plan.needs.packingItems.count <= packingCategories.count &&
        Set(plan.needs.packingItems).count == plan.needs.packingItems.count && Set(plan.needs.packingItems).isSubset(of: packingCategories) &&
        plan.clarifications.count <= 3 && Set(plan.clarifications.map(\.id)).count == plan.clarifications.count &&
        plan.clarifications.allSatisfy { clarificationIDs.contains($0.id) && !$0.question.isEmpty && $0.question.count <= 300 && !$0.choices.isEmpty && $0.choices.count <= 7 && Set($0.choices).isSubset(of: clarificationChoices) }
    }

    static func merge(_ explicit: AIPlanNeeds, into current: TripNeeds) -> TripNeeds {
        var result = current
        if let value = explicit.travellingLight { result.travellingLight = value }
        if let value = explicit.giftsOnReturn { result.giftsOnReturn = value }
        if let value = explicit.stayTogether { result.stayTogether = value }
        if let value = explicit.noAlcohol { result.noAlcohol = value }
        func setFlag(_ flag: String, _ value: Bool?) {
            guard let value else { return }
            result.packingItems.removeAll { $0 == flag }
            if value { result.packingItems.append(flag) }
        }
        setFlag("vegetarian", explicit.vegetarian)
        setFlag("checked-bag-each-way", explicit.checkedBagEachWay)
        setFlag("meals-each-flight", explicit.mealsEachFlight)
        if explicit.mealsEachFlight == false { result.childMeals = false }
        for item in explicit.packingItems where !result.packingItems.contains(item) { result.packingItems.append(item) }
        if explicit.travellingLight == true && explicit.checkedBagEachWay != true && explicit.giftsOnReturn != true {
            result.giftsOnReturn = false
            result.packingItems.removeAll { ["checked-bag", "checked-bag-each-way"].contains($0) }
        }
        return result
    }

    static func proposal(plan: AITripPlan, revision: Int, itinerary: Itinerary, passengers: [Passenger], selection: BookingSelection, needs: TripNeeds) -> AITripProposal? {
        guard plan.revision == revision, validate(plan) else { return nil }
        let beforeQuote = Pricing.quote(itinerary: itinerary, passengers: passengers, selection: selection)
        guard beforeQuote.isValid else { return nil }
        guard plan.needs.hasExplicitNeeds else {
            return AITripProposal(selection: selection, needs: needs, totalCents: beforeQuote.totalCents, deltaCents: 0, changes: [], warnings: ["No explicit booking preference was identified. Your choices remain unchanged."])
        }
        let explicit = plan.needs
        if explicit.travellingLight == true && (explicit.checkedBagEachWay == true || explicit.giftsOnReturn == true) { return nil }
        let merged = merge(explicit, into: needs)
        let segmentIDs = Set(itinerary.segments.filter(\.isPegasus).map(\.id))
        let passengerIDs = Set(passengers.map(\.id))
        var proposed = selection
        if explicit.checkedBagEachWay == false {
            proposed.extras.removeAll { passengerIDs.contains($0.passengerID) && segmentIDs.contains($0.segmentID) && $0.productID.hasPrefix("peg-checked") }
        }
        if explicit.travellingLight == true {
            proposed.extras.removeAll { passengerIDs.contains($0.passengerID) && segmentIDs.contains($0.segmentID) && Catalog.baggageProducts.map(\.id).contains($0.productID) }
        }
        if explicit.mealsEachFlight == false { proposed.meals.removeAll { passengerIDs.contains($0.passengerID) && segmentIDs.contains($0.segmentID) } }

        // Only explicitly discussed categories generate purchases. Existing requirements remain
        // recorded, but a note about alcohol cannot unexpectedly add the default family bags.
        var demand = TripNeeds(travellingLight: explicit.travellingLight == true, giftsOnReturn: explicit.giftsOnReturn == true, stayTogether: explicit.stayTogether == true, noAlcohol: merged.noAlcohol)
        if explicit.checkedBagEachWay == true || (explicit.giftsOnReturn == true && needs.packingItems.contains("checked-bag-each-way")) { demand.packingItems.append("checked-bag-each-way") }
        if explicit.mealsEachFlight == true { demand.packingItems.append("meals-each-flight") }
        let purchaseCategoryDiscussed = explicit.travellingLight != nil || explicit.giftsOnReturn != nil || explicit.stayTogether != nil || explicit.checkedBagEachWay != nil || explicit.mealsEachFlight != nil
        if purchaseCategoryDiscussed {
            let suggestions = Pricing.recommend(itinerary: itinerary, passengers: passengers, selection: proposed, needs: demand)
                .filter { $0.id.hasPrefix("fit-") || $0.id.hasPrefix("keep-allowance-") }
            if let cheapest = suggestions.min(by: { $0.totalCents < $1.totalCents }) { proposed = cheapest.selection }
        }
        if explicit.vegetarian == true {
            let adultIDs = Set(passengers.filter { !$0.isChild }.map(\.id))
            proposed.meals = proposed.meals.map { item in
                guard adultIDs.contains(item.passengerID), segmentIDs.contains(item.segmentID), let meal = Catalog.mealProducts.first(where: { $0.id == item.productID }), !meal.tags.contains("Vegetarian") else { return item }
                return MealSelection(passengerID: item.passengerID, segmentID: item.segmentID, productID: "peg-meal-veggie")
            }
        }
        if explicit.mealsEachFlight == false { proposed.meals.removeAll { passengerIDs.contains($0.passengerID) && segmentIDs.contains($0.segmentID) } }
        let purchasesChanged = proposed.extras != selection.extras || proposed.seats != selection.seats || proposed.meals != selection.meals
        if purchasesChanged || explicit.travellingLight == true {
            if selection.bundle == .flex && explicit.travellingLight != true {
                proposed.bundle = .flex // Flexibility is an unrelated existing choice.
            } else {
                let options = FareBundle.allCases.compactMap { bundle -> (BookingSelection, Quote)? in
                    var candidate = proposed; candidate.bundle = bundle
                    let quote = Pricing.quote(itinerary: itinerary, passengers: passengers, selection: candidate)
                    return quote.isValid ? (candidate, quote) : nil
                }
                if let cheapest = options.min(by: { $0.1.totalCents < $1.1.totalCents }) { proposed = cheapest.0 }
            }
        } else { proposed.bundle = selection.bundle }
        let quote = Pricing.quote(itinerary: itinerary, passengers: passengers, selection: proposed)
        guard quote.isValid else { return nil }
        var warnings: [String] = []
        if explicit.travellingLight == true { warnings.append("Light travel assumes your items fit the 3 kg, 40 × 30 × 15 cm underseat limit. Confirm actual weight and dimensions before applying.") }
        if explicit.vegetarian == true { warnings.append("Vegetarian menu labels are not an allergy-safety guarantee. Confirm allergens with the airline.") }
        if explicit.packingItems.contains("sports") { warnings.append("Sports equipment is not sold in this demo catalogue. Standard checked baggage does not confirm sports-equipment acceptance.") }
        if itinerary.segments.contains(where: { !$0.isPegasus }) && purchasesChanged { warnings.append("Changes apply only to listed Pegasus flights. Incoming-airline baggage and fare terms remain separate.") }
        if explicit.stayTogether == true {
            for segment in itinerary.segments where segment.isPegasus { warnings += Validation.familyAdjacency(proposed.seats, passengers: passengers, segment: segment).map(\.message) }
        }
        var changes = describeChanges(before: selection, after: proposed, itinerary: itinerary, passengers: passengers)
        if needs.travellingLight != merged.travellingLight { changes.append("Preference: travelling light \(merged.travellingLight ? "on" : "off").") }
        if needs.giftsOnReturn != merged.giftsOnReturn { changes.append("Preference: room for return gifts \(merged.giftsOnReturn ? "on" : "off").") }
        if needs.stayTogether != merged.stayTogether { changes.append("Preference: sit together \(merged.stayTogether ? "on" : "off").") }
        if needs.noAlcohol != merged.noAlcohol { changes.append("Preference: alcohol suggestions \(merged.noAlcohol ? "hidden" : "allowed for adults").") }
        if explicit.vegetarian != nil { changes.append("Preference: vegetarian \(explicit.vegetarian == true ? "on" : "off").") }
        if !explicit.packingItems.isEmpty { changes.append("Confirmed packing categories: \(explicit.packingItems.joined(separator: ", ")).") }
        return AITripProposal(selection: proposed, needs: merged, totalCents: quote.totalCents, deltaCents: quote.totalCents - beforeQuote.totalCents, changes: changes, warnings: Array(Set(warnings)).sorted())
    }

    private static func describeChanges(before: BookingSelection, after: BookingSelection, itinerary: Itinerary, passengers: [Passenger]) -> [String] {
        var changes: [String] = []
        if before.bundle != after.bundle { changes.append("Fare: \(before.bundle.title) → \(after.bundle.title), for all \(passengers.count) travellers on all \(itinerary.segments.filter(\.isPegasus).count) Pegasus flights.") }
        for passenger in passengers {
            for segment in itinerary.segments {
                let scope = "\(passenger.displayName) · \(segment.direction.title) \(segment.origin)–\(segment.destination)"
                for kind in ["cabin", "checked"] {
                    func bag(_ selection: BookingSelection) -> String? { selection.extras.first { item in item.passengerID == passenger.id && item.segmentID == segment.id && Catalog.baggageProducts.contains { $0.id == item.productID && $0.kind == kind } }?.productID }
                    let old = bag(before), new = bag(after)
                    if old != new { let title = new.flatMap { id in Catalog.baggageProducts.first { $0.id == id }?.name } ?? "included \(kind) allowance only"; changes.append("\(scope): \(title).") }
                }
                let oldSeat = before.seats.first { $0.passengerID == passenger.id && $0.segmentID == segment.id }?.seatID
                let newSeat = after.seats.first { $0.passengerID == passenger.id && $0.segmentID == segment.id }?.seatID
                if oldSeat != newSeat { changes.append("\(scope): \(newSeat.map { "seat " + $0 } ?? "no selected seat").") }
                let oldMeal = before.meals.first { $0.passengerID == passenger.id && $0.segmentID == segment.id }?.productID
                let newMeal = after.meals.first { $0.passengerID == passenger.id && $0.segmentID == segment.id }?.productID
                if oldMeal != newMeal { let title = newMeal.flatMap { id in Catalog.mealProducts.first { $0.id == id }?.name } ?? "no meal"; changes.append("\(scope): \(title).") }
            }
        }
        return changes
    }

    static func localPlan(note: String, revision: Int) -> AITripPlan {
        let text = note.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var needs = AIPlanNeeds()
        // A deliberately small, transparent keyword helper. It is not presented as AI.
        if text.contains("travel light") || text.contains("travelling light") || text.contains("only a backpack") || text.contains("small bag only") { needs.travellingLight = true }
        if text.contains("no gifts") || text.contains("no souvenirs") || text.contains("not bringing gifts") { needs.giftsOnReturn = false }
        else if text.contains("gifts") || text.contains("souvenirs") { needs.giftsOnReturn = true }
        if text.contains("don't sit together") || text.contains("do not sit together") || text.contains("don't need seats together") || text.contains("no seats together") { needs.stayTogether = false }
        else if text.contains("sit together") || text.contains("stay together") || text.contains("seats together") { needs.stayTogether = true }
        if text.contains("no alcohol") || text.contains("avoid alcohol") { needs.noAlcohol = true }
        if text.contains("not vegetarian") || text.contains("no vegetarian") { needs.vegetarian = false }
        else if text.contains("vegetarian") { needs.vegetarian = true }
        if text.contains("no checked bags") || text.contains("no checked bag") || text.contains("don't need checked") || text.contains("do not need checked") { needs.checkedBagEachWay = false }
        else if text.contains("checked bag each way") || text.contains("checked bags both ways") || text.contains("checked bag for everyone") || (text.contains("checked bags") && (text.contains("each flight") || text.contains("every flight"))) { needs.checkedBagEachWay = true }
        if text.contains("no meals") || text.contains("no meal") { needs.mealsEachFlight = false }
        else if text.contains("meals on every flight") || text.contains("meals each flight") || text.contains("meals for everyone") { needs.mealsEachFlight = true }
        for category in ["clothes", "laptop", "sports", "liquids"] where text.contains(category) { needs.packingItems.append(category) }
        return AITripPlan(revision: revision, source: "local", model: nil, summary: needs.hasExplicitNeeds ? "The local keyword helper found the preferences below. Review and correct them before applying." : "The local keyword helper found no explicit booking preferences. Keep your current choices or select preferences manually.", needs: needs, clarifications: [], notice: "Live AI is unavailable. This is a limited local text helper, not an AI analysis. Prices and choices come from the demo catalogue.")
    }
}
