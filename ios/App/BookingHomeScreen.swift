import SwiftUI
import TripFitCore

struct BookingHomeRoot: View {
    @Environment(BookingV2Store.self) private var booking
    @Environment(BookingStore.self) private var legacy
    @Environment(TravelProfileStore.self) private var memory
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = booking.error {
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                Text(error).font(.subheadline)
                                Spacer(minLength: 2)
                                Button { booking.error = nil } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.accessibilityLabel("Dismiss message")
                            }.padding(16).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        switch booking.stage {
                        case .search: FlightSearchHome()
                        case .results: FlightSearchResults()
                        case .configuration: BookingConfigurationScreen()
                        case .review: BookingReviewScreen()
                        case .confirmation: BookingConfirmationScreen()
                        case .trips: BookingSavedTripsScreen()
                        }
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 28).frame(maxWidth: 680)
                }.scrollDismissesKeyboard(.interactively).id(booking.stage)
                if (booking.stage == .configuration || booking.stage == .review) && booking.selectedOffer?.effectiveCapabilities.quote == true { BookingPinnedTotal() }
                if [.search, .results, .trips].contains(booking.stage) { tabs }
            }
            .background(.white).foregroundStyle(TripTheme.ink)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if ![.search, .trips].contains(booking.stage) {
                        Button { booking.back() } label: { Image(systemName: "chevron.left").font(.headline).frame(minWidth: 32, minHeight: 44) }.accessibilityLabel("Back")
                    } else {
                        HStack(spacing: 6) { Image(systemName: "airplane").rotationEffect(.degrees(-25)).padding(7).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 8)); Text("Pegasus").bold(); Text("TripFit").foregroundStyle(.secondary) }.font(.subheadline).fixedSize(horizontal: true, vertical: false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "person.crop.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("What we know about you and settings") }
            }
            .navigationTitle(booking.stage == .search || booking.stage == .trips ? "" : stageTitle)
            .tripInlineTitle()
            .sheet(isPresented: $settings) { TravelProfileScreen() }
            .task { await booking.initialize(); await memory.load() }
            .onChange(of: phase) { _, value in legacy.analytics.setForeground(value == .active); if value != .active { booking.persist() } }
            .onChange(of: booking.stage) { _, value in legacy.analytics.view(value == .results ? "itinerary" : value.rawValue); booking.persist() }
            .simultaneousGesture(TapGesture().onEnded { legacy.analytics.interact() })
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: booking.stage)
        }
    }
    private var stageTitle: String {
        switch booking.stage { case .results: "Choose flights"; case .configuration: "Your trip"; case .review: "Review & book"; case .confirmation: "Confirmation"; default: "" }
    }
    private var tabs: some View {
        HStack {
            tab("Search", symbol: "magnifyingglass", selected: booking.stage == .search) { booking.stage = .search }
            tab("For You", symbol: "person.crop.circle", selected: false) { settings = true }
            tab("My Trips", symbol: "suitcase.rolling", selected: booking.stage == .trips) { booking.stage = .trips }
        }.padding(.vertical, 8).background(.white).overlay(alignment: .top) { Divider() }
    }
    private func tab(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 5) { Image(systemName: symbol).font(.title3); Text(title).font(.caption.weight(selected ? .semibold : .regular)) }.frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(selected ? TripTheme.ink : .secondary) }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FlightSearchHome: View {
    @Environment(BookingV2Store.self) private var booking
    @State private var description = ""
    @State private var importSheet = false
    @FocusState private var noteFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where next?").font(.system(.largeTitle, design: .default, weight: .bold)).tracking(-1)
                Text("Less planning. More going.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.magnifyingglass").font(.title3).padding(.top, 6)
                    TextField("Describe your trip, or search below", text: $description, axis: .vertical).lineLimit(2...4).focused($noteFocused).accessibilityLabel("Describe your trip")
                        .onChange(of: description) { _, value in
                            if value.count > 1200 { description = String(value.prefix(1200)) }
                            if booking.aiBusy { booking.cancelInterpretation() }
                        }
                    Button {
                        noteFocused = false
                        Task { await booking.interpret(description) }
                    } label: {
                        Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44).background(TripTheme.yellow, in: Circle())
                    }.disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || booking.aiBusy).accessibilityLabel("Find flights from description")
                }.padding(17).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 20))
                if booking.aiBusy {
                    HStack { ProgressView(); Text("Understanding your trip…").font(.subheadline); Spacer(); Button("Cancel") { booking.cancelInterpretation() } }
                } else if !booking.aiStatus.isEmpty && booking.aiStatus != "Describe a trip or use the fields below." {
                    HStack(alignment: .top) { Text(booking.aiStatus).font(.caption).foregroundStyle(.secondary); Spacer(); if booking.aiStatus.lowercased().contains("unavailable") { Button("Retry") { Task { await booking.interpret(description) } }.font(.caption.bold()) } }
                }
                Button { importSheet = true } label: { Label("Import screenshot", systemImage: "photo.badge.plus").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
            }
            InventoryProviderPicker()
            SearchIntentEditor()
            Button { noteFocused = false; Task { await booking.search() } } label: {
                HStack { if booking.busy { ProgressView() }; Text("Search flights"); Spacer(); Image(systemName: "arrow.right") }
            }.buttonStyle(PrimaryButtonStyle()).disabled(booking.busy || booking.aiBusy)
            InventorySourceLine()
            if let offer = booking.selectedOffer, booking.completedOrder == nil {
                Button { booking.stage = .configuration } label: { HStack { Image(systemName: "arrow.clockwise"); Text("Continue \(offer.itinerary.routeLabel)"); Spacer(); Image(systemName: "chevron.right") }.font(.subheadline.weight(.semibold)).padding(18).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("A little inspiration.").font(.title2.bold())
                Image("barcelona").resizable().scaledToFill().frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: 22))
                HStack { VStack(alignment: .leading, spacing: 5) { Text("A week in Barcelona.").font(.headline); Text("Make room for a change of scene.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Button { booking.editIntent { $0.destinationAirports = ["BCN"] } } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44).background(TripTheme.card, in: Circle()) }.accessibilityLabel("Choose Barcelona destination") }
            }
        }.sheet(isPresented: $importSheet) { TripImportScreen() }
    }
}

