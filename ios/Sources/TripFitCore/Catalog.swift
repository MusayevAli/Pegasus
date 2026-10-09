import Foundation

/// Every schedule, fare, airline pairing and product in this catalogue is illustrative demo data.
public enum Catalog {
    public static let version = "demo-2026-1"
    public static let baggageProducts: [BaggageProduct] = [
        BaggageProduct(id: "peg-cabin", name: "Cabin bag", priceCents: 1800, description: "1 piece · 8 kg · 55 × 40 × 20 cm", kind: "cabin", allowance: BaggageLimit(totalWeightKG: 8, dimensions: BagDimensions(55, 40, 20))),
        BaggageProduct(id: "peg-checked20", name: "Checked bag · 20 kg", priceCents: 2500, description: "1 piece · 20 kg total · 158 cm combined dimensions", kind: "checked", allowance: BaggageLimit(totalWeightKG: 20, maxLinearCM: 158)),
        BaggageProduct(id: "peg-checked25", name: "Checked bag · 25 kg", priceCents: 3500, description: "1 piece · 25 kg total · 158 cm combined dimensions", kind: "checked", allowance: BaggageLimit(totalWeightKG: 25, maxLinearCM: 158))
    ]
    public static let mealProducts: [MealProduct] = [
        MealProduct(id: "peg-meal-child", name: "Little traveller's pasta", priceCents: 900, description: "Tomato pasta, fruit and water. Demo menu; allergens require provider confirmation.", tags: ["Child meal", "Vegetarian"], childOnly: true),
        MealProduct(id: "peg-meal-veggie", name: "Garden bowl", priceCents: 1200, description: "Roasted vegetables, grains and greens. Demo menu; allergens require provider confirmation.", tags: ["Vegetarian"]),
        MealProduct(id: "peg-meal-classic", name: "Chicken & rice", priceCents: 1400, description: "Warm chicken with herbed rice. Demo menu; allergens require provider confirmation.", tags: [])
    ]
    public static func demoSearch(_ preset: DemoJourney, now: Date = Date()) -> SearchRequest {
        let date = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 14, to: now)!)
        switch preset {
        case .barcelonaFamily: return SearchRequest(origin: "SAW", destination: "BCN", outboundDate: date, returnDate: Calendar.current.date(byAdding: .day, value: 6, to: date), adults: 2, children: 1)
        case .usConnection: return SearchRequest(origin: "JFK", destination: "SAW", outboundDate: date, adults: 1, children: 0)
        case .soloLight: return SearchRequest(origin: "SAW", destination: "AYT", outboundDate: date, adults: 1, children: 0)
        }
    }
    public static func demoNeeds(_ preset: DemoJourney) -> TripNeeds {
        switch preset {
        case .barcelonaFamily: return TripNeeds(giftsOnReturn: true, stayTogether: true, childMeals: true, packingItems: ["checked-bag-each-way", "meals-each-flight"])
        case .usConnection: return TripNeeds(packingItems: ["checked-bag"])
        case .soloLight: return TripNeeds(travellingLight: true)
        }
    }
    public static func search(_ request: SearchRequest, now: Date = Date()) -> SearchResult {
        let issues = Validation.search(request, now: now)
        guard !issues.contains(where: { $0.severity == .error }) else { return SearchResult(issues: issues) }
        let route = "\(request.origin.uppercased())-\(request.destination.uppercased())"
        switch route {
        case "SAW-BCN":
            let departure = scheduled(request.outboundDate, hour: 9, minute: 25, zone: "Europe/Istanbul")
            var segments = [Segment(id: "family-out", flightNumber: "PC-DEMO-01", origin: "SAW", destination: "BCN", departure: departure, arrival: departure.addingTimeInterval(220 * 60), originTimeZone: "Europe/Istanbul", destinationTimeZone: "Europe/Madrid")]
            if let date = request.returnDate {
                let back = scheduled(date, hour: 13, minute: 15, zone: "Europe/Madrid")
                segments.append(Segment(id: "family-in", flightNumber: "PC-DEMO-02", origin: "BCN", destination: "SAW", departure: back, arrival: back.addingTimeInterval(220 * 60), originTimeZone: "Europe/Madrid", destinationTimeZone: "Europe/Istanbul", direction: .inbound))
            }
            let count = segments.count
            return SearchResult(itineraries: [Itinerary(id: "family", title: "Barcelona, together", segments: segments, basePricePerAdultCents: 9000 * count, basePricePerChildCents: 6750 * count)])
        case "JFK-SAW" where request.returnDate == nil:
            let departure = scheduled(request.outboundDate, hour: 20, minute: 0, zone: "America/New_York")
            let arrival = departure.addingTimeInterval(7 * 3600)
            let onwards = arrival.addingTimeInterval(4 * 3600)
            let segments = [
                Segment(id: "us-external", carrier: "External airline (demo)", flightNumber: "EX-DEMO-01", origin: "JFK", destination: "LGW", departure: departure, arrival: arrival, originTimeZone: "America/New_York", destinationTimeZone: "Europe/London", includedBaggage: BaggageAllowance(checked: BaggageLimit(totalWeightKG: 23, maxLinearCM: 158))),
                Segment(id: "us-pegasus", flightNumber: "PC-DEMO-03", origin: "LGW", destination: "SAW", departure: onwards, arrival: onwards.addingTimeInterval(230 * 60), originTimeZone: "Europe/London", destinationTimeZone: "Europe/Istanbul", includedBaggage: BaggageAllowance(checked: BaggageLimit(totalWeightKG: 20, maxLinearCM: 158)))
            ]
            let itinerary = Itinerary(id: "us-connection", title: "New York → London → Istanbul", segments: segments, basePricePerAdultCents: 48000, basePricePerChildCents: 36000, fareConditions: "Separate, non-refundable demo tickets. No disruption protection. Neither airline is responsible for missed separate-ticket connections.", transferKind: .selfTransfer)
            var short = segments[1]; short.departure = arrival.addingTimeInterval(85 * 60); short.arrival = short.departure.addingTimeInterval(230 * 60)
            let rejection = Connections.validate(incoming: segments[0], outgoing: short).first?.message ?? "Too little transfer time."
            return SearchResult(itineraries: [itinerary], rejected: [RejectedItinerary(id: "us-short", title: "85-minute self-transfer · unavailable", reason: rejection, connectionMinutes: 85)])
        case "SAW-AYT" where request.returnDate == nil:
            let departure = scheduled(request.outboundDate, hour: 9, minute: 15, zone: "Europe/Istanbul")
            return SearchResult(itineraries: [Itinerary(id: "solo", title: "A little Antalya escape", segments: [Segment(id: "solo-out", flightNumber: "PC-DEMO-04", origin: "SAW", destination: "AYT", departure: departure, arrival: departure.addingTimeInterval(85 * 60), originTimeZone: "Europe/Istanbul", destinationTimeZone: "Europe/Istanbul")], basePricePerAdultCents: 4500, basePricePerChildCents: 3400)])
        default: return SearchResult(issues: [ValidationIssue("unsupported-search", "No demo inventory for this search. Try SAW–BCN, JFK–SAW one way, or SAW–AYT one way.", severity: .warning, componentID: "search.route")])
        }
    }
    public static func seats(for segment: Segment) -> [Seat] {
        guard segment.isPegasus else { return [] }
        let unavailable = Set(["2B", "3E", "5A", "7C"])
        return (1...8).flatMap { row in ["A", "B", "C", "D", "E", "F"].map { letter in let id = "\(row)\(letter)"; return Seat(id: id, row: row, letter: letter, priceCents: row == 1 ? 3000 : 1500, isAvailable: !unavailable.contains(id), isExitRow: row == 1) } }
    }
    /// Searches a single three-seat block; never treats C/D across the aisle as adjacent.
    public static func familySeats(passengers: [Passenger], segment: Segment, existing: [SeatSelection] = []) -> [SeatSelection]? {
        guard segment.isPegasus, passengers.contains(where: { $0.isChild }), passengers.contains(where: { !$0.isChild }) else { return nil }
        let selected = existing.filter { $0.segmentID == segment.id }
        if passengers.allSatisfy({ p in selected.contains { $0.passengerID == p.id } }), Validation.seats(selected, passengers: passengers, segments: [segment]).isEmpty, Validation.familyAdjacency(selected, passengers: passengers, segment: segment).isEmpty { return selected }
        guard passengers.count <= 3 else { return nil }
        let children = passengers.filter(\.isChild), adults = passengers.filter { !$0.isChild }
        let ordered = children.count == 2 ? [children[0], adults[0], children[1]] : children + adults
        for row in 2...8 {
            for block in [["A", "B", "C"], ["D", "E", "F"]] {
                let seats = block.prefix(passengers.count).map { "\(row)\($0)" }
                if seats.allSatisfy({ id in Catalog.seats(for: segment).contains { $0.id == id && $0.isAvailable } }) {
                    // Parent next to child: child at A/D, first adult at B/E.
                    let proposal = zip(ordered, seats).map { SeatSelection(passengerID: $0.0.id, segmentID: segment.id, seatID: $0.1) }
                    if Validation.familyAdjacency(proposal, passengers: passengers, segment: segment).isEmpty { return proposal }
                }
            }
        }
        return nil
    }
    public static func orderedMeals(passenger: Passenger, needs: TripNeeds) -> [MealProduct] {
        // No alcohol products exist in this demo. Explicit noAlcohol is still carried to the live boundary.
        let options = mealProducts.filter { !$0.childOnly || passenger.isChild }
        return options.sorted { left, right in
            if passenger.isChild && left.childOnly != right.childOnly { return left.childOnly }
            if needs.packingItems.contains("vegetarian") && left.tags.contains("Vegetarian") != right.tags.contains("Vegetarian") { return left.tags.contains("Vegetarian") }
            return left.priceCents < right.priceCents
        }
    }
    private static func scheduled(_ day: Date, hour: Int, minute: Int, zone: String) -> Date {
        let dateParts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        var parts = dateParts; parts.hour = hour; parts.minute = minute; parts.timeZone = calendar.timeZone
        return calendar.date(from: parts)!
    }
}
