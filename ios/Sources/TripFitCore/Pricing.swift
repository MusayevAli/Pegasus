import Foundation

/// Integer-minor-unit pricing, shared contract with the Node catalogue. AI never calculates money.
public enum Pricing {
    public static func quote(itinerary: Itinerary, passengers: [Passenger], selection: BookingSelection) -> Quote {
        var issues: [ValidationIssue] = []
        var lines: [QuoteLine] = []
        if passengers.isEmpty || Set(passengers.map(\.id)).count != passengers.count { issues.append(ValidationIssue("quote-passengers", "A quote needs uniquely identified travellers.")) }
        if itinerary.currency != "EUR" { issues.append(ValidationIssue("quote-currency", "This demo catalogue only supports EUR.")) }
        let base = passengers.reduce(0) { $0 + ($1.isChild ? itinerary.basePricePerChildCents : itinerary.basePricePerAdultCents) }
        for passenger in passengers { lines.append(QuoteLine(id: "flight-\(passenger.id)", label: "Flights · \(passenger.displayName)", amountCents: passenger.isChild ? itinerary.basePricePerChildCents : itinerary.basePricePerAdultCents, passengerID: passenger.id)) }
        let pegasus = itinerary.segments.filter(\.isPegasus)
        if selection.bundle == .family && (!passengers.contains(where: \.isChild) || !passengers.contains(where: { !$0.isChild })) { issues.append(ValidationIssue("family-eligibility", "Together requires at least one adult and one child and applies to the full party on every Pegasus flight.", componentID: "fare.bundle")) }
        if selection.bundle != .basic {
            let unit = selection.bundle == .family ? 4200 : 6500
            lines.append(QuoteLine(id: "bundle-\(selection.bundle.rawValue)", label: "\(selection.bundle.title) · \(passengers.count) travellers × \(pegasus.count) Pegasus flights", amountCents: unit * passengers.count * pegasus.count))
        }
        var extraKeys = Set<String>()
        for extra in selection.extras {
            guard let passenger = passengers.first(where: { $0.id == extra.passengerID }), let segment = itinerary.segments.first(where: { $0.id == extra.segmentID }), segment.isPegasus, let product = Catalog.baggageProducts.first(where: { $0.id == extra.productID }) else { issues.append(ValidationIssue("extra-scope-\(extra.passengerID)-\(extra.segmentID)-\(extra.productID)", "Baggage product is unknown or unavailable for this traveller/airline/flight.", componentID: "baggage.selector")); continue }
            let key = "\(extra.passengerID)-\(extra.segmentID)-\(product.kind)"
            guard extraKeys.insert(key).inserted else { issues.append(ValidationIssue("duplicate-baggage-\(key)", "Choose only one \(product.kind) allowance per traveller and flight; allowances do not stack.", componentID: "baggage.selector")); continue }
            let amount = extraPrice(product: product, segment: segment, bundle: selection.bundle)
            lines.append(QuoteLine(id: "extra-\(key)", label: "\(product.name) · \(passenger.displayName) · \(segment.direction.title)\(amount == 0 ? " · included" : "")", amountCents: amount, passengerID: passenger.id, segmentID: segment.id))
        }
        issues += Validation.seats(selection.seats, passengers: passengers, segments: itinerary.segments)
        var seatKeys = Set<String>()
        for chosen in selection.seats {
            let key = "\(chosen.passengerID)-\(chosen.segmentID)"
            guard seatKeys.insert(key).inserted, let segment = itinerary.segments.first(where: { $0.id == chosen.segmentID }), let seat = Catalog.seats(for: segment).first(where: { $0.id == chosen.seatID }), let passenger = passengers.first(where: { $0.id == chosen.passengerID }) else { continue }
            let amount = max(0, seat.priceCents - (selection.bundle == .basic ? 0 : 1500))
            lines.append(QuoteLine(id: "seat-\(key)", label: "Seat \(seat.id) · \(passenger.displayName) · \(segment.direction.title)\(amount == 0 ? " · included" : "")", amountCents: amount, passengerID: passenger.id, segmentID: segment.id))
        }
        var mealKeys = Set<String>()
        for chosen in selection.meals {
            let key = "\(chosen.passengerID)-\(chosen.segmentID)"
            guard mealKeys.insert(key).inserted else { issues.append(ValidationIssue("duplicate-meal-\(key)", "Choose one meal or no meal per traveller and flight.", componentID: "meals.selector")); continue }
            guard let passenger = passengers.first(where: { $0.id == chosen.passengerID }), let segment = itinerary.segments.first(where: { $0.id == chosen.segmentID }), segment.isPegasus, let product = Catalog.mealProducts.first(where: { $0.id == chosen.productID }), !product.childOnly || passenger.isChild else { issues.append(ValidationIssue("meal-scope-\(key)", "Meal is unknown or unavailable for this traveller/airline/flight.", componentID: "meals.selector")); continue }
            let amount = selection.bundle == .basic ? product.priceCents : 0
            lines.append(QuoteLine(id: "meal-\(key)", label: "\(product.name) · \(passenger.displayName) · \(segment.direction.title)\(amount == 0 ? " · included" : "")", amountCents: amount, passengerID: passenger.id, segmentID: segment.id))
        }
        let total = lines.reduce(0) { $0 + $1.amountCents }
        return Quote(totalCents: total, baseCents: base, extrasCents: total - base, currency: itinerary.currency, lines: lines, issues: issues)
    }
    public static func extraPrice(product: BaggageProduct, segment: Segment, bundle: FareBundle) -> Int {
        guard segment.isPegasus else { return 0 }
        let baseAllowance = Baggage.allowance(passengerID: "pricing", segment: segment, selection: BookingSelection(bundle: bundle))
        if product.kind == "cabin" { return (baseAllowance.cabin?.totalWeightKG ?? 0) >= product.allowance.totalWeightKG ? 0 : product.priceCents }
        let included = baseAllowance.checked?.totalWeightKG ?? 0
        if included >= product.allowance.totalWeightKG { return 0 }
        if included >= 20 && product.id == "peg-checked25" { return 1000 }
        return product.priceCents
    }
    public static func recommend(itinerary: Itinerary, passengers: [Passenger], selection: BookingSelection, needs: TripNeeds) -> [Recommendation] {
        let current = quote(itinerary: itinerary, passengers: passengers, selection: selection)
        var result: [Recommendation] = []
        let pegasus = itinerary.segments.filter(\.isPegasus)
        var desired = selection
        let bagEverywhere = needs.packingItems.contains("checked-bag-each-way")
        let allMeals = needs.packingItems.contains("meals-each-flight")
        for segment in pegasus {
            // Explicitly configured demo requirements. An ordinary gifts preference needs one adult return bag.
            let bagPassengers = bagEverywhere ? passengers : (needs.giftsOnReturn && segment.direction == .inbound ? Array(passengers.filter { !$0.isChild }.prefix(1)) : [])
            for passenger in bagPassengers {
                let productID = needs.giftsOnReturn && segment.direction == .inbound ? "peg-checked25" : "peg-checked20"
                if productID == "peg-checked25", let index = desired.extras.firstIndex(where: { $0.passengerID == passenger.id && $0.segmentID == segment.id && $0.productID == "peg-checked20" }) {
                    desired.extras[index].productID = productID // Proposal only; manual selections remain unchanged until Apply.
                }
                if !desired.extras.contains(where: { $0.passengerID == passenger.id && $0.segmentID == segment.id && $0.productID.hasPrefix("peg-checked") }) {
                    desired.extras.append(ExtraSelection(passengerID: passenger.id, segmentID: segment.id, productID: productID))
                }
            }
            if needs.stayTogether, let family = Catalog.familySeats(passengers: passengers, segment: segment, existing: desired.seats), !desired.seats.contains(where: { $0.segmentID == segment.id }) {
                desired.seats += family
            }
            for passenger in passengers where allMeals || (passenger.isChild && needs.childMeals) {
                if !desired.meals.contains(where: { $0.passengerID == passenger.id && $0.segmentID == segment.id }) {
                    desired.meals.append(MealSelection(passengerID: passenger.id, segmentID: segment.id, productID: passenger.isChild ? "peg-meal-child" : "peg-meal-veggie"))
                }
            }
        }
        var individually = desired; individually.bundle = .basic
        let individualQuote = quote(itinerary: itinerary, passengers: passengers, selection: individually)
        let eligibleBundles = passengers.contains(where: \.isChild) && passengers.contains(where: { !$0.isChild }) ? FareBundle.allCases : [.basic, .flex]
        let candidates: [(BookingSelection, Quote)] = eligibleBundles.map { bundle in var proposed = desired; proposed.bundle = bundle; return (proposed, quote(itinerary: itinerary, passengers: passengers, selection: proposed)) }.filter { $0.1.isValid }
        if let cheapest = candidates.min(by: { $0.1.totalCents < $1.1.totalCents }), desired != selection || cheapest.0.bundle != selection.bundle {
            let saving = max(0, individualQuote.totalCents - cheapest.1.totalCents)
            let explanation = cheapest.0.bundle == .family ? "For your confirmed bags, meals and seats, Together covers the entire party on every Pegasus flight. Save \(Money.format(saving)) versus these same choices individually. Return 25 kg upgrades remain separately itemised." : "The lowest available price for your confirmed needs and existing choices. Purchases remain assigned to individual travellers and flights."
            result.append(Recommendation(id: "fit-\(itinerary.id)-\(cheapest.0.bundle.rawValue)", type: cheapest.0.bundle == .basic ? "baggage" : "bundles", title: cheapest.0.bundle == .family ? "Together costs less" : "Fit your trip, keep your choices", explanation: explanation, selection: cheapest.0, totalCents: cheapest.1.totalCents, savingsCents: saving))
        }
        if needs.travellingLight && !bagEverywhere && !needs.giftsOnReturn && !needs.packingItems.contains("checked-bag") {
            var light = selection; light.bundle = .basic; light.extras = light.extras.filter { !Catalog.baggageProducts.map(\.id).contains($0.productID) }
            let lightQuote = quote(itinerary: itinerary, passengers: passengers, selection: light)
            if lightQuote.isValid && lightQuote.totalCents <= current.totalCents {
                result.insert(Recommendation(id: "keep-allowance-\(itinerary.id)", type: "baggage", title: lightQuote.totalCents < current.totalCents ? "Travel light. Spend less." : "Your included bag is enough", explanation: "If your confirmed items fit the included 3 kg, 40 × 30 × 15 cm underseat allowance, keep it. \(lightQuote.totalCents < current.totalCents ? "Remove unneeded baggage and save \(Money.format(current.totalCents - lightQuote.totalCents))." : "No baggage purchase is needed.") Seats and meals remain unchanged. A photo cannot establish weight or dimensions.", selection: light, totalCents: lightQuote.totalCents, savingsCents: current.totalCents - lightQuote.totalCents), at: 0)
            }
        }
        if itinerary.transferKind == .selfTransfer {
            var upgraded = selection
            for pair in zip(itinerary.segments, itinerary.segments.dropFirst()) where pair.0.direction == pair.1.direction && pair.1.isPegasus {
                for passenger in passengers {
                    if let incoming = Baggage.allowance(passengerID: passenger.id, segment: pair.0, selection: selection).checked {
                        let conflicts = Baggage.conflicts(incoming: incoming, onward: Baggage.allowance(passengerID: passenger.id, segment: pair.1, selection: selection).checked)
                        if !conflicts.isEmpty && conflicts.allSatisfy({ $0.productIDs.contains("peg-checked25") }) {
                            upgraded.extras.removeAll { $0.passengerID == passenger.id && $0.segmentID == pair.1.id && $0.productID.hasPrefix("peg-checked") }
                            upgraded.extras.append(ExtraSelection(passengerID: passenger.id, segmentID: pair.1.id, productID: "peg-checked25"))
                        }
                    }
                }
            }
            if upgraded != selection {
                let upgradeQuote = quote(itinerary: itinerary, passengers: passengers, selection: upgraded)
                result.append(Recommendation(id: "connection-baggage-\(itinerary.id)", type: "connections", title: "23 kg in. 20 kg onward.", explanation: "The incoming allowance is larger. Choose a 25 kg allowance on Pegasus for \(Money.format(upgradeQuote.totalCents - current.totalCents)) more, or keep your actual bag within 20 kg. The purchase only applies to the Pegasus flight.", selection: upgraded, totalCents: upgradeQuote.totalCents))
            }
        }
        if let flexible = candidates.first(where: { $0.0.bundle == .flex }), selection.bundle != .flex {
            result.append(Recommendation(id: "flex-\(itinerary.id)", type: "bundles", title: "Room for plans to change", explanation: "More flexibility includes 25 kg, standard seats and one meal on every Pegasus flight. Demo change fee waived; fare difference still payable. External-airline fare conditions stay unchanged.", selection: flexible.0, totalCents: flexible.1.totalCents))
        }
        return result
    }
}