struct InventorySourceLine: View {
    @Environment(BookingV2Store.self) private var booking
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(TripTheme.yellow).frame(width: 6, height: 6)
            Text(booking.selectedOffer?.source == "sample" || (booking.selectedOffer == nil && booking.providerID == "sample") ? "Sample flights · illustrative schedules & prices" : "Live flights · Pegasus Airlines").font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct InventoryProviderPicker: View {
    @Environment(BookingV2Store.self) private var booking
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Flight inventory", selection: Binding(get: { booking.providerID }, set: { booking.setProvider($0) })) {
                Text("Live Pegasus").tag("pegasus_mcp")
                Text("Demo booking").tag("sample")
            }.pickerStyle(.segmented)
            Text(booking.providerID == "sample" ? "Explore the complete demo booking, bags and seats with sample prices." : "Search Pegasus flights. Confirm extras and complete your booking with Pegasus.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SearchIntentEditor: View {
    @Environment(BookingV2Store.self) private var booking
    @State private var moreFilters = false
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !booking.missingFields.isEmpty && (booking.stage == .results || booking.lastAIRequestId != nil || booking.error != nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Just a few details.").font(.headline)
                    ForEach(booking.missingFields) { field in Text(field.question).font(.subheadline).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(TripTheme.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 17))
            }
            HStack(alignment: .top, spacing: 12) {
                airportPicker("From", selection: Binding(get: { booking.intent.originAirport ?? "" }, set: { value in edit("originAirport") { $0.originAirport = value.isEmpty ? nil : value } }))
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).padding(.top, 32)
                airportPicker("To", selection: Binding(get: { booking.intent.destinationAirports.first ?? "" }, set: { value in edit("destinationAirports") { $0.destinationAirports = value.isEmpty ? [] : [value] } }))
            }
            Picker("Trip type", selection: Binding(get: { booking.intent.tripType }, set: { value in edit("tripType") { $0.tripType = value; if value == "one_way" { $0.returnDate = nil; $0.durationNights = nil } else if $0.returnDate == nil { $0.returnDate = V2Dates.day(Calendar.current.date(byAdding: .day, value: 6, to: V2Dates.date($0.outboundDate ?? "") ?? Date())!) } } })) { Text("Return").tag("round_trip"); Text("One way").tag("one_way") }.pickerStyle(.segmented)
            if let window = booking.intent.dateWindow {
                HStack { Text("Flexible: \(window.start) – \(window.end)").font(.subheadline); Spacer(); Button("Exact date") { edit("dateWindow") { $0.outboundDate = window.start; $0.dateWindow = nil } }.font(.caption.bold()) }
                Stepper("\(booking.intent.durationNights ?? 6) nights", value: Binding(get: { booking.intent.durationNights ?? 6 }, set: { value in edit("durationNights") { $0.durationNights = value } }), in: 1...21)
            } else {
                DatePicker("Depart", selection: dateBinding(\.outboundDate, field: "outboundDate"), displayedComponents: .date)
                if booking.intent.tripType == "round_trip" { DatePicker("Return", selection: dateBinding(\.returnDate, field: "returnDate"), displayedComponents: .date) }
            }
            Divider()
            Stepper("\(booking.intent.adults) adult\(booking.intent.adults == 1 ? "" : "s")", value: Binding(get: { booking.intent.adults }, set: { value in edit("adults") { $0.adults = value } }), in: 1...max(1, min(8, 9 - booking.intent.childAges.count)))
            Stepper("\(booking.intent.childAges.count) children", value: Binding(get: { booking.intent.childAges.count }, set: { value in edit("childAges") { intent in if value > intent.childAges.count { intent.childAges.append(contentsOf: Array(repeating: nil, count: value - intent.childAges.count)) } else { intent.childAges = Array(intent.childAges.prefix(value)) } } }), in: 0...max(0, 9 - booking.intent.adults))
            ForEach(booking.intent.childAges.indices, id: \.self) { index in
                Picker("Child \(index + 1) age", selection: Binding(get: { booking.intent.childAges[index] ?? -1 }, set: { value in edit("childAges") { $0.childAges[index] = value < 0 ? nil : value } })) { Text("Choose age").tag(-1); ForEach(2...11, id: \.self) { Text("\($0)").tag($0) } }.tint(TripTheme.ink)
            }
            if booking.intent.budgetMinor != nil || booking.intent.checkedBags != nil || compact { explicitPreferences }
            DisclosureGroup("More preferences", isExpanded: $moreFilters) {
                VStack(alignment: .leading, spacing: 18) {
                    if !(booking.intent.budgetMinor != nil || booking.intent.checkedBags != nil || compact) { explicitPreferences }
                    Toggle("Avoid overnight travel", isOn: boolBinding(\.noOvernight, field: "noOvernight"))
                    Picker("Connections", selection: Binding(get: { booking.intent.maxConnections ?? 2 }, set: { value in edit("maxConnections") { $0.maxConnections = value == 2 ? nil : value } })) { Text("Direct only").tag(0); Text("Up to one").tag(1); Text("Any supported").tag(2) }
                    HStack { Text("Depart after"); Spacer(); TextField("HH:mm", text: Binding(get: { booking.intent.departureAfter ?? "" }, set: { value in edit("departureAfter") { $0.departureAfter = value.isEmpty ? nil : value } })).multilineTextAlignment(.trailing).frame(width: 90) }
                    Toggle("Seats together", isOn: boolBinding(\.keepTogether, field: "keepTogether"))
                    Toggle("Meals on every flight", isOn: boolBinding(\.meals, field: "meals"))
                    if booking.intent.meals { Toggle("Vegetarian meals", isOn: boolBinding(\.vegetarian, field: "vegetarian")) }
                    Toggle("No alcohol", isOn: boolBinding(\.noAlcohol, field: "noAlcohol"))
                }.font(.subheadline).padding(.top, 16)
            }.font(.subheadline.weight(.medium)).tint(TripTheme.ink)
            if let incoming = booking.intent.incomingFlight {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Connecting from \(incoming.airline)").font(.headline)
                    Text("Arrive \(incoming.arrivalAirport) · \(incoming.arrivalAt)").font(.caption)
                    Stepper("Connection buffer: \(incoming.minimumConnectionMinutes) min", value: Binding(get: { booking.intent.incomingFlight?.minimumConnectionMinutes ?? 180 }, set: { value in edit("incomingFlight") { $0.incomingFlight?.minimumConnectionMinutes = value } }), in: 60...720, step: 30).font(.subheadline)
                    Text("Incoming flight already booked. Search prices cover onward travel only.").font(.caption).foregroundStyle(.secondary)
                    Button("Remove incoming flight") { edit("incomingFlight") { $0.incomingFlight = nil } }.font(.caption.bold())
                }.padding(16).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 16))
            }
            if booking.intent.arrivalDeadline != nil {
                let zone = booking.airports.first { $0.code == booking.intent.destinationAirports.first }?.timeZone ?? "UTC"
                DatePicker("Arrive at airport by", selection: Binding(get: { V2Dates.instant(booking.intent.arrivalDeadline ?? "") ?? Date() }, set: { value in edit("arrivalDeadline") { $0.arrivalDeadline = ISO8601DateFormatter().string(from: value) } }), displayedComponents: [.date, .hourAndMinute]).environment(\.timeZone, TimeZone(identifier: zone) ?? .gmt)
                Text("Airport local time · \(zone). Include ground travel in your arrival buffer.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var explicitPreferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Budget · EUR"); Spacer(); TextField("No limit", text: Binding(get: { booking.intent.budgetMinor.map { String($0 / 100) } ?? "" }, set: { value in edit("budgetMinor") { $0.budgetMinor = Int(value).map { $0 * 100 }; if value.isEmpty { $0.budgetScope = nil } } })).multilineTextAlignment(.trailing).frame(width: 100).tripNumberInput() }
            if booking.intent.budgetMinor != nil {
                Picker("Budget applies to", selection: Binding(get: { booking.intent.budgetScope ?? "" }, set: { value in edit("budgetScope") { $0.budgetScope = value.isEmpty ? nil : value } })) { Text("Please choose").tag(""); Text("Whole party").tag("party"); Text("Each person").tag("per_person") }
            }
            Stepper("\(booking.intent.checkedBags ?? 0) checked bags", value: Binding(get: { booking.intent.checkedBags ?? 0 }, set: { value in edit("checkedBags") { $0.checkedBags = value; if value == 0 { $0.baggageScope = "party"; $0.baggageDirection = "both" } } }), in: 0...4)
            if (booking.intent.checkedBags ?? 0) > 0 {
                Picker("Bags for", selection: Binding(get: { booking.intent.baggageScope ?? "" }, set: { value in edit("baggageScope") { $0.baggageScope = value.isEmpty ? nil : value } })) { Text("Please choose").tag(""); Text("Whole party").tag("party"); Text("Each traveller").tag("per_passenger") }
                Picker("On which flights?", selection: Binding(get: { booking.intent.baggageDirection ?? "" }, set: { value in edit("baggageDirection") { $0.baggageDirection = value.isEmpty ? nil : value } })) { Text("Please choose").tag(""); Text("Outbound").tag("outbound"); if booking.intent.tripType == "round_trip" { Text("Return").tag("return"); Text("Both ways").tag("both") } }
            }
        }.font(.subheadline)
    }
    private func edit(_ field: String, _ mutate: (inout V2SearchIntent) -> Void) { booking.editIntent { intent in mutate(&intent); intent.unresolved.removeAll { $0.field == field } } }
    private func airportPicker(_ label: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: selection) { Text("Choose airport").tag(""); ForEach(booking.airports) { airport in Text("\(airport.city) · \(airport.code)").tag(airport.code) } }.labelsHidden().tint(TripTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 15))
    }
    private func dateBinding(_ key: WritableKeyPath<V2SearchIntent, String?>, field: String) -> Binding<Date> {
        Binding(get: { V2Dates.date(booking.intent[keyPath: key] ?? "") ?? Date() }, set: { value in edit(field) { $0[keyPath: key] = V2Dates.day(value); $0.dateWindow = nil } })
    }
    private func boolBinding(_ key: WritableKeyPath<V2SearchIntent, Bool>, field: String) -> Binding<Bool> { Binding(get: { booking.intent[keyPath: key] }, set: { value in edit(field) { $0[keyPath: key] = value } }) }
}

