import SwiftUI
import TripFitCore

struct BookingConfigurationScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @State private var peopleOpen = true
    @State private var bagsOpen = false
    @State private var seatsOpen = false
    @State private var mealsOpen = false
    @State private var faresOpen = false
    @State private var packingOpen = false
    @State private var passengerID = ""
    @State private var segmentID = ""
    var body: some View {
        if let offer = booking.selectedOffer, !offer.effectiveCapabilities.quote {
            LiveFlightDetailsScreen(offer: offer)
        } else { sampleConfiguration }
    }
    private var sampleConfiguration: some View {
        @Bindable var booking = booking
        return VStack(alignment: .leading, spacing: 23) {
            Text("Make it yours.").font(.largeTitle.bold()).tracking(-1)
            if let offer = booking.selectedOffer {
                Panel { FlightOfferFacts(offer: offer, quotedTotal: booking.quote?.total, quotedBaggage: baggageSummary, needsQuote: booking.quote == nil); InventorySourceLine() }
            }
            if booking.busy { HStack { ProgressView(); Text(booking.busyMessage).font(.subheadline) } }
            section("Travellers", summary: "\(booking.passengers.count) \(booking.passengers.count == 1 ? "person" : "people") · guest booking", symbol: "person.2", open: $peopleOpen) {
                ForEach(booking.passengers.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(passengerLabel(booking.passengers[index])).font(.subheadline.bold())
                        TextField("First name", text: $booking.passengers[index].givenName).textContentType(.givenName).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                        TextField("Last name", text: $booking.passengers[index].familyName).textContentType(.familyName).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            section("Bags", summary: baggageSummary, symbol: "suitcase.rolling", open: $bagsOpen) {
                Button { packingOpen = true } label: {
                    HStack(spacing: 14) { Image(systemName: "camera").font(.title2).frame(width: 48, height: 48).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 14)); VStack(alignment: .leading, spacing: 5) { Text("Show what you're packing").font(.headline); Text("Photo → item list → bag options").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                }.buttonStyle(.plain).padding(.vertical, 7)
                scopePickers
                if let allowance = currentSegment?.underseat {
                    Text("Included underseat: \(allowance.weightKg) kg · \(allowance.dimensionsCm.map(String.init).joined(separator: " × ")) cm").font(.caption).foregroundStyle(.secondary)
                }
                let productList = booking.services.filter { ["cabin", "checked"].contains($0.type) && $0.eligibleSegmentIds.contains(activeSegmentID) }
                ForEach(productList) { product in
                    let selected = booking.selection.bags.contains { $0.passengerId == activePassengerID && $0.segmentId == activeSegmentID && $0.productId == product.id }
                    Button { Task { await booking.setBag(selected ? nil : product.id, passengerId: activePassengerID, segmentId: activeSegmentID, kind: product.type) } } label: {
                        HStack { Image(systemName: selected ? "checkmark.circle.fill" : "circle"); Text(product.name).font(.subheadline); Spacer(); Text(productSurcharge(product) == 0 ? "Included" : V2Money(amountMinor: productSurcharge(product)).formatted).font(.caption.bold()) }.padding(.vertical, 10)
                    }.buttonStyle(.plain).disabled(booking.busy)
                }
                Text("Prices are per selected traveller and flight, after bundle inclusions. Choosing another bag of the same kind replaces the previous choice. Allowances cannot be pooled.").font(.caption).foregroundStyle(.secondary)
                if booking.canUndoPacking { Button("Undo packing change") { Task { await booking.undoPackingOption() } }.font(.subheadline.bold()) }
            }
            section("Seats", summary: booking.selection.seats.isEmpty ? "Choose a place, or leave unassigned" : "\(booking.selection.seats.count) seat choices", symbol: "chair", open: $seatsOpen) {
                scopePickers
                if let map = booking.seatMaps.first(where: { $0.segmentId == activeSegmentID }) {
                    if map.familyAvailable && booking.passengers.count > 1 && map.suggestedFamilySeats.count >= booking.passengers.count {
                        Button { Task { await booking.applyFamilySeats(segmentId: activeSegmentID) } } label: { Label("Sit together · \(map.suggestedFamilySeats.joined(separator: ", "))", systemImage: "person.2.fill").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered).disabled(booking.busy)
                    }
                    Text("Front of aircraft").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    ForEach(Array(Set(map.seats.map(\.row))).sorted(), id: \.self) { row in
                        HStack(spacing: 7) {
                            ForEach(map.seats.filter { $0.row == row }.sorted { $0.column < $1.column }) { seat in
                                seatButton(seat)
                                if seat.column == "C" { Text(String(row)).font(.caption2).foregroundStyle(.secondary).frame(width: 14) }
                            }
                        }
                    }
                    HStack(spacing: 15) { Label("Available", systemImage: "square"); Label("Selected", systemImage: "checkmark.square.fill"); Label("Taken", systemImage: "xmark.square.fill") }.font(.caption2).foregroundStyle(.secondary)
                    Button("Leave this seat unassigned") { Task { await booking.setSeat(nil, passengerId: activePassengerID, segmentId: activeSegmentID) } }.font(.subheadline).frame(minHeight: 44)
                    Text("An arrangement is a selection, not a reservation. Children cannot use exit seats.").font(.caption).foregroundStyle(.secondary)
                }
            }
            section("Meals", summary: booking.selection.meals.isEmpty ? "Optional, just as you like" : "\(booking.selection.meals.count) meal choices", symbol: "fork.knife", open: $mealsOpen) {
                scopePickers
                Button("No meal for this flight") { Task { await booking.setMeal(nil, passengerId: activePassengerID, segmentId: activeSegmentID) } }.frame(minHeight: 44)
                ForEach(eligibleMeals) { product in
                    let selected = booking.selection.meals.contains { $0.passengerId == activePassengerID && $0.segmentId == activeSegmentID && $0.productId == product.id }
                    Button { Task { await booking.setMeal(product.id, passengerId: activePassengerID, segmentId: activeSegmentID) } } label: {
                        HStack(alignment: .top) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").padding(.top, 3)
                            VStack(alignment: .leading, spacing: 5) { Text(product.name).font(.subheadline.bold()); Text(product.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(currentBundle?.mealIncluded == true ? "Included" : V2Money(amountMinor: product.priceMinor).formatted).font(.caption.bold())
                        }.padding(.vertical, 10)
                    }.buttonStyle(.plain).disabled(booking.busy)
                }
                Text("Dietary tags describe the sample menu. Confirm allergens with the carrier.").font(.caption).foregroundStyle(.secondary)
            }
            section("Fare bundle", summary: currentBundle?.name ?? "Choose a bundle", symbol: "square.stack.3d.up", open: $faresOpen) {
                Text("The quoted fare starts with the cheapest eligible combination for your requested needs.").font(.caption).foregroundStyle(.secondary)
                ForEach(booking.bundles) { bundle in
                    Button { Task { await booking.setBundle(bundle.id) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Image(systemName: booking.selection.bundleId == bundle.id ? "checkmark.circle.fill" : "circle"); Text(bundle.name).font(.headline); Spacer() }
                            Text(bundle.conditions).font(.caption).foregroundStyle(.secondary)
                            Text("Bundle supplement: \(V2Money(amountMinor: bundle.pricePerPassengerSegmentMinor).formatted) per traveller / flight").font(.caption)
                        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }.buttonStyle(.plain).disabled(booking.busy)
                }
            }
            if let itinerary = booking.selectedOffer?.itinerary, itinerary.transferType != "direct" { ConnectionSummary(itinerary: itinerary) }
        }.sheet(isPresented: $packingOpen) { BookingPackingScreen() }
    }
    private var activePassengerID: String { booking.passengers.contains { $0.id == passengerID } ? passengerID : booking.passengers.first?.id ?? "" }
    private var activeSegmentID: String { bookableSegments.contains { $0.id == segmentID } ? segmentID : bookableSegments.first?.id ?? "" }
    private var bookableSegments: [V2FlightSegment] { booking.selectedOffer?.itinerary.segments.filter { !$0.independentlyBooked } ?? [] }
    private var currentSegment: V2FlightSegment? { bookableSegments.first { $0.id == activeSegmentID } }
    private var currentBundle: V2FareBundle? { booking.bundles.first { $0.id == booking.selection.bundleId } }
    private var currentPassenger: V2Passenger? { booking.passengers.first { $0.id == activePassengerID } }
    private var baggageSummary: String { booking.selection.bags.isEmpty ? (currentBundle?.checkedPieces ?? 0) > 0 ? "Checked allowance included" : "Included underseat allowance" : "\(booking.selection.bags.count) bag choices across your flights" }
    private var eligibleMeals: [V2AncillaryProduct] { booking.services.filter { product in product.type == "meal" && product.eligibleSegmentIds.contains(activeSegmentID) && (!product.childOnly || currentPassenger?.type == "child") && (!booking.intent.vegetarian || product.tags.contains(where: { $0.lowercased() == "vegetarian" })) && (!(booking.intent.noAlcohol || currentPassenger?.type == "child") || !product.tags.contains(where: { $0.lowercased() == "alcohol" })) } }
    // Matches the current sample catalogue's surcharges in backend/src/v2/engine.ts.
    // The authoritative total is still obtained from a new backend quote after selection.
    private func productSurcharge(_ product: V2AncillaryProduct) -> Int {
        if product.type == "cabin", currentBundle?.cabinIncluded == true { return 0 }
        if product.type == "checked", let bundle = currentBundle {
            if bundle.checkedWeightKg >= (product.weightKg ?? 0) { return 0 }
            if bundle.checkedWeightKg == 20, product.weightKg == 25 { return 900 }
        }
        return product.priceMinor
    }
    private func seatSurcharge(_ seat: V2Seat) -> Int { max(0, seat.priceMinor - (currentBundle?.standardSeatIncluded == true ? 1400 : 0)) }
    private var scopePickers: some View {
        VStack(spacing: 8) {
            Picker("Traveller", selection: Binding(get: { activePassengerID }, set: { passengerID = $0 })) { ForEach(booking.passengers) { Text(passengerLabel($0)).tag($0.id) } }
            Picker("Flight", selection: Binding(get: { activeSegmentID }, set: { segmentID = $0 })) { ForEach(bookableSegments) { Text("\($0.direction == "return" ? "Return" : "Outbound") · \($0.routeLabel)").tag($0.id) } }
        }.font(.subheadline).tint(TripTheme.ink)
    }
    private func seatButton(_ seat: V2Seat) -> some View {
        let selected = booking.selection.seats.contains { $0.passengerId == activePassengerID && $0.segmentId == activeSegmentID && $0.seatId == seat.id }
        let occupied = booking.selection.seats.contains { $0.passengerId != activePassengerID && $0.segmentId == activeSegmentID && $0.seatId == seat.id }
        let allowed = seat.available && !occupied && (currentPassenger?.type != "child" || seat.childAllowed)
        let surcharge = seatSurcharge(seat)
        let priceLabel = surcharge == 0 ? "Included" : V2Money(amountMinor: surcharge).formatted
        return Button { Task { await booking.setSeat(selected ? nil : seat.id, passengerId: activePassengerID, segmentId: activeSegmentID) } } label: {
            VStack(spacing: 4) {
                Text(seat.id).font(.caption2.weight(.semibold))
                Text(allowed || selected ? (surcharge == 0 ? "Incl." : priceLabel) : "—").font(.caption2).minimumScaleFactor(0.75).lineLimit(1)
            }.frame(maxWidth: .infinity, minHeight: 54).background(selected ? TripTheme.yellow : allowed ? .white : Color.gray.opacity(0.13), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(allowed || selected ? TripTheme.ink : .secondary)
        }.buttonStyle(.plain).disabled(!allowed || booking.busy)
            .accessibilityLabel("Seat \(seat.id), \(allowed ? priceLabel + " for this traveller and flight" : "unavailable")\(selected ? ", selected" : "")")

    }
    private func section<Content: View>(_ title: String, summary: String, symbol: String, open: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(isExpanded: open) { VStack(alignment: .leading, spacing: 16, content: content).padding(.top, 20) } label: {
            HStack(spacing: 13) { Image(systemName: symbol).font(.title3).frame(width: 28); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(summary).font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 4)
        }.tint(TripTheme.ink).padding(18).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 21))
    }
}

struct BookingPinnedTotal: View {
    @Environment(BookingV2Store.self) private var booking
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(booking.quote?.total.formatted ?? "Update price").font(.title2.bold()).contentTransition(.numericText())
                Text(booking.quote?.priceScope == "onward_party" ? "Onward only · whole party" : "Whole party · sample fare").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if booking.stage == .configuration {
                Button { Task { if booking.quote == nil { await booking.requote() } else { await booking.review() } } } label: { Text(booking.busy ? "Updating…" : booking.quote == nil ? "Retry quote" : "Review trip").frame(minWidth: 110) }.buttonStyle(PrimaryButtonStyle()).disabled(booking.busy)
            } else {
                Text("No charge in demo").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 22).padding(.vertical, 14).background(.white).overlay(alignment: .top) { Divider() }
    }
}

