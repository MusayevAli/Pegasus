import SwiftUI
import TripFitCore

struct SearchScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var customSearch = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 36
    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Explore.").font(.system(size: heroSize, weight: .bold, design: .default)).tracking(-1.2).accessibilityAddTraits(.isHeader)
                Text("A journey that's more you.").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                category("Find flights", symbol: "airplane") { customSearch = true }
                category("Travel light", symbol: "backpack") { store.demo(.soloLight) }
                category("Together", symbol: "person.2") { store.demo(.barcelonaFamily) }
                category("Connect", symbol: "point.topleft.down.to.point.bottomright.curvepath") { store.demo(.usConnection) }
            }.padding(.vertical, 8)
            AIEntryCard()
            Button { store.demo(.barcelonaFamily) } label: {
                VStack(spacing: 0) {
                    VStack(spacing: 9) {
                        Text("Made for making memories.").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Barcelona.\nBetter together.").font(.system(.title, design: .default, weight: .bold)).tracking(-0.8).multilineTextAlignment(.center)
                        Text("6 nights. 2 adults. 1 little explorer.").font(.subheadline)
                        HStack(spacing: 6) { Text("Find your fit"); Image(systemName: "chevron.right").font(.caption.bold()) }.font(.subheadline.weight(.semibold)).padding(.horizontal, 17).padding(.vertical, 9).background(TripTheme.yellow, in: Capsule()).padding(.top, 3)
                    }.padding(.vertical, 24).padding(.horizontal, 18)
                    Image("barcelona").resizable().scaledToFill().frame(height: 210).clipped()
                }.background(TripTheme.card).clipShape(RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain).accessibilityLabel("Try Barcelona family demo, two adults and one child, six nights")
            SectionTitle(title: "Go a little further.", subtitle: "Two more ways to make a trip your own.")
            HStack(alignment: .top, spacing: 12) {
                smallJourney(.usConnection, image: "istanbul", title: "Across the Atlantic", detail: "JFK → LGW → SAW")
                smallJourney(.soloLight, image: "antalya", title: "Less baggage. More sea.", detail: "SAW → AYT · Solo")
            }
            InfoNote(text: "Try the demo. Illustrative schedules and prices. No charge or real ticket.")
            Button { customSearch = true } label: { HStack { Text("Find your own fit").font(.title2.bold()); Spacer(); Image(systemName: "arrow.up.right.circle") }.padding(.vertical, 6) }.buttonStyle(.plain)
            if store.itinerary != nil { Button("Resume your saved booking") { store.navigate(.configuration) }.buttonStyle(PrimaryButtonStyle()) }
            Panel {
                Label("A smarter fit, in your hands.", systemImage: "checkmark.seal").font(.headline)
                Text("Personal suggestions are optional. Nothing is added until you choose it — and travelling light can mean spending less.").font(.subheadline).foregroundStyle(.secondary)
            }
        }.sheet(isPresented: $customSearch) {
            NavigationStack {
                ScrollView { searchForm.padding(24) }
                    .navigationTitle("Find your flight")
                    .tripInlineTitle()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customSearch = false } } }
            }
        }
    }
    func category(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 25, weight: .light)).frame(width: 56, height: 56).background(TripTheme.card, in: Circle())
                Text(title).font(.caption2.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, minHeight: 80, alignment: .top)
        }.buttonStyle(.plain)
    }
    func smallJourney(_ demo: DemoJourney, image: String, title: String, detail: String) -> some View {
        Button { store.demo(demo) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(image).resizable().scaledToFill().frame(height: 120).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                Text(title).font(.headline).multilineTextAlignment(.leading)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .topLeading)
        }.buttonStyle(.plain)
    }
    var searchForm: some View {
        @Bindable var store = store
        return Panel {
            Picker("From", selection: $store.request.origin) {
                Text("Istanbul · SAW").tag("SAW"); Text("New York · JFK").tag("JFK"); Text("London · LGW").tag("LGW"); Text("Paris · CDG").tag("CDG")
            }
            Picker("To", selection: $store.request.destination) {
                Text("Barcelona · BCN").tag("BCN"); Text("Istanbul · SAW").tag("SAW"); Text("Antalya · AYT").tag("AYT"); Text("Paris · CDG").tag("CDG")
            }
            Toggle("Round trip", isOn: Binding(get: { store.request.returnDate != nil }, set: { store.request.returnDate = $0 ? Calendar.current.date(byAdding: .day, value: 6, to: store.request.outboundDate) : nil }))
            DatePicker("Departure", selection: $store.request.outboundDate, in: Date()..., displayedComponents: .date)
            if store.request.returnDate != nil {
                DatePicker("Return", selection: Binding(get: { store.request.returnDate ?? store.request.outboundDate }, set: { store.request.returnDate = $0 }), in: store.request.outboundDate..., displayedComponents: .date)
            }
            Stepper("Adults · \(store.request.adults)", value: $store.request.adults, in: 1...6)
            Stepper("Children · \(store.request.children)", value: $store.request.children, in: 0...4)
            Text("Guest booking · maximum 9 travellers. Child demo age: 8. No account needed.").font(.caption).foregroundStyle(.secondary)
            Button { store.loading = true; Task { try? await Task.sleep(for: .milliseconds(180)); customSearch = false; store.performSearch(); store.loading = false } } label: {
                if store.loading { ProgressView().frame(maxWidth: .infinity) } else { Label("Find flights", systemImage: "magnifyingglass") }
            }.buttonStyle(PrimaryButtonStyle()).disabled(store.loading)
        }
    }
}