struct FlightSearchResults: View {
    @Environment(BookingV2Store.self) private var booking
    @State private var editing = false
    @State private var comparing = false
    @State private var compareIDs: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find your flight.").font(.largeTitle.bold()).tracking(-1)
                    Text("\(booking.intent.originAirport ?? "From") → \(booking.intent.destinationAirports.joined(separator: ", ")) · \(booking.intent.partySize) \(booking.intent.partySize == 1 ? "traveller" : "travellers")").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Edit") { editing = true }.font(.subheadline.bold()).frame(minHeight: 44)
            }
            SearchPreferenceChips(edit: { editing = true })
            InventorySourceLine()
            if let notice = booking.notice { Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if booking.busy { ProgressView("Finding flights…").frame(maxWidth: .infinity).padding(30) }
            if !booking.missingFields.isEmpty {
                SearchIntentEditor(compact: true)
                Button("Show matching flights") { Task { await booking.search() } }.buttonStyle(PrimaryButtonStyle()).disabled(booking.busy)
            } else if booking.offers.isEmpty && !booking.busy {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "airplane.circle").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("No exact matches.").font(.title2.bold())
                    Text(booking.notice ?? "Try another date or adjust a preference.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Edit search") { editing = true }.buttonStyle(PrimaryButtonStyle())
                }.padding(22).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 22))
                if !booking.alternatives.isEmpty {
                    Text("A small change could work.").font(.title2.bold())
                    ForEach(booking.alternatives) { alternative in
                        Panel {
                            ForEach(alternative.changes) { change in Label("\(fieldTitle(change.field)): \(changeValue(change.from, field: change.field)) → \(changeValue(change.to, field: change.field))", systemImage: "arrow.triangle.swap").font(.subheadline.bold()) }
                            FlightOfferFacts(offer: alternative.offer)
                            Text(alternative.explanation).font(.subheadline).foregroundStyle(.secondary)
                            Button("Use these changes") { Task { await booking.chooseAlternative(alternative) } }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
            ForEach(booking.offers) { offer in
                VStack(alignment: .leading, spacing: 17) {
                    FlightOfferFacts(offer: offer)
                    HStack {
                        Button { toggleCompare(offer.id) } label: { Label(compareIDs.contains(offer.id) ? "Selected" : "Compare", systemImage: compareIDs.contains(offer.id) ? "checkmark.circle.fill" : "circle").font(.subheadline.weight(.medium)).frame(minHeight: 44) }.buttonStyle(.plain).accessibilityLabel("Compare flight \(offer.id)")
                        Spacer()
                        Button(offer.effectiveCapabilities.checkout ? "Choose flight" : "View flight") { Task { await booking.select(offer) } }.font(.subheadline.bold()).padding(.horizontal, 22).frame(minHeight: 46).background(TripTheme.yellow, in: Capsule()).buttonStyle(.plain).disabled(booking.busy)
                    }
                }.padding(20).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 22))
            }
            if !compareIDs.isEmpty {
                Button(compareIDs.count == 2 ? "Compare these 2 flights" : "Select one more flight") { comparing = true; Task { await booking.compareSelected(compareIDs) } }.buttonStyle(PrimaryButtonStyle()).disabled(compareIDs.count != 2 || booking.busy)
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { ScrollView { VStack(spacing: 20) { InventoryProviderPicker(); SearchIntentEditor(compact: true) }.padding(24) }.navigationTitle("Your search").tripInlineTitle().safeAreaInset(edge: .bottom) { Button("Update flights") { editing = false; Task { await booking.search() } }.buttonStyle(PrimaryButtonStyle()).padding().background(.white) }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { editing = false } } } } }
        .sheet(isPresented: $comparing) { FlightComparisonScreen() }
        .onChange(of: booking.offers.map(\.id)) { _, ids in compareIDs.removeAll { !ids.contains($0) } }
    }
    private func toggleCompare(_ id: String) { if compareIDs.contains(id) { compareIDs.removeAll { $0 == id } } else { if compareIDs.count == 2 { compareIDs.removeFirst() }; compareIDs.append(id) } }
    private func changeValue(_ value: String, field: String) -> String {
        if field == "budgetMinor", let amount = Int(value) { return V2Money(amountMinor: amount).formatted }
        if field == "noOvernight" { return value == "true" ? "Avoid" : "Allowed" }
        return value
    }
}

