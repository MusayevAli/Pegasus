import Foundation
import Testing
@testable import TripFitCore

struct TripFitCoreTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
    private func fixture(_ journey: DemoJourney) throws -> (SearchRequest, Itinerary) {
        let request = Catalog.demoSearch(journey, now: now)
        return (request, try requireValue(Catalog.search(request, now: now).itineraries.first))
    }
    @Test func testFamilyCheapestBundleExactPartyTotalAndNoDoubleCharging() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        let recommendations = Pricing.recommend(itinerary: itinerary, passengers: request.passengers, selection: BookingSelection(), needs: Catalog.demoNeeds(.barcelonaFamily))
        let recommended = try requireValue(recommendations.first { $0.selection.bundle == .family })
        expectEqual(recommended.totalCents, 77700)
        expectEqual(recommended.savingsCents, 5400)
        let quote = Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: recommended.selection)
        expectTrue(quote.isValid)
        expectEqual(quote.baseCents, 49500)
        expectEqual(quote.extrasCents, 28200)
        expectEqual(quote.lines.filter { $0.id.hasPrefix("meal-") }.reduce(0) { $0 + $1.amountCents }, 0)
        expectEqual(quote.lines.filter { $0.id.hasPrefix("seat-") }.reduce(0) { $0 + $1.amountCents }, 0)
        expectEqual(quote.lines.reduce(0) { $0 + $1.amountCents }, quote.totalCents)
        var individual = recommended.selection; individual.bundle = .basic
        expectEqual(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: individual).totalCents, 83100)
    }
    @Test func testFamilyBundleEligibilityAndGroupScope() throws {
        let (request, itinerary) = try fixture(.soloLight)
        let invalid = Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: BookingSelection(bundle: .family))
        expectFalse(invalid.isValid)
        expectTrue(invalid.issues.contains { $0.id == "family-eligibility" })
        let (family, trip) = try fixture(.barcelonaFamily)
        let quote = Pricing.quote(itinerary: trip, passengers: family.passengers, selection: BookingSelection(bundle: .family))
        expectEqual(quote.totalCents, 74700) // Full party, both Pegasus flights, even without explicit selections.
    }
    @Test func testIncludedCheckedAllowanceIsNeverChargedAgain() throws {
        let (request, itinerary) = try fixture(.usConnection)
        let selected = BookingSelection(extras: [ExtraSelection(passengerID: "adult-1", segmentID: "us-pegasus", productID: "peg-checked20")])
        expectEqual(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: selected).totalCents, 48000)
        var upgrade = selected; upgrade.extras[0].productID = "peg-checked25"
        expectEqual(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: upgrade).totalCents, 49000)
        var flex = upgrade; flex.bundle = .flex
        expectEqual(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: flex).totalCents, 54500)
    }
    @Test func testOutAndReturnBaggageAreIndependentAndNoPooling() throws {
        let (_, itinerary) = try fixture(.barcelonaFamily)
        let selected = BookingSelection(extras: [ExtraSelection(passengerID: "adult-1", segmentID: "family-in", productID: "peg-checked25")])
        expectTrue(Baggage.allowance(passengerID: "adult-1", segment: itinerary.segments[0], selection: selected).checked == nil)
        expectEqual(Baggage.allowance(passengerID: "adult-1", segment: itinerary.segments[1], selection: selected).checked?.totalWeightKG, 25)
        expectTrue(Baggage.allowance(passengerID: "adult-2", segment: itinerary.segments[1], selection: selected).checked == nil)
        expectFalse(Baggage.allowance(passengerID: "adult-1", segment: itinerary.segments[1], selection: selected).poolingAllowed)
    }
    @Test func testDuplicateUnknownWrongPassengerAndExternalExtraRejected() throws {
        let (request, itinerary) = try fixture(.usConnection)
        for extras in [
            [ExtraSelection(passengerID: "adult-1", segmentID: "us-external", productID: "peg-checked25")],
            [ExtraSelection(passengerID: "adult-8", segmentID: "us-pegasus", productID: "peg-checked25")],
            [ExtraSelection(passengerID: "adult-1", segmentID: "us-pegasus", productID: "invented")],
            [ExtraSelection(passengerID: "adult-1", segmentID: "us-pegasus", productID: "peg-checked20"), ExtraSelection(passengerID: "adult-1", segmentID: "us-pegasus", productID: "peg-checked25")]
        ] { expectFalse(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: BookingSelection(extras: extras)).isValid) }
    }
    @Test func testSoloCanRemoveUnnecessaryBaggageAndKeepSeatsMeals() throws {
        let (request, itinerary) = try fixture(.soloLight)
        let selected = BookingSelection(extras: [ExtraSelection(passengerID: "adult-1", segmentID: "solo-out", productID: "peg-cabin")], seats: [SeatSelection(passengerID: "adult-1", segmentID: "solo-out", seatID: "4A")], meals: [MealSelection(passengerID: "adult-1", segmentID: "solo-out", productID: "peg-meal-veggie")])
        let recommendation = try requireValue(Pricing.recommend(itinerary: itinerary, passengers: request.passengers, selection: selected, needs: Catalog.demoNeeds(.soloLight)).first)
        expectEqual(recommendation.id, "keep-allowance-solo")
        expectEqual(recommendation.savingsCents, 1800)
        expectEqual(recommendation.totalCents, 7200)
        expectEqual(recommendation.selection.seats, selected.seats)
        expectEqual(recommendation.selection.meals, selected.meals)
        expectEqual(selected.extras.count, 1) // Proposals do not mutate purchases.
    }
    @Test func testKeepExistingAllowanceRecommendationAtZeroExtras() throws {
        let (request, itinerary) = try fixture(.soloLight)
        let recommendation = try requireValue(Pricing.recommend(itinerary: itinerary, passengers: request.passengers, selection: BookingSelection(), needs: Catalog.demoNeeds(.soloLight)).first)
        expectEqual(recommendation.totalCents, 4500)
        expectEqual(recommendation.savingsCents, 0)
        expectTrue(recommendation.selection.extras.isEmpty)
    }
    @Test func testGiftPreferenceOnlyChangesProposalsAndPreservesManualBaggage() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        let selected = BookingSelection(extras: [ExtraSelection(passengerID: "adult-1", segmentID: "family-out", productID: "peg-cabin")])
        let withGifts = Pricing.recommend(itinerary: itinerary, passengers: request.passengers, selection: selected, needs: TripNeeds(giftsOnReturn: true))
        let proposed = try requireValue(withGifts.first).selection
        expectTrue(proposed.extras.contains(selected.extras[0]))
        expectEqual(proposed.extras.filter { $0.productID == "peg-checked25" }.map(\.segmentID), ["family-in"])
        expectEqual(selected.extras.count, 1)
        let removedPreference = Pricing.recommend(itinerary: itinerary, passengers: request.passengers, selection: proposed, needs: TripNeeds())
        expectFalse(removedPreference.contains { !$0.selection.extras.contains(proposed.extras.last!) })
    }
    @Test func testSameAirportAndTimeZoneAwareConnectionRules() throws {
        let (_, itinerary) = try fixture(.usConnection)
        let incoming = itinerary.segments[0]; var onward = itinerary.segments[1]
        expectEqual(incoming.durationMinutes, 420)
        expectEqual(itinerary.connectionMinutes, 240)
        expectTrue(Connections.validate(incoming: incoming, outgoing: onward).isEmpty)
        onward.origin = "LHR"
        expectTrue(Connections.validate(incoming: incoming, outgoing: onward).contains { $0.id == "airport-mismatch" })
        onward.origin = "LGW"; onward.departure = incoming.arrival.addingTimeInterval(85 * 60)
        expectTrue(Connections.validate(incoming: incoming, outgoing: onward).contains { $0.id == "connection-too-short" })
        let result = Catalog.search(Catalog.demoSearch(.usConnection, now: now), now: now)
        expectEqual(result.rejected.first?.connectionMinutes, 85)
    }
    @Test func testCheckInDeadlineCanTightenBuffer() throws {
        let (_, itinerary) = try fixture(.usConnection)
        let strict = TransferRules(minimumConnectionMinutes: 60, baggageCollectionMinutes: 80, entryAndCheckInMinutes: 100, securityMinutes: 20, checkInDeadlineMinutes: 90)
        expectTrue(Connections.validate(incoming: itinerary.segments[0], outgoing: itinerary.segments[1], rules: strict).contains { $0.id == "connection-too-short" })
    }
    @Test func testScheduleUsesDestinationZonesAcrossDST() throws {
        var search = Catalog.demoSearch(.usConnection, now: now)
        search.outboundDate = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!
        let itinerary = try requireValue(Catalog.search(search, now: now).itineraries.first)
        expectEqual(itinerary.segments[0].localDeparture("HH:mm"), "20:00")
        expectEqual(itinerary.segments[0].localArrival("HH:mm"), "08:00")
        expectEqual(itinerary.durationMinutes, 890)
    }
    @Test func testPieceWeightCountAndDimensionsComparedIndependently() {
        let incoming = BaggageLimit(pieces: 2, totalWeightKG: 23, maxPieceWeightKG: 23, dimensions: BagDimensions(60, 50, 30))
        let onward = BaggageLimit(pieces: 1, totalWeightKG: 20, maxPieceWeightKG: 20, dimensions: BagDimensions(55, 40, 20), maxLinearCM: 100)
        let conflicts = Baggage.conflicts(incoming: incoming, onward: onward)
        expectEqual(Set(conflicts.map(\.id)), Set(["piece-count", "total-weight", "piece-weight", "dimensions", "linear-dimensions"]))
        expectTrue(conflicts.allSatisfy { $0.productIDs.isEmpty }) // A weight upgrade cannot fix two pieces or oversized baggage.
        expectTrue(Baggage.conflicts(incoming: BaggageLimit(totalWeightKG: 8, dimensions: BagDimensions(20, 55, 40)), onward: BaggageLimit(totalWeightKG: 8, dimensions: BagDimensions(55, 40, 20))).isEmpty) // Rotation permitted.
    }
    @Test func testConnectionBaggageFixOnlyAppliesOnwardAndResolvesMismatch() throws {
        let (request, itinerary) = try fixture(.usConnection)
        let initial = Validation.review(request: request, itinerary: itinerary, selection: BookingSelection(), now: now)
        expectTrue(initial.contains { $0.id.hasPrefix("total-weight") })
        let rec = try requireValue(Pricing.recommend(itinerary: itinerary, passengers: request.passengers, selection: BookingSelection(), needs: TripNeeds()).first { $0.type == "connections" })
        expectEqual(rec.selection.extras.map(\.segmentID), ["us-pegasus"])
        expectEqual(rec.totalCents, 49000)
        expectFalse(Validation.review(request: request, itinerary: itinerary, selection: rec.selection, now: now).contains { $0.id.hasPrefix("total-weight") || $0.id.hasPrefix("piece-weight") })
    }
    @Test func testFamilyAdjacentSeatsAndChildEligibility() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        let segment = itinerary.segments[0]
        let suggested = try requireValue(Catalog.familySeats(passengers: request.passengers, segment: segment))
        expectTrue(Validation.seats(suggested, passengers: request.passengers, segments: [segment]).isEmpty)
        expectTrue(Validation.familyAdjacency(suggested, passengers: request.passengers, segment: segment).isEmpty)
        let invalid = [SeatSelection(passengerID: "child-1", segmentID: segment.id, seatID: "1A")]
        expectTrue(Validation.seats(invalid, passengers: request.passengers, segments: [segment]).contains { $0.id.hasPrefix("child-exit") })
        let acrossAisle = [SeatSelection(passengerID: "child-1", segmentID: segment.id, seatID: "4C"), SeatSelection(passengerID: "adult-1", segmentID: segment.id, seatID: "4D")]
        expectFalse(Validation.familyAdjacency(acrossAisle, passengers: request.passengers, segment: segment).isEmpty)
    }
    @Test func testOneAdultCanSitBetweenTwoChildren() throws {
        let (_, itinerary) = try fixture(.barcelonaFamily)
        let passengers = SearchRequest(adults: 1, children: 2).passengers
        let suggested = try requireValue(Catalog.familySeats(passengers: passengers, segment: itinerary.segments[0]))
        expectTrue(Validation.familyAdjacency(suggested, passengers: passengers, segment: itinerary.segments[0]).isEmpty)
    }
    @Test func testSeatCollisionAndUnavailableSeatRejected() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        let duplicate = [SeatSelection(passengerID: "adult-1", segmentID: "family-out", seatID: "4A"), SeatSelection(passengerID: "adult-2", segmentID: "family-out", seatID: "4A")]
        expectFalse(Validation.seats(duplicate, passengers: request.passengers, segments: itinerary.segments).isEmpty)
        expectFalse(Validation.seats([SeatSelection(passengerID: "adult-1", segmentID: "family-out", seatID: "2B")], passengers: request.passengers, segments: itinerary.segments).isEmpty)
    }
    @Test func testIncludedSeatUpgradeAndMealScope() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        var selection = BookingSelection(bundle: .family, seats: [SeatSelection(passengerID: "adult-1", segmentID: "family-out", seatID: "1A")])
        expectEqual(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: selection).extrasCents, 26700)
        selection.meals = [MealSelection(passengerID: "adult-1", segmentID: "family-out", productID: "peg-meal-child")]
        expectFalse(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: selection).isValid)
    }
    @Test func testSearchValidationAndOneWayPricing() throws {
        var request = Catalog.demoSearch(.barcelonaFamily, now: now)
        request.returnDate = nil
        let itinerary = try requireValue(Catalog.search(request, now: now).itineraries.first)
        expectEqual(itinerary.segments.count, 1)
        expectEqual(Pricing.quote(itinerary: itinerary, passengers: request.passengers, selection: BookingSelection()).totalCents, 24750)
        request.adults = 0
        expectTrue(Catalog.search(request, now: now).itineraries.isEmpty)
        request.adults = 1; request.returnDate = now
        expectTrue(Validation.search(request, now: now).contains { $0.id == "return-date" })
        request.returnDate = nil; request.origin = "XXX"
        expectEqual(Catalog.search(request, now: now).issues.first?.id, "unsupported-search")
    }
    @Test func testReconcilePreservesValidChoicesDropsRemovedPassengerAndFlight() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        var selected = BookingSelection(bundle: .family, extras: [ExtraSelection(passengerID: "adult-1", segmentID: "family-out", productID: "peg-cabin"), ExtraSelection(passengerID: "child-1", segmentID: "family-in", productID: "peg-checked20")])
        selected.seats = [SeatSelection(passengerID: "child-1", segmentID: "family-out", seatID: "4A")]
        let newPassengers = request.passengers.filter { !$0.isChild }
        var oneWay = itinerary; oneWay.segments = [itinerary.segments[0]]
        let result = Validation.reconcile(selected, passengers: newPassengers, itinerary: oneWay)
        expectEqual(result.bundle, .basic)
        expectEqual(result.extras.count, 1)
        expectTrue(result.seats.isEmpty)
    }
    @Test func testDraftCodableRoundTrip() throws {
        let (request, itinerary) = try fixture(.barcelonaFamily)
        let data = try JSONEncoder().encode(itinerary)
        expectEqual(try JSONDecoder().decode(Itinerary.self, from: data), itinerary)
        expectEqual(try JSONDecoder().decode(SearchRequest.self, from: JSONEncoder().encode(request)), request)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(actual == expected, sourceLocation: sourceLocation) }
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, sourceLocation: sourceLocation) }
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
private func requireValue<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T { try #require(value, sourceLocation: sourceLocation) }
