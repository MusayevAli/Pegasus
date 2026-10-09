import Foundation

public enum DemoJourney: String, Codable, CaseIterable, Identifiable, Sendable {
    case barcelonaFamily, usConnection, soloLight
    public var id: String { rawValue }
    public var title: String {
        switch self { case .barcelonaFamily: "Barcelona, together"; case .usConnection: "New York to Istanbul"; case .soloLight: "Antalya, travelling light" }
    }
}
public enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
    case outbound, inbound
    public var id: String { rawValue }
    public var title: String { self == .outbound ? "Outbound" : "Return" }
}
public enum FareBundle: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic, family, flex
    public var id: String { rawValue }
    public var title: String { switch self { case .basic: "Essential"; case .family: "Together"; case .flex: "More flexibility" } }
}
public enum TransferKind: String, Codable, Sendable { case direct, selfTransfer, throughTicket, protectedSelfTransfer }
public enum Severity: String, Codable, Sendable { case error, warning }

public struct Passenger: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var isChild: Bool
    public init(id: String, displayName: String, isChild: Bool = false) { self.id = id; self.displayName = displayName; self.isChild = isChild }
}
public struct SearchRequest: Codable, Equatable, Sendable {
    public var origin: String
    public var destination: String
    public var outboundDate: Date
    public var returnDate: Date?
    public var adults: Int
    public var children: Int
    public init(origin: String = "SAW", destination: String = "BCN", outboundDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date())!, returnDate: Date? = nil, adults: Int = 2, children: Int = 1) {
        self.origin = origin; self.destination = destination; self.outboundDate = outboundDate; self.returnDate = returnDate; self.adults = adults; self.children = children
    }
    public var passengers: [Passenger] {
        (0..<max(0, min(adults, 9))).map { Passenger(id: "adult-\($0 + 1)", displayName: "Adult \($0 + 1)") } +
        (0..<max(0, min(children, 8))).map { Passenger(id: "child-\($0 + 1)", displayName: "Child \($0 + 1)", isChild: true) }
    }
    public var nights: Int { guard let returnDate else { return 0 }; return max(0, Calendar.current.dateComponents([.day], from: outboundDate, to: returnDate).day ?? 0) }
}
public struct TripNeeds: Codable, Equatable, Sendable {
    public var travellingLight: Bool
    public var giftsOnReturn: Bool
    public var stayTogether: Bool
    public var childMeals: Bool
    public var noAlcohol: Bool
    public var note: String
    public var packingItems: [String]
    public init(travellingLight: Bool = false, giftsOnReturn: Bool = false, stayTogether: Bool = false, childMeals: Bool = false, noAlcohol: Bool = true, note: String = "", packingItems: [String] = []) {
        self.travellingLight = travellingLight; self.giftsOnReturn = giftsOnReturn; self.stayTogether = stayTogether; self.childMeals = childMeals; self.noAlcohol = noAlcohol; self.note = note; self.packingItems = packingItems
    }
}
public struct BagDimensions: Codable, Equatable, Sendable {
    public var lengthCM: Int
    public var widthCM: Int
    public var heightCM: Int
    public init(_ lengthCM: Int, _ widthCM: Int, _ heightCM: Int) { self.lengthCM = lengthCM; self.widthCM = widthCM; self.heightCM = heightCM }
    public var label: String { "\(lengthCM) × \(widthCM) × \(heightCM) cm" }
    public var linearCM: Int { lengthCM + widthCM + heightCM }
    public var sortedEdges: [Int] { [lengthCM, widthCM, heightCM].sorted() }
}
public struct BaggageLimit: Codable, Equatable, Sendable {
    public var pieces: Int
    public var totalWeightKG: Int
    public var maxPieceWeightKG: Int
    public var dimensions: BagDimensions?
    public var maxLinearCM: Int?
    public init(pieces: Int = 1, totalWeightKG: Int, maxPieceWeightKG: Int? = nil, dimensions: BagDimensions? = nil, maxLinearCM: Int? = nil) {
        self.pieces = pieces; self.totalWeightKG = totalWeightKG; self.maxPieceWeightKG = maxPieceWeightKG ?? totalWeightKG; self.dimensions = dimensions; self.maxLinearCM = maxLinearCM
    }
    public var label: String { "\(pieces) piece\(pieces == 1 ? "" : "s") · \(totalWeightKG) kg total" }
}
public struct BaggageAllowance: Codable, Equatable, Sendable {
    public var underseat: BaggageLimit
    public var cabin: BaggageLimit?
    public var checked: BaggageLimit?
    public var poolingAllowed: Bool
    public init(underseat: BaggageLimit = BaggageLimit(totalWeightKG: 3, dimensions: BagDimensions(40, 30, 15)), cabin: BaggageLimit? = nil, checked: BaggageLimit? = nil, poolingAllowed: Bool = false) {
        self.underseat = underseat; self.cabin = cabin; self.checked = checked; self.poolingAllowed = poolingAllowed
    }
    public var summary: String { ["Underseat \(underseat.totalWeightKG) kg", cabin.map { "Cabin \($0.totalWeightKG) kg" }, checked.map { "Checked \($0.totalWeightKG) kg" }].compactMap { $0 }.joined(separator: " · ") }
}
public struct Segment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var carrier: String
    public var flightNumber: String
    public var origin: String
    public var destination: String
    public var departure: Date
    public var arrival: Date
    public var originTimeZone: String
    public var destinationTimeZone: String
    public var direction: Direction
    public var includedBaggage: BaggageAllowance
    public init(id: String, carrier: String = "Pegasus", flightNumber: String, origin: String, destination: String, departure: Date, arrival: Date, originTimeZone: String, destinationTimeZone: String, direction: Direction = .outbound, includedBaggage: BaggageAllowance = BaggageAllowance()) {
        self.id = id; self.carrier = carrier; self.flightNumber = flightNumber; self.origin = origin; self.destination = destination; self.departure = departure; self.arrival = arrival; self.originTimeZone = originTimeZone; self.destinationTimeZone = destinationTimeZone; self.direction = direction; self.includedBaggage = includedBaggage
    }
    public var isPegasus: Bool { carrier == "Pegasus" }
    public var durationMinutes: Int { Int(arrival.timeIntervalSince(departure) / 60) }
    public func localDeparture(_ template: String = "MMM d, HH:mm") -> String { Self.local(departure, zone: originTimeZone, template: template) }
    public func localArrival(_ template: String = "MMM d, HH:mm") -> String { Self.local(arrival, zone: destinationTimeZone, template: template) }
    private static func local(_ date: Date, zone: String, template: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: zone); f.dateFormat = template; return f.string(from: date) }
}
public struct Itinerary: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var segments: [Segment]
    public var basePricePerAdultCents: Int
    public var basePricePerChildCents: Int
    public var currency: String
    public var fareConditions: String
    public var transferKind: TransferKind
    public init(id: String, title: String, segments: [Segment], basePricePerAdultCents: Int, basePricePerChildCents: Int, currency: String = "EUR", fareConditions: String = "Illustrative demo fare. Non-refundable; provider terms require live validation.", transferKind: TransferKind = .direct) {
        self.id = id; self.title = title; self.segments = segments; self.basePricePerAdultCents = basePricePerAdultCents; self.basePricePerChildCents = basePricePerChildCents; self.currency = currency; self.fareConditions = fareConditions; self.transferKind = transferKind
    }
    public var durationMinutes: Int {
        Direction.allCases.reduce(0) { total, direction in let group = segments.filter { $0.direction == direction }; guard let first = group.first, let last = group.last else { return total }; return total + Int(last.arrival.timeIntervalSince(first.departure) / 60) }
    }
    public var connectionMinutes: Int? { let group = segments.filter { $0.direction == .outbound }; guard group.count > 1 else { return nil }; return Int(group[1].departure.timeIntervalSince(group[0].arrival) / 60) }
    public var isDemo: Bool { true }
    public var transferTerms: String { transferKind == .selfTransfer ? "Separate tickets. Collect and re-check baggage at LGW, complete entry formalities if required, and pass security. No connection protection or through-checked baggage. You bear onward rebooking costs if delayed. Entry/transit requirements: not checked." : "Demo airline combinations and conditions. Entry/transit requirements: not checked." }
}
public struct ValidationIssue: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var message: String
    public var severity: Severity
    public var componentID: String
    public init(_ id: String, _ message: String, severity: Severity = .error, componentID: String = "review") { self.id = id; self.message = message; self.severity = severity; self.componentID = componentID }
}
public struct RejectedItinerary: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var reason: String
    public var connectionMinutes: Int
    public init(id: String, title: String, reason: String, connectionMinutes: Int) { self.id = id; self.title = title; self.reason = reason; self.connectionMinutes = connectionMinutes }
}
public struct SearchResult: Sendable {
    public var itineraries: [Itinerary]
    public var rejected: [RejectedItinerary]
    public var issues: [ValidationIssue]
    public init(itineraries: [Itinerary] = [], rejected: [RejectedItinerary] = [], issues: [ValidationIssue] = []) { self.itineraries = itineraries; self.rejected = rejected; self.issues = issues }
}
public struct ExtraSelection: Codable, Equatable, Hashable, Sendable {
    public var passengerID: String
    public var segmentID: String
    public var productID: String
    public init(passengerID: String, segmentID: String, productID: String) { self.passengerID = passengerID; self.segmentID = segmentID; self.productID = productID }
}
public struct SeatSelection: Codable, Equatable, Hashable, Sendable {
    public var passengerID: String
    public var segmentID: String
    public var seatID: String
    public init(passengerID: String, segmentID: String, seatID: String) { self.passengerID = passengerID; self.segmentID = segmentID; self.seatID = seatID }
}
public struct MealSelection: Codable, Equatable, Hashable, Sendable {
    public var passengerID: String
    public var segmentID: String
    public var productID: String
    public init(passengerID: String, segmentID: String, productID: String) { self.passengerID = passengerID; self.segmentID = segmentID; self.productID = productID }
}
public struct BookingSelection: Codable, Equatable, Sendable {
    public var bundle: FareBundle
    public var extras: [ExtraSelection]
    public var seats: [SeatSelection]
    public var meals: [MealSelection]
    public init(bundle: FareBundle = .basic, extras: [ExtraSelection] = [], seats: [SeatSelection] = [], meals: [MealSelection] = []) { self.bundle = bundle; self.extras = extras; self.seats = seats; self.meals = meals }
}
public struct BaggageProduct: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var priceCents: Int
    public var description: String
    public var kind: String
    public var allowance: BaggageLimit
    public init(id: String, name: String, priceCents: Int, description: String, kind: String, allowance: BaggageLimit) { self.id = id; self.name = name; self.priceCents = priceCents; self.description = description; self.kind = kind; self.allowance = allowance }
}
public struct MealProduct: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var priceCents: Int
    public var description: String
    public var tags: [String]
    public var childOnly: Bool
    public init(id: String, name: String, priceCents: Int, description: String, tags: [String], childOnly: Bool = false) { self.id = id; self.name = name; self.priceCents = priceCents; self.description = description; self.tags = tags; self.childOnly = childOnly }
}
public struct Seat: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var row: Int
    public var letter: String
    public var priceCents: Int
    public var isAvailable: Bool
    public var isExitRow: Bool
    public init(id: String, row: Int, letter: String, priceCents: Int, isAvailable: Bool = true, isExitRow: Bool = false) { self.id = id; self.row = row; self.letter = letter; self.priceCents = priceCents; self.isAvailable = isAvailable; self.isExitRow = isExitRow }
}
public struct QuoteLine: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var amountCents: Int
    public var passengerID: String?
    public var segmentID: String?
    public init(id: String, label: String, amountCents: Int, passengerID: String? = nil, segmentID: String? = nil) { self.id = id; self.label = label; self.amountCents = amountCents; self.passengerID = passengerID; self.segmentID = segmentID }
}
public struct Quote: Codable, Equatable, Sendable {
    public var totalCents: Int
    public var baseCents: Int
    public var extrasCents: Int
    public var currency: String
    public var lines: [QuoteLine]
    public var issues: [ValidationIssue]
    public var isValid: Bool { !issues.contains { $0.severity == .error } }
    public init(totalCents: Int, baseCents: Int, extrasCents: Int, currency: String = "EUR", lines: [QuoteLine] = [], issues: [ValidationIssue] = []) { self.totalCents = totalCents; self.baseCents = baseCents; self.extrasCents = extrasCents; self.currency = currency; self.lines = lines; self.issues = issues }
}
public struct Recommendation: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var type: String
    public var title: String
    public var explanation: String
    public var selection: BookingSelection
    public var totalCents: Int
    public var savingsCents: Int
    public var requiredUserConfirmation: Bool
    public init(id: String, type: String, title: String, explanation: String, selection: BookingSelection, totalCents: Int, savingsCents: Int = 0, requiredUserConfirmation: Bool = true) { self.id = id; self.type = type; self.title = title; self.explanation = explanation; self.selection = selection; self.totalCents = totalCents; self.savingsCents = savingsCents; self.requiredUserConfirmation = requiredUserConfirmation }
}
public enum Money {
    public static func format(_ cents: Int, currency: String = "EUR") -> String { let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency; f.locale = Locale(identifier: "en_IE"); return f.string(from: NSDecimalNumber(value: cents).dividing(by: 100)) ?? "\(currency) \(cents / 100)" }
}