struct SearchPreferenceChips: View {
    @Environment(BookingV2Store.self) private var booking
    var edit: () -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(booking.intent.outboundDate ?? "Flexible dates", field: booking.intent.dateWindow == nil ? "outboundDate" : "dateWindow", removable: false)
                if booking.intent.maxConnections == 0 { chip("Direct", field: "maxConnections") }
                if booking.intent.noOvernight { chip("No overnight", field: "noOvernight") }
                if let budget = booking.intent.budgetMinor { chip("Under \(V2Money(amountMinor: budget).formatted) \(booking.intent.budgetScope == nil ? "· confirm scope" : booking.intent.budgetScope == "per_person" ? "each" : "total")", field: "budgetMinor") }
                if let bags = booking.intent.checkedBags, bags > 0 { chip("\(bags) checked bag\(bags == 1 ? "" : "s") · \(booking.intent.baggageScope == nil ? "confirm scope" : booking.intent.baggageScope == "per_passenger" ? "each" : "party")", field: "checkedBags") }
                if booking.intent.arrivalDeadline != nil { chip("Arrival deadline", field: "arrivalDeadline") }
                chip("\(booking.intent.partySize) \(booking.intent.partySize == 1 ? "traveller" : "travellers")", field: "adults", removable: false)
            }
        }
    }
    private func chip(_ label: String, field: String, removable: Bool = true) -> some View {
        let locked = booking.intent.lockedFields.contains(field)
        return Menu {
            Button("Edit preference", action: edit)
            if field != "adults" { Button(locked ? "Unlock requirement" : "Lock requirement") { booking.setLocked(field, !locked) } }
            if removable { Button("Remove preference") { booking.editIntent { intent in
                switch field { case "maxConnections": intent.maxConnections = nil; case "noOvernight": intent.noOvernight = false; case "budgetMinor": intent.budgetMinor = nil; intent.budgetScope = nil; case "checkedBags": intent.checkedBags = 0; case "arrivalDeadline": intent.arrivalDeadline = nil; default: break }
                intent.lockedFields.removeAll { $0 == field }
            } } }
        } label: { HStack(spacing: 6) { Text(label); Image(systemName: locked ? "lock.fill" : "chevron.down").font(.caption2) }.font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 40).background(locked ? TripTheme.yellow.opacity(0.25) : TripTheme.card, in: Capsule()) }
    }
}