struct BookingReviewScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @State private var acknowledged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Everything in place.").font(.largeTitle.bold()).tracking(-1)
            if let quote = booking.quote, let offer = booking.selectedOffer {
                Panel { ForEach(offer.itinerary.segments) { segment in FlightSegmentRow(segment: segment); if segment.independentlyBooked { Text("Already booked · not charged again").font(.caption.bold()) } }; InventorySourceLine() }
                Panel {
                    HStack { Text("Travellers & choices").font(.headline); Spacer(); Button("Edit") { booking.stage = .configuration }.font(.subheadline.bold()) }
                    ForEach(booking.passengers) { passenger in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(passenger.fullName).font(.subheadline.bold())
                            ForEach(offer.itinerary.segments.filter { !$0.independentlyBooked }) { segment in
                                Text("\(segment.routeLabel): \(selectionSummary(passenger: passenger.id, segment: segment.id))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Panel {
                    Text("Your total, itemised.").font(.title3.bold())
                    ForEach(quote.items) { item in HStack(alignment: .top) { Text(item.label).font(.subheadline); Spacer(minLength: 12); Text(V2Money(amountMinor: item.amountMinor, currency: quote.total.currency).formatted).font(.subheadline).fixedSize() } }
                    Divider()
                    HStack { Text(quote.priceScope == "onward_party" ? "Onward total" : "Party total").bold(); Spacer(); Text(quote.total.formatted).font(.title2.bold()) }
                    Text("Sample inventory · quote valid until \(V2Dates.local(quote.expiresAt, zone: TimeZone.current.identifier))").font(.caption).foregroundStyle(.secondary)
                }
                if let bundle = booking.bundles.first(where: { $0.id == quote.selection.bundleId }) { Text("\(bundle.name) · \(bundle.conditions)").font(.caption).foregroundStyle(.secondary) }
                if booking.priceChanged { InfoNote(text: "The price changed. Review the updated total before continuing.", symbol: "arrow.clockwise") }
                if quote.isExpired && !booking.hasPendingCheckout { Button("Refresh expired price") { Task { await booking.review() } }.buttonStyle(PrimaryButtonStyle()) }
                if booking.hasPendingCheckout { InfoNote(text: "The previous demo booking result was not received. Retry the same attempt to recover its status; this does not create a second booking.", symbol: "arrow.clockwise") }
                Toggle("I've reviewed the trip and total", isOn: $acknowledged).font(.subheadline).tint(TripTheme.ink)
                Button { Task { await booking.checkoutDemo() } } label: {
                    HStack { if booking.checkoutBusy { ProgressView() }; Text(booking.checkoutBusy ? "Saving your booking…" : booking.hasPendingCheckout ? "Retry existing demo booking" : "Complete demo booking") }
                }.buttonStyle(PrimaryButtonStyle()).disabled(!acknowledged || booking.busy || booking.checkoutBusy || (quote.isExpired && !booking.hasPendingCheckout))
                Text("No payment is taken. No ticket is issued.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Button(booking.hasPendingCheckout ? "Back to trip" : "Cancel checkout") { if !booking.hasPendingCheckout { booking.analytics.emit("checkout_cancelled", "checkout.cancel") }; booking.stage = .configuration }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ContentUnavailableView("Price needs updating", systemImage: "arrow.clockwise", description: Text("Refresh your quote before booking."))
                Button("Refresh price") { Task { await booking.review() } }.buttonStyle(PrimaryButtonStyle())
            }
        }.onChange(of: booking.quote?.total.amountMinor) { _, _ in acknowledged = false }
    }
    private func selectionSummary(passenger: String, segment: String) -> String {
        let products = booking.selection.bags.filter { $0.passengerId == passenger && $0.segmentId == segment }.compactMap { bag in booking.services.first { $0.id == bag.productId }?.name }
        let seat = booking.selection.seats.first { $0.passengerId == passenger && $0.segmentId == segment }?.seatId
        let meal = booking.selection.meals.first { $0.passengerId == passenger && $0.segmentId == segment }.flatMap { selected in booking.services.first { $0.id == selected.productId }?.name }
        return (products.isEmpty ? ["Included bags"] : products).joined(separator: ", ") + " · Seat \(seat ?? "unassigned") · \(meal ?? "No meal")"
    }
}

struct BookingConfirmationScreen: View {
    @Environment(BookingV2Store.self) private var booking
    var body: some View {
        if let order = booking.completedOrder {
            VStack(alignment: .leading, spacing: 23) {
                Image(systemName: "checkmark").font(.system(size: 30, weight: .semibold)).frame(width: 76, height: 76).background(TripTheme.yellow, in: Circle())
                Text("Trip saved.").font(.largeTitle.bold()).tracking(-1)
                Text("Demo booking — no ticket issued").font(.headline)
                OrderDetailContent(order: order)
                Button("View My Trips") { booking.stage = .trips }.buttonStyle(PrimaryButtonStyle())
                Button("Find another flight") { booking.reset() }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

struct BookingSavedTripsScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @Environment(BookingStore.self) private var legacy
    @State private var selected: V2Order?
    @State private var legacyTrips = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("My Trips.").font(.largeTitle.bold()).tracking(-1)
            if booking.orders.isEmpty { ContentUnavailableView("Your next trip starts here", systemImage: "suitcase.rolling", description: Text("Completed demo bookings are saved on this iPhone.")) }
            ForEach(booking.orders.filter { $0.state == "confirmed_demo" }) { order in
                Button { selected = order } label: { Panel {
                    HStack { Text(order.itinerary.routeLabel).font(.title2.bold()); Spacer(); Text(order.total.formatted).font(.headline) }
                    Text(order.itinerary.segments.first?.departureText ?? "").font(.subheadline)
                    HStack { Text(order.reference).font(.system(.caption, design: .monospaced)); Spacer(); Image(systemName: "arrow.up.right") }
                    Text("Demo · no ticket issued").font(.caption).foregroundStyle(.secondary)
                } }.buttonStyle(.plain)
            }
            if !legacy.trips.isEmpty { Button("Earlier saved demo trips (\(legacy.trips.count))") { legacyTrips = true }.font(.subheadline).frame(minHeight: 44) }
        }.sheet(item: $selected) { order in NavigationStack { ScrollView { OrderDetailContent(order: order).padding(24) }.navigationTitle("Trip details").tripInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } } } } }
            .sheet(isPresented: $legacyTrips) { NavigationStack { ScrollView { TripsScreen().padding(24) }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { legacyTrips = false } } } } }
    }
}

