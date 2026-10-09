import Foundation

enum V2BookingStage: String, Codable, CaseIterable { case search, results, configuration, review, confirmation, trips }
struct V2Money: Codable, Equatable, Sendable {
    var amountMinor: Int; var currency: String = "EUR"
    var formatted: String { (Decimal(amountMinor) / 100).formatted(.currency(code: currency)) }
}
struct V2Airport: Codable, Equatable, Identifiable, Sendable {
    var code: String; var name: String; var city: String; var country: String; var timeZone: String
    var id: String { code }
}
struct V2DeviceContext: Codable, Sendable {
    var currentDate: String; var locale: String; var timeZone: String
    static var current: Self { .init(currentDate: V2Dates.day(Date()), locale: Locale.current.identifier, timeZone: TimeZone.current.identifier) }
}
struct V2UnresolvedField: Codable, Equatable, Identifiable, Sendable {
    var field: String; var question: String; var choices: [String]
    var id: String { field }
}
struct V2DateWindow: Codable, Equatable, Sendable { var start: String; var end: String }
struct V2IncomingFlight: Codable, Equatable, Sendable {
    var airline: String; var flightNumber: String?; var arrivalAirport: String; var arrivalAt: String
    var departureAirport: String?; var minimumConnectionMinutes: Int = 180; var baggageReclaim = true; var confirmed = false
    enum CodingKeys: String, CodingKey { case airline, flightNumber, arrivalAirport, arrivalAt, departureAirport, minimumConnectionMinutes, baggageReclaim, confirmed }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(airline, forKey: .airline); try c.encode(flightNumber, forKey: .flightNumber); try c.encode(arrivalAirport, forKey: .arrivalAirport); try c.encode(arrivalAt, forKey: .arrivalAt); try c.encode(departureAirport, forKey: .departureAirport)
        try c.encode(minimumConnectionMinutes, forKey: .minimumConnectionMinutes); try c.encode(baggageReclaim, forKey: .baggageReclaim); try c.encode(confirmed, forKey: .confirmed)
    }
}
struct V2SearchIntent: Codable, Equatable, Sendable {
    var revision = 0
    var originAirport: String? = nil
    var destinationAirports: [String] = []
    var tripType = "one_way"
    var outboundDate: String? = V2Dates.day(Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
    var returnDate: String? = nil
    var dateWindow: V2DateWindow? = nil
    var durationNights: Int? = nil
    var adults = 1
    var childAges: [Int?] = []
    var budgetMinor: Int? = nil
    var budgetScope: String? = nil
    var currency = "EUR"
    var checkedBags: Int? = nil
    var baggageScope: String? = nil
    var baggageDirection: String? = nil
    var noOvernight = true
    var maxConnections: Int? = 0
    var departureAfter: String? = nil
    var arrivalDeadline: String? = nil
    var keepTogether = false
    var vegetarian = false
    var noAlcohol = false
    var meals = false
    var lockedFields: [String] = []
    var unresolved: [V2UnresolvedField] = []
    var incomingFlight: V2IncomingFlight? = nil
    var partySize: Int { adults + childAges.count }
    enum CodingKeys: String, CodingKey { case revision, originAirport, destinationAirports, tripType, outboundDate, returnDate, dateWindow, durationNights, adults, childAges, budgetMinor, budgetScope, currency, checkedBags, baggageScope, baggageDirection, noOvernight, maxConnections, departureAfter, arrivalDeadline, keepTogether, vegetarian, noAlcohol, meals, lockedFields, unresolved, incomingFlight }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(revision, forKey: .revision); try c.encode(originAirport, forKey: .originAirport); try c.encode(destinationAirports, forKey: .destinationAirports); try c.encode(tripType, forKey: .tripType)
        try c.encode(outboundDate, forKey: .outboundDate); try c.encode(returnDate, forKey: .returnDate); try c.encode(dateWindow, forKey: .dateWindow); try c.encode(durationNights, forKey: .durationNights)
        try c.encode(adults, forKey: .adults); try c.encode(childAges, forKey: .childAges); try c.encode(budgetMinor, forKey: .budgetMinor); try c.encode(budgetScope, forKey: .budgetScope); try c.encode(currency, forKey: .currency)
        try c.encode(checkedBags, forKey: .checkedBags); try c.encode(baggageScope, forKey: .baggageScope); try c.encode(baggageDirection, forKey: .baggageDirection); try c.encode(noOvernight, forKey: .noOvernight); try c.encode(maxConnections, forKey: .maxConnections)
        try c.encode(departureAfter, forKey: .departureAfter); try c.encode(arrivalDeadline, forKey: .arrivalDeadline); try c.encode(keepTogether, forKey: .keepTogether); try c.encode(vegetarian, forKey: .vegetarian); try c.encode(noAlcohol, forKey: .noAlcohol); try c.encode(meals, forKey: .meals)
        try c.encode(lockedFields, forKey: .lockedFields); try c.encode(unresolved, forKey: .unresolved); try c.encode(incomingFlight, forKey: .incomingFlight)
    }
}
struct V2CheckedBaggage: Codable, Equatable, Sendable { var pieces: Int; var totalWeightKg: Int; var maxPieceWeightKg: Int; var maxLinearCm: Int }
struct V2Underseat: Codable, Equatable, Sendable { var weightKg: Int; var dimensionsCm: [Int] }
struct V2FlightSegment: Codable, Equatable, Identifiable, Sendable {
    var id: String; var operatingCarrier: String; var flightNumber: String?; var origin: V2Airport; var destination: V2Airport
    var departureAt: String; var arrivalAt: String; var durationMinutes: Int; var direction: String; var ticketGroup: String
    var checkedBaggage: V2CheckedBaggage?; var underseat: V2Underseat?; var independentlyBooked: Bool
    var departureText: String { V2Dates.local(departureAt, zone: origin.timeZone) }
    var arrivalText: String { V2Dates.local(arrivalAt, zone: destination.timeZone) }
    var routeLabel: String { "\(origin.code)–\(destination.code)" }
}
struct V2Itinerary: Codable, Equatable, Identifiable, Sendable {
    var id: String; var segments: [V2FlightSegment]; var durationMinutes: Int; var connectionMinutes: [Int]; var overnight: Bool
    var transferType: String; var transferSteps: [String]; var terms: String; var entryRequirements: String
    var routeLabel: String { guard let first = segments.first, let last = segments.last(where: { $0.direction == "outbound" }) else { return "Journey" }; return "\(first.origin.code)–\(last.destination.code)" }
}
struct V2FareBundle: Codable, Equatable, Identifiable, Sendable {
    var id: String; var name: String; var pricePerPassengerSegmentMinor: Int; var checkedPieces: Int; var checkedWeightKg: Int
    var cabinIncluded: Bool; var standardSeatIncluded: Bool; var mealIncluded: Bool; var conditions: String
}
struct V2AncillaryProduct: Codable, Equatable, Identifiable, Sendable {
    var id: String; var type: String; var name: String; var priceMinor: Int; var weightKg: Int?; var pieces: Int?
    var tags: [String]; var childOnly: Bool; var eligibleSegmentIds: [String]
}
struct V2Seat: Codable, Equatable, Identifiable, Sendable {
    var id: String; var row: Int; var column: String; var available: Bool; var extraLegroom: Bool; var childAllowed: Bool; var priceMinor: Int
}
struct V2SeatMap: Codable, Equatable, Identifiable, Sendable {
    var segmentId: String; var seats: [V2Seat]; var suggestedFamilySeats: [String]; var familyAvailable: Bool
    var id: String { segmentId }
}
struct V2OfferCapabilities: Codable, Equatable, Sendable {
    var ancillaries: Bool; var seats: Bool; var quote: Bool; var checkout: Bool; var externalBooking: Bool
    static let sample = Self(ancillaries: true, seats: true, quote: true, checkout: true, externalBooking: false)
    static let unavailable = Self(ancillaries: false, seats: false, quote: false, checkout: false, externalBooking: false)
}
struct V2InventoryProvider: Codable, Equatable, Identifiable, Sendable {
    var id: String; var label: String; var source: String; var search: Bool
    var ancillaries: Bool; var seats: Bool; var quote: Bool; var checkout: Bool; var externalBooking: Bool
    var authenticationRequired: Bool; var notice: String
}
struct V2ProvidersResponse: Codable, Sendable { var defaultProvider: String; var providers: [V2InventoryProvider] }
struct V2FlightOffer: Codable, Equatable, Identifiable, Sendable {
    var id: String; var provider: String; var source: String; var itinerary: V2Itinerary
    var basePrice: V2Money?; var totalPrice: V2Money; var extrasPrice: V2Money?; var priceScope: String; var partySize: Int
    var bundleId: String?; var includedCheckedPieces: Int?; var includedCheckedWeightKg: Int?; var baggageSummary: String
    var requestedExtrasPriced: Bool; var available: Bool; var remainingSeats: Int?; var expiresAt: String?; var requestFingerprint: String; var notices: [String]
    var bookingURL: String? = nil
    var capabilities: V2OfferCapabilities? = nil
    var isExpired: Bool { guard let expiresAt else { return false }; return (V2Dates.instant(expiresAt) ?? .distantPast) <= Date() }
    var effectiveCapabilities: V2OfferCapabilities { capabilities ?? (source == "sample" && provider == "sample" ? .sample : .unavailable) }
    var externalBookingURL: URL? {
        guard effectiveCapabilities.externalBooking, let bookingURL, let url = URL(string: bookingURL), url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), host == "flypgs.com" || host.hasSuffix(".flypgs.com") else { return nil }
        return url
    }
}
struct V2SearchResponse: Codable, Sendable {
    var revision: Int; var source: String; var offers: [V2FlightOffer]; var totalMatches: Int; var unresolved: [V2UnresolvedField]
    var notice: String; var searchedWindow: V2DateWindow; var requestFingerprint: String
}
struct V2Capabilities: Codable, Equatable, Sendable {
    var liveAI: Bool; var textModel: String; var visionModel: String; var inventory: String; var payments: String; var fulfilment: String
    var sampleWindow: V2DateWindow; var offerCount: Int; var routePairs: Int; var providerNotice: String
}
struct V2Route: Codable, Equatable, Sendable { var origin: String; var destination: String }
struct V2Catalog: Codable, Sendable { var capabilities: V2Capabilities; var airports: [V2Airport]; var bundles: [V2FareBundle]; var routes: [V2Route] }
struct V2AIExtraction: Codable, Sendable {
    var revision: Int; var source: String; var model: String; var requestId: String; var latencyMs: Int; var intent: V2SearchIntent; var summary: String
}
struct V2TripImport: Codable, Sendable {
    var revision: Int; var source: String; var model: String; var requestId: String; var latencyMs: Int; var kind: String
    var title: String?; var location: String?; var airportCandidates: [String]; var localDate: String?; var localTime: String?; var year: Int?; var timeZone: String?
    var incomingFlight: V2IncomingFlight?; var unresolved: [V2UnresolvedField]; var suggestedArrivalBufferMinutes: Int; var notice: String
}
struct V2PackingItem: Codable, Equatable, Identifiable, Sendable {
    var id: String; var category: String; var label: String; var visibleCount: Int?; var confidence: String
    enum CodingKeys: String, CodingKey { case id, category, label, visibleCount, confidence }
    func encode(to encoder: Encoder) throws { var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(id, forKey: .id); try c.encode(category, forKey: .category); try c.encode(label, forKey: .label); try c.encode(visibleCount, forKey: .visibleCount); try c.encode(confidence, forKey: .confidence) }
}
struct V2PackingAssessment: Codable, Sendable {
    var revision: Int; var source: String; var model: String; var requestId: String; var latencyMs: Int; var summary: String
    var items: [V2PackingItem]; var uncertainties: [String]; var requiresMeasurements: Bool
}
struct V2BagSelection: Codable, Equatable, Sendable { var passengerId: String; var segmentId: String; var productId: String }
struct V2SeatSelection: Codable, Equatable, Sendable { var passengerId: String; var segmentId: String; var seatId: String }
struct V2MealSelection: Codable, Equatable, Sendable { var passengerId: String; var segmentId: String; var productId: String }
struct V2Selection: Codable, Equatable, Sendable {
    var bundleId = "light"; var bags: [V2BagSelection] = []; var seats: [V2SeatSelection] = []; var meals: [V2MealSelection] = []
}
struct V2PassengerScope: Codable, Equatable, Identifiable, Sendable { var id: String; var type: String; var age: Int? }
struct V2Passenger: Codable, Equatable, Identifiable, Sendable {
    var id: String; var type: String; var age: Int?; var givenName = ""; var familyName = ""
    var fullName: String { [givenName.trimmingCharacters(in: .whitespacesAndNewlines), familyName.trimmingCharacters(in: .whitespacesAndNewlines)].joined(separator: " ") }
    var isValid: Bool { !givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (type != "child" || (age.map { (2...11).contains($0) } ?? false)) }
}
struct V2QuoteItem: Codable, Equatable, Identifiable, Sendable { var id: String; var label: String; var amountMinor: Int; var passengerId: String?; var segmentId: String? }
struct V2Quote: Codable, Equatable, Identifiable, Sendable {
    var id: String; var revision: Int; var source: String; var provider: String; var offerId: String; var selection: V2Selection; var passengers: [V2PassengerScope]
    var items: [V2QuoteItem]; var basePrice: V2Money; var extrasPrice: V2Money; var total: V2Money; var status: String; var expiresAt: String; var priceScope: String; var notices: [String]
    var isValid: Bool { status == "valid" && !isExpired && total.currency == "EUR" && basePrice.currency == "EUR" && extrasPrice.currency == "EUR" && basePrice.amountMinor >= 0 && extrasPrice.amountMinor >= 0 && basePrice.amountMinor + extrasPrice.amountMinor == total.amountMinor && items.reduce(0) { $0 + $1.amountMinor } == total.amountMinor }
    var isExpired: Bool { (V2Dates.instant(expiresAt) ?? .distantPast) <= Date() }
}
struct V2OfferServices: Codable, Sendable {
    var offerId: String; var bundles: [V2FareBundle]; var products: [V2AncillaryProduct]; var seatMaps: [V2SeatMap]; var passengers: [V2PassengerScope]; var defaultSelection: V2Selection
}
struct V2ConstraintChange: Codable, Equatable, Identifiable, Sendable { var field: String; var from: String; var to: String; var id: String { field } }
struct V2Alternative: Codable, Equatable, Identifiable, Sendable {
    var id: String; var offer: V2FlightOffer; var changes: [V2ConstraintChange]; var intent: V2SearchIntent; var explanation: String; var requiresConfirmation: Bool
}
struct V2AlternativesResponse: Codable, Sendable { var revision: Int; var alternatives: [V2Alternative]; var notice: String; var explanationSource: String; var model: String?; var requestId: String? }
struct V2ComparisonDifference: Codable, Identifiable, Sendable { var label: String; var values: [String]; var id: String { label } }
struct V2Comparison: Codable, Sendable {
    var revision: Int; var offers: [V2FlightOffer]; var differences: [V2ComparisonDifference]; var explanation: String?; var explanationSource: String; var model: String?; var requestId: String?; var notice: String
}
struct V2PackingMeasurement: Codable, Equatable, Identifiable, Sendable {
    var passengerId: String; var direction: String; var pieces: Int; var totalWeightKg: Int; var maxPieceWeightKg: Int; var maxLinearCm: Int
    var dimensionsCm: [Int]? = nil
    var id: String { passengerId + ":" + direction }
}
struct V2PackingOption: Codable, Equatable, Identifiable, Sendable {
    var id: String; var title: String; var explanation: String; var selection: V2Selection; var total: V2Money; var differenceMinor: Int; var action: String; var requiresConfirmation: Bool
}
struct V2PackingOptionsResponse: Codable, Sendable { var status: String; var questions: [String]; var options: [V2PackingOption]; var notice: String }
struct V2Order: Codable, Equatable, Identifiable, Sendable {
    var id: String; var quoteId: String; var reference: String; var state: String; var paymentStatus: String; var fulfilmentStatus: String; var ticketIssued: Bool
    var total: V2Money; var createdAt: String; var itinerary: V2Itinerary; var selection: V2Selection; var travellerNames: [String]; var notice: String
}
enum V2Dates {
    static func day(_ date: Date) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    static func date(_ day: String) -> Date? { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.date(from: day) }
    static func instant(_ value: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
    static func localDay(_ date: Date, zone: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: zone); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    static func local(_ value: String, zone: String) -> String { guard let date = instant(value) else { return value }; let f = DateFormatter(); f.locale = Locale.current; f.timeZone = TimeZone(identifier: zone); f.dateFormat = "d MMM, HH:mm"; return f.string(from: date) }
}