struct ResultsScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var shortestFirst = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(store.request.origin) → \(store.request.destination) · \(store.passengers.count) travellers").font(.headline)
            Text("\(store.request.outboundDate.formatted(date: .abbreviated, time: .omitted)) · \(store.request.returnDate == nil ? "One way" : "\(store.request.nights) nights")").foregroundStyle(.secondary)
            if store.results.isEmpty {
                ContentUnavailableView("A little outside our demo map", systemImage: "globe.europe.africa", description: Text("Try Istanbul–Barcelona, New York–Istanbul via Gatwick, or Istanbul–Antalya. These are illustrative journeys, not global availability."))
                ForEach(DemoJourney.allCases) { demo in Button(demo.title) { store.demo(demo) }.buttonStyle(PrimaryButtonStyle()) }
            } else {
                Picker("Compare flights", selection: $shortestFirst) { Text("Lowest price").tag(false); Text("Shortest journey").tag(true) }.pickerStyle(.segmented)
                    .onChange(of: shortestFirst) { _, v in store.analytics.emit("filter_changed", "results.sort", ["choice": .string(v ? "duration" : "price")]) }
                ForEach(sortedResults) { offer in
                    Panel {
                        HStack { Pill(text: offer.transferKind == .selfTransfer ? "SELF-TRANSFER" : "DIRECT", yellow: true); Spacer(); Text(euros(Pricing.quote(itinerary: offer, passengers: store.passengers, selection: BookingSelection()).totalCents)).font(.title2.bold()) }
                        Text(offer.title).font(.title3.bold())
                        ForEach(offer.segments) { segment in SegmentSummary(segment: segment) }
                        HStack { Label(duration(offer.durationMinutes), systemImage: "clock"); Spacer(); Text("All travellers · EUR") }.font(.caption).foregroundStyle(.secondary)
                        if let connection = offer.connectionMinutes { Text("\(duration(connection)) at London Gatwick (LGW) · collect and re-check bags").font(.subheadline) }
                        DisclosureGroup("Baggage, fare & transfer details") {
                            ForEach(offer.segments) { segment in Text("\(segment.flightNumber): \(segment.includedBaggage.summary)").font(.footnote).frame(maxWidth: .infinity, alignment: .leading) }
                            Text(offer.fareConditions).font(.footnote)
                            if offer.transferKind != .direct { ConnectionTimeline(itinerary: offer) }
                        }.font(.subheadline).simultaneousGesture(TapGesture().onEnded { store.analytics.emit("offer_compared", "itinerary.details", ["journeyId": .string(offer.id)]) })
                        Button("Choose this journey") { store.choose(offer) }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            if !store.rejected.isEmpty {
                SectionTitle(title: "A connection we ruled out", subtitle: "More options aren't always better.")
                ForEach(store.rejected) { rejected in Panel {
                    Label(rejected.title, systemImage: "xmark.circle").font(.headline)
                    Text(rejected.reason).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(rejected.connectionMinutes) minute connection · not bookable").font(.caption.bold())
                }.onAppear { store.analytics.emit("validation_error", "connections.rejected", ["code": .string("connection_too_short"), "journeyId": .string(rejected.id)]) } }
            }
            InfoNote(text: "All schedules, prices and airline combinations shown here are demo fixtures. Transfer buffers are planning rules, never guarantees.")
            Button("Edit search") { store.navigate(.search, back: true) }.frame(minHeight: 44)
        }
    }
    var sortedResults: [Itinerary] { store.results.sorted { shortestFirst ? $0.durationMinutes < $1.durationMinutes : $0.basePricePerAdultCents < $1.basePricePerAdultCents } }
}
struct SegmentSummary: View {
    var segment: Segment
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("\(segment.direction.title) · \(segment.carrier)").font(.caption.bold()); Spacer(); Text(segment.flightNumber).font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) { Text(segment.origin).font(.title2.bold()); Text(segment.localDeparture()).font(.caption); Text(airportName(segment.origin)).font(.caption2).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "airplane").foregroundStyle(.secondary); Spacer()
                VStack(alignment: .trailing, spacing: 4) { Text(segment.destination).font(.title2.bold()); Text(segment.localArrival()).font(.caption); Text(airportName(segment.destination)).font(.caption2).foregroundStyle(.secondary) }
            }
            Text("Local airport times · \(duration(segment.durationMinutes))").font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
