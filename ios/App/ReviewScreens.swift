import SwiftUI
import TripFitCore

struct ReviewScreen: View {
    @Environment(BookingStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let itinerary = store.itinerary {
                Panel {
                    editTitle("Your journey", step: .itinerary)
                    ForEach(itinerary.segments) { SegmentSummary(segment: $0) }
                    if itinerary.transferKind != .direct { DisclosureGroup("Your self-transfer timeline") { ConnectionTimeline(itinerary: itinerary) } }
                }
                Panel {
                    editTitle("Your travellers", step: .search)
                    ForEach(store.passengers) { p in Label("\(p.displayName) · \(p.isChild ? "Child, demo age 8" : "Adult")", systemImage: p.isChild ? "figure.child" : "person").font(.subheadline) }
                    InfoNote(text: "Guest demo booking. Personal details and documents are not required for a simulated ticket. Live ticketing needs provider-validated traveller details.")
                }
                Panel {
                    editTitle("Baggage", step: .baggage)
                    ForEach(itinerary.segments) { segment in
                        Text("\(segment.direction.title) · \(segment.origin)–\(segment.destination) · \(segment.carrier)").font(.subheadline.bold())
                        ForEach(store.passengers) { p in Text("\(p.displayName): \(Baggage.allowance(passengerID: p.id, segment: segment, selection: store.selection).summary)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Panel {
                    editTitle("Seats", step: .seats)
                    ForEach(itinerary.segments) { segment in
                        Text("\(segment.origin)–\(segment.destination)").font(.subheadline.bold())
                        ForEach(store.passengers) { p in Text("\(p.displayName): \(store.selection.seats.first { $0.passengerID == p.id && $0.segmentID == segment.id }?.seatID ?? "Not selected")").font(.caption) }
                    }
                    InfoNote(text: "Unselected seats are not promised to be adjacent.")
                }
                Panel {
                    editTitle("Meals", step: .meals)
                    ForEach(itinerary.segments.filter(\.isPegasus)) { segment in
                        Text("\(segment.origin)–\(segment.destination)").font(.subheadline.bold())
                        ForEach(store.passengers) { p in Text("\(p.displayName): \(mealName(p.id, segment.id))").font(.caption) }
                    }
                }
                Panel { editTitle("Fare conditions", step: .configuration); Text(store.selection.bundle.title).font(.headline); Text(bundleDescription(store.selection.bundle)).font(.subheadline); Text(itinerary.fareConditions).font(.caption).foregroundStyle(.secondary) }
                let issues = Validation.review(request: store.request, itinerary: itinerary, selection: store.selection)
                if !issues.isEmpty { Panel {
                    Text("Before you go").font(.headline)
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(issue.severity == .error ? "Needs a fix" : "Optional check", systemImage: issue.severity == .error ? "exclamationmark.circle.fill" : "info.circle").font(.caption.bold())
                            Text(issue.message).font(.subheadline)
                        }.onAppear { if issue.severity == .error { store.analytics.emit("validation_error", "review.check", ["code": .string(issue.id)]) } }
                    }
                } }
                if let quote = store.quote { PriceBreakdown(quote: quote) }
            }
        }
    }
    func editTitle(_ title: String, step: BookingStep) -> some View { HStack { Text(title).font(.title3.bold()); Spacer(); Button("Edit") { store.navigate(step, back: true) }.font(.subheadline.bold()).frame(minHeight: 44) } }
    func mealName(_ passengerID: String, _ segmentID: String) -> String {
        let id = store.selection.meals.first { $0.passengerID == passengerID && $0.segmentID == segmentID }?.productID
        return Catalog.mealProducts.first { $0.id == id }?.name ?? "No meal selected"
    }
}
struct PriceBreakdown: View {
    var quote: Quote
    var body: some View { Panel {
        Text("Your total, explained.").font(.title3.bold())
        ForEach(quote.lines) { line in HStack(alignment: .top) { Text(line.label).font(.subheadline); Spacer(); Text(euros(line.amountCents)).font(.subheadline).fixedSize() }.accessibilityElement(children: .combine) }
        Divider()
        HStack { Text("Total · EUR").font(.headline); Spacer(); Text(euros(quote.totalCents)).font(.title2.bold()) }
        InfoNote(text: "Illustrative price for the complete party. Included items are charged once. No currency conversion.")
    } }
}

struct CheckoutScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var payment = ApplePayCoordinator()
    @State private var checked = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let quote = store.quote { PriceBreakdown(quote: quote) }
            Panel(selected: true) {
                Label("This is a demo booking", systemImage: "testtube.2").font(.headline)
                Text("No charge will occur. No real ticket will be issued. Your completed trip will be saved on this device with a DEMO reference.").font(.subheadline)
                Toggle("I've reviewed my journey and choices", isOn: $checked)
            }
            Button { Task { await store.completeDemo() } } label: {
                HStack { if store.paymentBusy { ProgressView() }; Text("Complete demo booking"); Image(systemName: "arrow.right") }
            }.buttonStyle(PrimaryButtonStyle()).disabled(!checked || store.paymentBusy || store.completedTrip != nil).opacity(checked ? 1 : 0.5)
            if payment.canPresent {
                NativeApplePayButton { Task { await payment.present(store: store) } }.frame(height: 50).disabled(!checked || payment.busy)
            }
            Panel {
                Label("Apple Pay integration", systemImage: "apple.logo").font(.headline)
                Text(payment.status).font(.subheadline).foregroundStyle(.secondary)
                InfoNote(text: "Wallet authorisation, provider capture and airline ticket issuance are tracked separately. Demo inventory is never sent to Apple Pay for a real charge.")
            }
            Button("Cancel checkout and return to review") { store.analytics.emit("checkout_cancelled", "checkout.cancel"); store.navigate(.review, back: true) }.frame(minHeight: 44)
        }.task { await payment.prepare(store: store) }
    }
}

