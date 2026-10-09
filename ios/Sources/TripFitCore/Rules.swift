import Foundation

public struct TransferRules: Sendable {
    public var minimumConnectionMinutes: Int
    public var baggageCollectionMinutes: Int
    public var entryAndCheckInMinutes: Int
    public var securityMinutes: Int
    public var checkInDeadlineMinutes: Int
    public init(minimumConnectionMinutes: Int = 180, baggageCollectionMinutes: Int = 45, entryAndCheckInMinutes: Int = 60, securityMinutes: Int = 30, checkInDeadlineMinutes: Int = 60) { self.minimumConnectionMinutes = minimumConnectionMinutes; self.baggageCollectionMinutes = baggageCollectionMinutes; self.entryAndCheckInMinutes = entryAndCheckInMinutes; self.securityMinutes = securityMinutes; self.checkInDeadlineMinutes = checkInDeadlineMinutes }
}
public enum Connections {
    public static func validate(incoming: Segment, outgoing: Segment, rules: TransferRules = TransferRules()) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if incoming.destination != outgoing.origin { issues.append(ValidationIssue("airport-mismatch", "\(incoming.destination) and \(outgoing.origin) are different airports. This prototype supports same-airport transfers only.", componentID: "connection.airport")) }
        let gap = Int(outgoing.departure.timeIntervalSince(incoming.arrival) / 60)
        let deadlineBudget = rules.baggageCollectionMinutes + rules.entryAndCheckInMinutes + rules.checkInDeadlineMinutes
        let required = max(rules.minimumConnectionMinutes, deadlineBudget, rules.baggageCollectionMinutes + rules.entryAndCheckInMinutes + rules.securityMinutes)
        if gap < required { issues.append(ValidationIssue("connection-too-short", "\(gap) minutes is below the \(required)-minute demo transfer buffer, including the \(rules.checkInDeadlineMinutes)-minute check-in deadline. Choose the longer connection. Buffers are not guarantees.", componentID: "connection.timing")) }
        if incoming.arrival <= incoming.departure || outgoing.arrival <= outgoing.departure { issues.append(ValidationIssue("invalid-segment-time", "A flight has invalid departure/arrival timestamps.", componentID: "connection.timing")) }
        return issues
    }
    public static func timeline(for itinerary: Itinerary) -> [String] {
        guard itinerary.segments.count > 1, itinerary.transferKind == .selfTransfer else { return [] }
        let first = itinerary.segments[0]; let next = itinerary.segments[1]
        return ["Arrive at \(first.destination) · \(first.localArrival())", "Collect your checked baggage", "Complete entry formalities if required — entry/transit requirements not checked", "Re-check with \(next.carrier) before the 60-minute demo check-in deadline", "Pass security and walk to your departure gate", "Depart \(next.origin) · \(next.localDeparture())", "No through-check or connection protection. Transfer buffers are not guarantees."]
    }
}
public struct BaggageConflict: Identifiable, Equatable, Sendable {
    public var id: String
    public var message: String
    public var productIDs: [String]
    public init(id: String, message: String, productIDs: [String] = []) { self.id = id; self.message = message; self.productIDs = productIDs }
}
public enum Baggage {
    /// Checks piece count, per-piece limit, total limit and geometry separately; no pooling assumptions.
    public static func conflicts(incoming: BaggageLimit, onward: BaggageLimit?) -> [BaggageConflict] {
        guard let onward else { return [BaggageConflict(id: "no-onward-allowance", message: "The onward flight includes no checked baggage.", productIDs: ["peg-checked20", "peg-checked25"])] }
        var result: [BaggageConflict] = []
        if incoming.pieces > onward.pieces { result.append(BaggageConflict(id: "piece-count", message: "Incoming allowance has \(incoming.pieces) pieces; onward allows \(onward.pieces). This catalogue has no extra-piece fix.")) }
        if incoming.totalWeightKG > onward.totalWeightKG { result.append(BaggageConflict(id: "total-weight", message: "Incoming allows \(incoming.totalWeightKG) kg; onward includes \(onward.totalWeightKG) kg. Pack to the smaller allowance or upgrade the Pegasus segment only.", productIDs: incoming.totalWeightKG <= 25 && incoming.pieces <= onward.pieces ? ["peg-checked25"] : [])) }
        if incoming.maxPieceWeightKG > onward.maxPieceWeightKG { result.append(BaggageConflict(id: "piece-weight", message: "One incoming piece may weigh \(incoming.maxPieceWeightKG) kg; the onward limit is \(onward.maxPieceWeightKG) kg per piece.", productIDs: incoming.maxPieceWeightKG <= 25 && incoming.pieces <= onward.pieces ? ["peg-checked25"] : [])) }
        if let dimensions = incoming.dimensions {
            if let onwardDimensions = onward.dimensions, zip(dimensions.sortedEdges, onwardDimensions.sortedEdges).contains(where: { $0.0 > $0.1 }) { result.append(BaggageConflict(id: "dimensions", message: "Incoming piece dimensions exceed at least one onward dimension. No size upgrade is offered.")) }
            if let linear = onward.maxLinearCM, dimensions.linearCM > linear { result.append(BaggageConflict(id: "linear-dimensions", message: "Incoming piece dimensions exceed the onward combined \(linear) cm limit. No size upgrade is offered.")) }
        } else if let incomingLinear = incoming.maxLinearCM, let onwardLinear = onward.maxLinearCM, incomingLinear > onwardLinear { result.append(BaggageConflict(id: "linear-dimensions", message: "Incoming combined dimensions exceed the onward \(onwardLinear) cm limit. No size upgrade is offered.")) }
        else if incoming.maxLinearCM != nil && onward.dimensions != nil { result.append(BaggageConflict(id: "dimensions-unknown", message: "A combined-dimension allowance cannot prove compliance with each onward dimension. Confirm the actual bag dimensions.")) }
        return result
    }
    public static func allowance(passengerID: String, segment: Segment, selection: BookingSelection) -> BaggageAllowance {
        var result = segment.includedBaggage
        guard segment.isPegasus else { return result }
        if selection.bundle == .family && (result.checked?.totalWeightKG ?? 0) < 20 { result.checked = BaggageLimit(totalWeightKG: 20, maxLinearCM: 158) }
        if selection.bundle == .flex && (result.checked?.totalWeightKG ?? 0) < 25 { result.checked = BaggageLimit(totalWeightKG: 25, maxLinearCM: 158) }
        for extra in selection.extras.filter({ $0.passengerID == passengerID && $0.segmentID == segment.id }) {
            guard let product = Catalog.baggageProducts.first(where: { $0.id == extra.productID }) else { continue }
            if product.kind == "cabin" { result.cabin = product.allowance }
            if product.kind == "checked" && product.allowance.totalWeightKG > (result.checked?.totalWeightKG ?? 0) { result.checked = product.allowance }
        }
        return result
    }
}
public enum Validation {
    public static func search(_ request: SearchRequest, now: Date = Date()) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if request.origin.count != 3 || request.destination.count != 3 || request.origin.uppercased() == request.destination.uppercased() { issues.append(ValidationIssue("route", "Choose two different three-letter airport codes.", componentID: "search.route")) }
        if request.adults < 1 || request.children < 0 || request.adults + request.children > 9 { issues.append(ValidationIssue("passengers", "Book 1–9 passengers, including at least one adult.", componentID: "search.passengers")) }
        if Calendar.current.startOfDay(for: request.outboundDate) < Calendar.current.startOfDay(for: now) { issues.append(ValidationIssue("past-date", "Choose today or a future departure date.", componentID: "search.dates")) }
        if let back = request.returnDate, Calendar.current.startOfDay(for: back) <= Calendar.current.startOfDay(for: request.outboundDate) { issues.append(ValidationIssue("return-date", "Return must be at least one day after departure in this demo.", componentID: "search.dates")) }
        return issues
    }
    public static func seats(_ selected: [SeatSelection], passengers: [Passenger], segments: [Segment]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []; var assigned = Set<String>(); var occupied = Set<String>()
        for item in selected {
            let assignment = "\(item.passengerID):\(item.segmentID)"; let seatKey = "\(item.segmentID):\(item.seatID)"
            if !assigned.insert(assignment).inserted || !occupied.insert(seatKey).inserted { issues.append(ValidationIssue("duplicate-seat-\(assignment)", "Each seat and traveller can be assigned once per flight.", componentID: "seats.map")); continue }
            guard let passenger = passengers.first(where: { $0.id == item.passengerID }), let segment = segments.first(where: { $0.id == item.segmentID }), let seat = Catalog.seats(for: segment).first(where: { $0.id == item.seatID }) else { issues.append(ValidationIssue("invalid-seat-\(assignment)", "Seat selection no longer matches a traveller or available flight.", componentID: "seats.map")); continue }
            if !seat.isAvailable { issues.append(ValidationIssue("unavailable-seat-\(seatKey)", "Seat \(seat.id) is unavailable.", componentID: "seats.map")) }
            if passenger.isChild && seat.isExitRow { issues.append(ValidationIssue("child-exit-seat-\(assignment)", "Children cannot select extra-legroom exit-row seats in this catalogue.", componentID: "seats.map")) }
        }
        return issues
    }
    public static func familyAdjacency(_ selected: [SeatSelection], passengers: [Passenger], segment: Segment) -> [ValidationIssue] {
        let seats = Catalog.seats(for: segment)
        func seatFor(_ passenger: Passenger) -> Seat? { guard let choice = selected.first(where: { $0.passengerID == passenger.id && $0.segmentID == segment.id }) else { return nil }; return seats.first { $0.id == choice.seatID } }
        let adults = passengers.filter { !$0.isChild }.compactMap(seatFor)
        return passengers.filter(\.isChild).compactMap { child in
            guard let childSeat = seatFor(child) else { return ValidationIssue("family-seat-\(child.id)-\(segment.id)", "Select a seat for \(child.displayName) before confirming adjacency.", severity: .warning, componentID: "seats.family") }
            let groups = ["ABC", "DEF"]
            let adjacent = adults.contains { adult in adult.row == childSeat.row && groups.contains { group in let letters = Array(group).map(String.init); guard let a = letters.firstIndex(of: adult.letter), let c = letters.firstIndex(of: childSeat.letter) else { return false }; return abs(a - c) == 1 } }
            return adjacent ? nil : ValidationIssue("family-seat-\(child.id)-\(segment.id)", "\(child.displayName) has no selected adult immediately beside them. Across the aisle does not count.", severity: .warning, componentID: "seats.family")
        }
    }
    public static func review(request: SearchRequest, itinerary: Itinerary, selection: BookingSelection, now: Date = Date()) -> [ValidationIssue] {
        var issues = search(request, now: now) + Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: selection).issues
        if itinerary.transferKind != .direct {
            for direction in Direction.allCases {
                let group = itinerary.segments.filter { $0.direction == direction }
                for pair in zip(group, group.dropFirst()) {
                    issues += Connections.validate(incoming: pair.0, outgoing: pair.1)
                    for passenger in request.passengers {
                        if let incoming = Baggage.allowance(passengerID: passenger.id, segment: pair.0, selection: selection).checked {
                            let onward = Baggage.allowance(passengerID: passenger.id, segment: pair.1, selection: selection).checked
                            issues += Baggage.conflicts(incoming: incoming, onward: onward).map {
                                ValidationIssue("\($0.id)-\(passenger.id)", $0.message, severity: .warning, componentID: "baggage.connection")
                            }
                        }
                    }
                }
            }
        }
        for segment in itinerary.segments where segment.isPegasus { issues += familyAdjacency(selection.seats, passengers: request.passengers, segment: segment) }
        return issues
    }
    /// Keep valid passenger/flight scoped choices when dates change; drop choices invalidated by party or route changes.
    public static func reconcile(_ selection: BookingSelection, passengers: [Passenger], itinerary: Itinerary) -> BookingSelection {
        let passengerIDs = Set(passengers.map(\.id)); let segmentIDs = Set(itinerary.segments.filter(\.isPegasus).map(\.id))
        var result = selection
        result.extras = result.extras.filter { passengerIDs.contains($0.passengerID) && segmentIDs.contains($0.segmentID) }
        result.meals = result.meals.filter { item in passengerIDs.contains(item.passengerID) && segmentIDs.contains(item.segmentID) && Catalog.mealProducts.contains { $0.id == item.productID && (!$0.childOnly || passengers.first(where: { $0.id == item.passengerID })?.isChild == true) } }
        result.seats = result.seats.filter { seats([$0], passengers: passengers, segments: itinerary.segments).isEmpty }
        if result.bundle == .family && (!passengers.contains(where: \.isChild) || !passengers.contains(where: { !$0.isChild })) { result.bundle = .basic }
        return result
    }
}