struct OrderDetailContent: View {
    var order: V2Order
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Panel {
                Text(order.reference).font(.system(.title3, design: .monospaced, weight: .bold))
                HStack { Text("Simulated total"); Spacer(); Text(order.total.formatted).bold() }
                ForEach(order.travellerNames, id: \.self) { Text($0).font(.subheadline) }
                Text("Sample inventory · no charge · no ticket issued").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(order.itinerary.segments) { segment in
                Panel {
                    FlightSegmentRow(segment: segment)
                    if segment.independentlyBooked { Text("Independently booked incoming flight · excluded from total").font(.caption.bold()) }
                    ForEach(Array(order.selection.seats.filter { $0.segmentId == segment.id }.enumerated()), id: \.offset) { _, seat in Text("\(seat.passengerId) · seat \(seat.seatId)").font(.caption) }
                }
            }
            if order.itinerary.transferType != "direct" { ConnectionSummary(itinerary: order.itinerary) }
        }
    }
}

struct ConnectionSummary: View {
    var itinerary: V2Itinerary
    var body: some View {
        Panel {
            Label(itinerary.transferType == "independent_incoming" ? "Your onward connection" : "Connection details", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
            ForEach(Array(itinerary.transferSteps.enumerated()), id: \.offset) { _, step in Text(step).font(.subheadline) }
            Text(itinerary.terms).font(.caption).foregroundStyle(.secondary)
            Text("Entry / transit requirements have not been checked.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FlightComparisonScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 22) {
                Text("Which fits your trip?").font(.largeTitle.bold()).tracking(-1)
                if let comparison = booking.comparison {
                    if let explanation = comparison.explanation { Text(explanation).font(.title3).fixedSize(horizontal: false, vertical: true) }
                    Text(comparison.offers.contains { $0.source == "live" } ? "Same travellers · flight fares only" : "Same travellers and requested extras").font(.caption).foregroundStyle(.secondary)
                    Text(comparison.notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(comparison.differences) { row in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(row.label).font(.caption.bold()).foregroundStyle(.secondary)
                            HStack(alignment: .top, spacing: 18) { ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in Text(value).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading) } }
                        }.padding(.vertical, 8)
                        Divider()
                    }
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(comparison.offers.enumerated()), id: \.element.id) { index, offer in
                            VStack(alignment: .leading, spacing: 12) { Text("Option \(index + 1)").font(.headline); Text(offer.totalPrice.formatted).font(.title3.bold()); Button("Choose") { Task { await booking.select(offer); dismiss() } }.buttonStyle(PrimaryButtonStyle()) }.frame(maxWidth: .infinity)
                        }
                    }
                    if comparison.explanationSource != "openai" { Text("AI explanation unavailable. The factual comparison is ready.").font(.caption).foregroundStyle(.secondary) }
                } else if booking.busy { ProgressView("Comparing your flights…").frame(maxWidth: .infinity).padding(30) }
                else { Text(booking.error ?? "Select two current flight offers to compare.").font(.subheadline) }
            }.padding(24) }.navigationTitle("Compare flights").tripInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct BookingPreferencesScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @Environment(BookingStore.self) private var legacy
    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics = false
    var body: some View {
        @Bindable var analytics = legacy.analytics
        NavigationStack {
            Form {
                Section("Privacy") {
                    Toggle("Share anonymous demo interactions", isOn: $analytics.enabled)
                    Text("Optional. Includes screens, choices and active time. Excludes names, typed trip descriptions, photos and payment information.").font(.caption)
                    if analytics.enabled { Button("Sync interactions") { Task { await analytics.flush() } }; Text(analytics.status).font(.caption) }
                }
                Section("Booking") {
                    Button("Start a new search") { booking.reset(); dismiss() }
                    Text("Live Pegasus flight search opens official Pegasus booking. Demo booking uses labelled sample inventory and issues no ticket.").font(.caption)
                }
                Section {
                    DisclosureGroup("Developer diagnostics", isExpanded: $diagnostics) {
                        TextField("Backend URL", text: $analytics.baseURL).tripURLInput()
                        SecureField("App access token", text: $analytics.uploadToken)
                        Button("Refresh capabilities") { Task { await booking.initialize() } }
                        if let c = booking.capabilities {
                            LabeledContent("AI", value: c.liveAI ? "Configured · \(c.textModel)" : "Unavailable")
                            LabeledContent("Inventory", value: c.inventory)
                            LabeledContent("Payments", value: c.payments)
                            LabeledContent("Fulfilment", value: c.fulfilment)
                            Text("\(c.offerCount) sample offers · \(c.routePairs) route pairs").font(.caption)
                            Text("Sample window \(c.sampleWindow.start) to \(c.sampleWindow.end)").font(.caption)
                        }
                        if let request = booking.lastAIRequestId { Text("Last validated model request: \(request)").font(.caption).textSelection(.enabled) }
                        Text("Merchant, processor and authorised airline access are required for Apple Pay and ticket issuance. Setup instructions are in the project README.").font(.caption)
                    }
                }
            }.navigationTitle("Preferences").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

func passengerLabel(_ passenger: V2Passenger) -> String {
    let name = passenger.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? passenger.id.replacingOccurrences(of: "-", with: " ").capitalized + (passenger.type == "child" ? " · age \(passenger.age.map(String.init) ?? "?")" : "") : name
}
