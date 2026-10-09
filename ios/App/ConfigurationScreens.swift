import SwiftUI
import PhotosUI
import TripFitCore

struct ConfigurationScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var extraPreferences = Set<String>()
    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 24) {
            AIEntryCard(compact: true)
            if store.canUndoAIPlan {
                Panel(selected: true) {
                    Label("Your tailored plan is applied", systemImage: "sparkles").font(.headline)
                    Text("\(euros(store.total)) for your party. Every choice below is still editable.").font(.subheadline)
                    Button("Undo AI plan") { store.undoAITripPlan() }.font(.subheadline.bold()).frame(minHeight: 44)
                }
            }
            Image(store.imageName).resizable().scaledToFill().frame(height: 195).clipped().clipShape(RoundedRectangle(cornerRadius: 25)).accessibilityHidden(true)
            SectionTitle(title: "A few things that matter to you.", subtitle: "We've already got your dates and travellers. These are optional, and you can change them anytime.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                needChip("Travel light", symbol: "backpack", selected: store.needs.travellingLight) { store.preference("light") { store.needs.travellingLight.toggle() } }
                needChip("Gifts on return", symbol: "gift", selected: store.needs.giftsOnReturn) { store.preference("gifts") { store.needs.giftsOnReturn.toggle() } }
                needChip("Stay together", symbol: "person.2", selected: store.needs.stayTogether) { store.preference("together") { store.needs.stayTogether.toggle() } }
                needChip("No alcohol", symbol: "cup.and.saucer", selected: store.needs.noAlcohol) { store.preference("noAlcohol") { store.needs.noAlcohol.toggle() } }
                ForEach(["Business", "Sports equipment", "Budget"], id: \.self) { title in
                    needChip(title, symbol: title == "Business" ? "briefcase" : title == "Budget" ? "eurosign.circle" : "figure.surfing", selected: extraPreferences.contains(title)) {
                        store.preference(title == "Business" ? "business" : title == "Budget" ? "budget" : "sports") {
                            if extraPreferences.contains(title) { extraPreferences.remove(title) } else { extraPreferences.insert(title) }
                            if title == "Sports equipment" { if extraPreferences.contains(title) { store.needs.packingItems.append("sports") } else { store.needs.packingItems.removeAll { $0 == "sports" } } }
                        }
                    }
                }
            }
            if extraPreferences.contains("Sports equipment") { InfoNote(text: "Sports equipment isn't sold in this demo catalogue. Confirm equipment rules directly with each carrier; a standard bag purchase does not cover it.", symbol: "exclamationmark.circle") }
            if extraPreferences.contains("Business") { InfoNote(text: "Compare More flexibility below if changeable plans matter to you. No upgrade is applied automatically.") }
            if extraPreferences.contains("Budget") { InfoNote(text: "Your recommendation compares the cheapest eligible combination for your confirmed needs, including keeping what you already have.") }
            if !store.needs.packingItems.isEmpty { Panel {
                Eyebrow(text: "Confirmed demo needs")
                ForEach(store.needs.packingItems, id: \.self) { item in Label(packingLabel(item), systemImage: "checkmark.circle").font(.subheadline) }
                Button("Clear confirmed packing needs") { store.preference("packing_clear") { store.needs.packingItems = [] } }.font(.caption.bold()).frame(minHeight: 44)
            } }
            RecommendationList()
            SectionTitle(title: "Choose your fare.", subtitle: "Demo bundles apply to every traveller on every Pegasus segment. Included items are never charged twice.")
            ForEach(FareBundle.allCases.filter { $0 != .family || store.passengers.contains(where: \.isChild) }) { bundle in
                ChoiceRow(title: bundle.title, detail: bundleDescription(bundle), selected: store.selection.bundle == bundle, price: bundleTotal(bundle)) { store.setBundle(bundle) }
            }
            InfoNote(text: "Prefer to decide later? Continue with your existing choices. Seating and meals are optional.")
        }
    }
    func bundleTotal(_ bundle: FareBundle) -> String {
        guard let itinerary = store.itinerary else { return "" }; var selection = store.selection; selection.bundle = bundle
        return euros(Pricing.quote(itinerary: itinerary, passengers: store.passengers, selection: selection).totalCents)
    }
    func needChip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 9).background(selected ? TripTheme.yellow : .white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(TripTheme.line)) }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