struct ConfirmationScreen: View {
    @Environment(BookingStore.self) private var store
    var body: some View {
        if let trip = store.completedTrip {
            VStack(alignment: .leading, spacing: 24) {
                ZStack { Circle().fill(TripTheme.yellow).frame(width: 76, height: 76); Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)) }.padding(.top, 12)
                Text("You're all set.").font(.system(.largeTitle, design: .default, weight: .bold))
                Text("A trip that fits you.").font(.title3).foregroundStyle(.secondary)
                Image(store.imageName).resizable().scaledToFill().frame(height: 210).clipped().clipShape(RoundedRectangle(cornerRadius: 25))
                Panel {
                    Pill(text: "DEMO BOOKING", yellow: true)
                    Text(trip.itinerary.title).font(.title2.bold())
                    Text(trip.id).font(.system(.title3, design: .monospaced, weight: .bold))
                    HStack { Text("Simulated total"); Spacer(); Text(euros(trip.totalCents)).bold() }
                    Label("No payment charged", systemImage: "checkmark.circle")
                    Label("No real ticket issued", systemImage: "info.circle")
                    Text("Saved in My Trips. This is not a boarding pass or a travel document.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("View My Trips") { store.navigate(.trips) }.buttonStyle(PrimaryButtonStyle())
                Button("Back to exploring") { store.reset() }.frame(maxWidth: .infinity, minHeight: 44)
                if store.analytics.enabled { InfoNote(text: store.analytics.status, symbol: "chart.bar.xaxis") }
            }
        } else { ContentUnavailableView("No completed booking yet", systemImage: "airplane", description: Text("Choose a journey to start.")); Button("Explore journeys") { store.reset() }.buttonStyle(PrimaryButtonStyle()) }
    }
}
struct TripsScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var selected: SavedTrip?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("My trips.").font(.system(.largeTitle, design: .default, weight: .bold))
            if store.trips.isEmpty { ContentUnavailableView("The next chapter is yours", systemImage: "suitcase.rolling", description: Text("Completed demo bookings will be saved here.")); Button("Find a journey") { store.reset() }.buttonStyle(PrimaryButtonStyle()) }
            ForEach(store.trips) { trip in Button { selected = trip } label: { Panel {
                HStack { Pill(text: "DEMO", yellow: true); Spacer(); Text(trip.request.outboundDate.formatted(date: .abbreviated, time: .omitted)).font(.caption) }
                Text(trip.itinerary.title).font(.title3.bold())
                HStack { Text(trip.id).font(.system(.caption, design: .monospaced)); Spacer(); Image(systemName: "arrow.up.right") }
                Text("\(trip.request.passengers.count) travellers · \(euros(trip.totalCents)) simulated").font(.subheadline).foregroundStyle(.secondary)
            } }.buttonStyle(.plain) }
        }.sheet(item: $selected) { trip in TripDetail(trip: trip) }
    }
}
struct TripDetail: View {
    var trip: SavedTrip
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 22) {
            Pill(text: "DEMO · NO TICKET ISSUED", yellow: true)
            Text(trip.itinerary.title).font(.largeTitle.bold()); Text(trip.id).font(.system(.headline, design: .monospaced))
            ForEach(trip.itinerary.segments) { segment in Panel {
                SegmentSummary(segment: segment)
                ForEach(trip.request.passengers) { p in
                    Text("\(p.displayName) · \(Baggage.allowance(passengerID: p.id, segment: segment, selection: trip.selection).summary)").font(.caption)
                    Text("Seat: \(trip.selection.seats.first { $0.passengerID == p.id && $0.segmentID == segment.id }?.seatID ?? "Unassigned") · Meal: \(meal(p.id, segment.id))").font(.caption)
                }
            } }
            Text(trip.itinerary.transferTerms).font(.footnote).foregroundStyle(.secondary)
            PriceBreakdown(quote: Pricing.quote(itinerary: trip.itinerary, passengers: trip.request.passengers, selection: trip.selection))
            InfoNote(text: "No money charged. This reference is not usable for travel or check-in.")
        }.padding(24) }.navigationTitle("Trip details").tripInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
    }
    func meal(_ passenger: String, _ segment: String) -> String {
        let id = trip.selection.meals.first { $0.passengerID == passenger && $0.segmentID == segment }?.productID
        return Catalog.mealProducts.first { $0.id == id }?.name ?? "None"
    }
}