struct ConnectionTimeline: View {
    @Environment(BookingStore.self) private var store
    var itinerary: Itinerary
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let incoming = itinerary.segments.first, let onward = itinerary.segments.dropFirst().first {
                timeline("Arrive at \(incoming.destination)", detail: incoming.localArrival() + " · " + incoming.carrier, symbol: "airplane.arrival")
                timeline("Collect your checked baggage", detail: "Separate tickets · baggage is not checked through", symbol: "suitcase.rolling")
                timeline("Entry and airline check-in", detail: "Allow time for entry formalities. Check-in closes 60 min before departure in this demo.", symbol: "person.text.rectangle")
                timeline("Security and your gate", detail: "Re-clear security. Configured processing buffer: 120 min, plus the check-in deadline.", symbol: "checkmark.shield")
                timeline("Depart on Pegasus", detail: onward.localDeparture() + " · " + onward.origin, symbol: "airplane.departure")
            }
            Text(itinerary.transferTerms).font(.footnote).foregroundStyle(.secondary)
            InfoNote(text: "A through-ticket or a supplied protection product would have its own explicit terms. This offer includes neither. Entry/transit eligibility has not been checked.")
        }.padding(.top, 10).onAppear { store.analytics.emit("connection_opened", "connection.timeline", ["journeyId": .string(itinerary.id)]) }
    }
    func timeline(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Image(systemName: symbol).frame(width: 32, height: 32).background(TripTheme.yellow.opacity(0.2), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.bold()); Text(detail).font(.caption).foregroundStyle(.secondary) } }
    }
}
func duration(_ minutes: Int) -> String { "\(minutes / 60)h \(minutes % 60)m" }
func airportName(_ code: String) -> String { ["SAW":"Sabiha Gökçen", "BCN":"Barcelona El Prat", "JFK":"John F. Kennedy", "LGW":"London Gatwick", "AYT":"Antalya", "CDG":"Paris Charles de Gaulle"][code] ?? code }