func bundleDescription(_ bundle: FareBundle) -> String {
    switch bundle {
    case .basic: "Keep the flight's existing allowance. Add only what you need."
    case .family: "20 kg checked bag, standard seat and one meal per traveller, per Pegasus flight. Family eligibility required."
    case .flex: "Checked bag, standard seat and one meal, plus demo change flexibility. Fare differences still apply."
    }
}
func packingLabel(_ item: String) -> String { ["checked-bag":"A checked bag for the journey", "checked-bag-each-way":"A checked bag for each traveller, both ways", "meals-each-flight":"A meal for each traveller, each flight", "clothes":"Clothes", "laptop":"Laptop", "gifts":"Gifts and souvenirs", "sports":"Sports equipment", "liquids":"Liquids" ][item] ?? item }

struct RecommendationList: View {
    @Environment(BookingStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(store.recommendations.filter { !store.dismissed.contains($0.id) }) { rec in
                Panel(selected: true) {
                    HStack { Label("A FIT FOR YOUR TRIP", systemImage: "sparkle").font(.caption.bold()); Spacer(); if rec.savingsCents > 0 { Pill(text: "Save \(euros(rec.savingsCents))", yellow: true) } }
                    Text(rec.title).font(.title3.bold())
                    Text(rec.explanation).font(.subheadline).foregroundStyle(.secondary)
                    HStack { Text("Proposed trip total").font(.subheadline); Spacer(); Text(euros(rec.totalCents)).font(.headline) }
                    if store.expanded.contains(rec.id) { Text("Based on the demo catalogue, your travellers, confirmed packing needs and current preferences. Review the new total before applying. This changes only this booking.").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if store.undoSelections[rec.id] != nil { Button("Undo change") { store.undo(rec) }.font(.headline) }
                        else { Button("Apply suggestion") { store.apply(rec) }.font(.headline) }
                        Spacer()
                        Button("Why?") { store.expand(rec) }.font(.subheadline)
                        Button { store.dismiss(rec) } label: { Image(systemName: "xmark").frame(width: 36, height: 44) }.accessibilityLabel("Dismiss recommendation")
                    }.frame(minHeight: 44)
                }.modifier(VisibleImpression { store.visible(rec) })
            }
        }
    }
}

/// Count an impression only after at least 40% of a card intersects the visible viewport.
private struct VisibleImpression: ViewModifier {
    var action: () -> Void
    @State private var recorded = false
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.onAppear { inspect(geometry.frame(in: .global)) }
                .onChange(of: geometry.frame(in: .global)) { _, frame in inspect(frame) }
        })
    }
    private func inspect(_ frame: CGRect) {
        let viewport = tripVisibleViewport()
        let visible = frame.intersection(viewport)
        guard !recorded, frame.height > 0, !visible.isNull, visible.height / frame.height >= 0.4 else { return }
        recorded = true; action()
    }
}