struct FlightOfferFacts: View {
    var offer: V2FlightOffer
    var quotedTotal: V2Money? = nil
    var quotedBaggage: String? = nil
    var needsQuote = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(needsQuote ? "Price needs updating" : (quotedTotal ?? offer.totalPrice).formatted).font(.title.bold()).tracking(-0.8)
                Spacer()
                Text(offer.itinerary.transferType == "direct" ? "Direct" : "Connection").font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7).background(.white, in: Capsule())
            }
            Text(offer.priceScope == "onward_party" ? "Onward flights · \(offer.partySize) \(offer.partySize == 1 ? "traveller" : "travellers")" : "\(offer.partySize) \(offer.partySize == 1 ? "traveller" : "travellers") · \(quotedTotal != nil ? "current selections included" : offer.requestedExtrasPriced == true ? "requested extras included" : "provider flight fare")").font(.caption).foregroundStyle(.secondary)
            ForEach(offer.itinerary.segments.filter { !$0.independentlyBooked }) { segment in FlightSegmentRow(segment: segment) }
            HStack(spacing: 6) { Image(systemName: "suitcase"); Text(quotedBaggage ?? offer.baggageSummary) }.font(.caption).foregroundStyle(.secondary)
            if offer.itinerary.overnight { Label("Includes overnight travel", systemImage: "moon").font(.caption) }
            if offer.itinerary.transferType != "direct" { Text(offer.itinerary.terms).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct FlightSegmentRow: View {
    var segment: V2FlightSegment
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(segment.direction == "return" ? "Return" : "Outbound") · \(segment.operatingCarrier) \(segment.flightNumber.map { "· " + $0 } ?? "")").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) { Text(segment.origin.code).font(.headline); Text(segment.departureText).font(.caption) }
                Spacer(minLength: 8)
                VStack(spacing: 5) { Image(systemName: "airplane").font(.caption).foregroundStyle(.secondary); Text("\(segment.durationMinutes / 60)h \(segment.durationMinutes % 60)m").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) { Text(segment.destination.code).font(.headline); Text(segment.arrivalText).font(.caption) }
            }
        }.accessibilityElement(children: .combine)
    }
}

func fieldTitle(_ field: String) -> String {
    ["outboundDate":"Departure", "returnDate":"Return", "budgetMinor":"Budget", "maxConnections":"Connections", "noOvernight":"Overnight travel", "arrivalDeadline":"Arrival time", "departureAfter":"Departure time", "dateWindow":"Date window"][field] ?? field
}

extension View {
    @ViewBuilder func tripNumberInput() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