struct BaggageScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var passengerID = "adult-1"
    @State private var segmentID = ""
    @State private var packing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "Pack for the way you travel.", subtitle: "Choose for each traveller and flight. A purchase with one airline never changes another airline's allowance.")
            if store.request.destination == "BCN" {
                Panel(selected: store.needs.giftsOnReturn) {
                    Text("Planning to bring food, gifts or souvenirs back?").font(.title3.bold())
                    HStack {
                        Button("Yes, leave some room") { store.preference("gifts") { store.needs.giftsOnReturn = true } }.buttonStyle(.borderedProminent).tint(TripTheme.yellow)
                        Button("Not this time") { store.preference("gifts") { store.needs.giftsOnReturn = false } }.buttonStyle(.bordered)
                    }
                    Text("Suggestions update below. Your selected bags stay exactly as you chose them.").font(.caption).foregroundStyle(.secondary)
                }
            }
            RecommendationList()
            assignmentPickers
            if let segment = segment {
                let allowance = Baggage.allowance(passengerID: passengerID, segment: segment, selection: store.selection)
                Panel {
                    HStack { Image(systemName: "backpack.fill").font(.system(size: 48)).foregroundStyle(TripTheme.yellow); VStack(alignment: .leading, spacing: 6) { Text("Your current allowance").font(.headline); Text(allowance.summary).font(.subheadline) } }
                    Text("Underseat: \(allowance.underseat.dimensions?.label ?? "See carrier rules") · \(allowance.underseat.totalWeightKG) kg").font(.caption).foregroundStyle(.secondary)
                    if let checked = allowance.checked { Text("Checked: \(checked.label), max \(checked.maxPieceWeightKG) kg per piece, \(checked.maxLinearCM ?? 158) cm linear dimensions.").font(.caption) }
                    Text("No pooling between travellers. Your fare bundle may include additional allowance.").font(.caption).foregroundStyle(.secondary)
                    Button("Keep only my included allowance") { store.setBag(nil, passenger: passengerID, segment: segment.id) }.frame(minHeight: 44)
                }
                if segment.isPegasus {
                    ForEach(Catalog.baggageProducts) { bag in
                        let selected = store.selection.extras.contains { $0.passengerID == passengerID && $0.segmentID == segment.id && $0.productID == bag.id }
                        ChoiceRow(title: bag.name, detail: "\(bag.description)\n\(bag.allowance.label) · max \(bag.allowance.maxPieceWeightKG) kg per piece", selected: selected, price: bagDelta(bag, segment: segment)) {
                            if selected { store.removeBag(bag.id, passenger: passengerID, segment: segment.id) }
                            else { store.setBag(bag.id, passenger: passengerID, segment: segment.id) }
                        }
                    }
                } else { InfoNote(text: "Incoming airline bags are included as shown. This demo does not sell extras for the incoming carrier.") }
            }
            Button { packing = true } label: { Panel { HStack { Image(systemName: "camera.viewfinder").font(.largeTitle); VStack(alignment: .leading, spacing: 5) { Text("Show us what you're packing.").font(.headline); Text("Photo or a quick checklist. Always optional.").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
        }.onAppear { if segmentID.isEmpty { segmentID = store.itinerary?.segments.first?.id ?? "" } }
            .sheet(isPresented: $packing) { PackingScreen().environment(store) }
    }
    var segment: Segment? { store.itinerary?.segments.first { $0.id == segmentID } }
    var assignmentPickers: some View { Panel {
        Picker("Traveller", selection: $passengerID) { ForEach(store.passengers) { Text($0.displayName).tag($0.id) } }
        Picker("Flight", selection: $segmentID) { ForEach(store.itinerary?.segments ?? []) { Text("\($0.direction.title) · \($0.origin)–\($0.destination) · \($0.carrier)").tag($0.id) } }
    } }
    func bagDelta(_ bag: BaggageProduct, segment: Segment) -> String {
        guard let itinerary = store.itinerary else { return "" }
        if store.selection.extras.contains(where: { $0.passengerID == passengerID && $0.segmentID == segment.id && $0.productID == bag.id }) {
            let price = Pricing.extraPrice(product: bag, segment: segment, bundle: store.selection.bundle)
            return price == 0 ? "Included" : euros(price)
        }
        var selection = store.selection
        let ids = Set(Catalog.baggageProducts.filter { $0.kind == bag.kind }.map(\.id))
        selection.extras.removeAll { $0.passengerID == passengerID && $0.segmentID == segment.id && ids.contains($0.productID) }
        selection.extras.append(ExtraSelection(passengerID: passengerID, segmentID: segment.id, productID: bag.id))
        let delta = Pricing.quote(itinerary: itinerary, passengers: store.passengers, selection: selection).totalCents - store.total
        return delta == 0 ? "Included" : (delta > 0 ? "+" : "") + euros(delta)
    }
}

struct PackingScreen: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var candidates = Set<String>()
    @State private var busy = false
    @State private var source = "Manual checklist · you know your bag best"
    @State private var analysis: PackingResponse?
    @State private var photoRevision = UUID()
    private let items = ["clothes", "laptop", "gifts", "sports", "liquids"]
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 22) {
                HStack { Image(systemName: "viewfinder").font(.system(size: 32)).frame(width: 64, height: 64).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 21)); Spacer(); Pill(text: "AI PACKING COACH") }
                Text("Pack with a little\nmore confidence.").font(.largeTitle.bold()).tracking(-1)
                Text("AI spots possible items in your photo. You confirm the list and decide what goes in your bag.").foregroundStyle(.secondary)
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose a packing photo", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, minHeight: 50) }.buttonStyle(.bordered)
                if let imageData { PackingPhoto(data: imageData).frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 20)) }
                Button { Task { await analyse() } } label: { Label("Analyze my packing photo", systemImage: "sparkles") }.buttonStyle(PrimaryButtonStyle()).disabled(busy || imageData == nil)
                Text("The photo is sent only when you tap Analyze. Live analysis requires the connected AI service.").font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView("Looking for item categories…") }
                Text(source).font(.caption).foregroundStyle(.secondary)
                if let analysis, analysis.source == "openai" {
                    Panel(selected: true) {
                        Label("AI spotted these possibilities", systemImage: "sparkles").font(.headline)
                        if let summary = analysis.summary { Text(summary).font(.subheadline) }
                        ForEach(Array((analysis.items ?? []).enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top) { Text(item.label).font(.subheadline); Spacer(); Text("\(item.confidence.capitalized) confidence").font(.caption).foregroundStyle(.secondary) }
                        }
                        ForEach(analysis.questions ?? [], id: \.self) { question in Text(question).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                SectionTitle(title: "Confirm your packing list.", subtitle: "Correct any suggestion, or use the checklist on its own.")
                ForEach(items, id: \.self) { item in Toggle(packingLabel(item), isOn: Binding(get: { candidates.contains(item) }, set: { if $0 { candidates.insert(item) } else { candidates.remove(item) } })) }
                InfoNote(text: "Photos cannot reliably measure weight or dimensions. Check those yourself; sports and liquid restrictions need a separate carrier check.")
                Button("Confirm my packing needs") {
                    store.preference("packing_confirmed") {
                        store.needs.packingItems = store.needs.packingItems.filter { !AIPlanner.packingCategories.contains($0) } + candidates.sorted()
                        if candidates.contains("gifts") { store.needs.giftsOnReturn = true }
                    }
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle())
            }.padding(24) }.navigationTitle("AI Packing Coach").tripInlineTitle().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.onChange(of: photo) { _, item in
            let requestID = UUID(); photoRevision = requestID; analysis = nil; imageData = nil
            Task { let data = try? await item?.loadTransferable(type: Data.self); guard requestID == photoRevision else { return }; imageData = data; source = data == nil ? "Couldn't open that photo. Try another or use the checklist." : "Photo ready · tap Analyze to send it to the AI service" }
        }
            .onAppear { candidates = Set(store.needs.packingItems.filter { items.contains($0) }) }
    }
    func analyse() async {
        guard let imageData, let jpeg = packingJPEG(imageData), jpeg.count < 3_000_000 else { source = "Photo too large. Please use the checklist."; return }
        busy = true; defer { busy = false }; let revision = store.revision; let requestedPhoto = photoRevision
        do {
            let response = try await BackendAPI(baseURL: store.analytics.baseURL, token: store.analytics.uploadToken).post("/api/ai/packing", body: ["revision": revision, "imageBase64": jpeg.base64EncodedString(), "mimeType": "image/jpeg"], as: PackingResponse.self)
            guard response.revision == store.revision, requestedPhoto == photoRevision else { source = "Your trip or photo changed. Analyze the current photo again."; return }
            analysis = response
            if response.source == "openai" { candidates = Set(response.candidates.filter { items.contains($0) }); source = "AI analysis complete · review the suggestions below" }
            else { source = response.notice ?? "Live AI is not connected. Your photo was not analyzed. Use the checklist or connect the service." }
        } catch { source = "AI unavailable. The manual checklist is ready." }
    }
}
