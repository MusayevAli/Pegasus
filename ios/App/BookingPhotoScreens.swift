import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
#endif

struct BookingPackingScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var camera = false
    @State private var photoGeneration = UUID()
    @State private var items: [V2PackingItem] = []
    @State private var confirmedItems = false
    @State private var passengerID = ""
    @State private var direction = "outbound"
    @State private var pieces = 1
    @State private var weight = ""
    @State private var largestWeight = ""
    @State private var length = ""
    @State private var width = ""
    @State private var height = ""
    @State private var measurements: [V2PackingMeasurement] = []
    @State private var category = "clothes"
    @State private var photoError: String?
    @State private var loadingPhoto = false
    @State private var visibleViewport = CGRect.zero
    @State private var visibleRecommendations = Set<String>()
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 23) {
                Text("What are you packing?").font(.largeTitle.bold()).tracking(-1)
                Text("Show your items. Choose only the space you need.").font(.subheadline).foregroundStyle(.secondary)
                photoControls
                if loadingPhoto { ProgressView("Loading your photo…") }
                if let imageData { PackingPhoto(data: imageData).frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 18)) }
                if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
                if imageData != nil {
                    Button { if let imageData { Task { await booking.analysePacking(imageData) } } } label: { HStack { if booking.aiBusy { ProgressView() }; Text(booking.aiBusy ? "Looking at your items…" : "Identify visible items") } }.buttonStyle(PrimaryButtonStyle()).disabled(booking.aiBusy)
                    Text("Only this selected photo is sent for analysis.").font(.caption).foregroundStyle(.secondary)
                }
                if let assessment = booking.packingAssessment {
                    Text(assessment.summary).font(.headline)
                    if !assessment.uncertainties.isEmpty { Text(assessment.uncertainties.joined(separator: " ")).font(.caption).foregroundStyle(.secondary) }
                }
                if let error = booking.error { HStack { Text(error).font(.subheadline); Spacer(); if let imageData { Button("Retry") { Task { await booking.analysePacking(imageData) } } } } }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your visible items").font(.title3.bold())
                        ForEach(items.indices, id: \.self) { index in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField("Item", text: $items[index].label).font(.subheadline.bold())
                                    Text("\(items[index].confidence.capitalized) confidence · approximate count").font(.caption2).foregroundStyle(.secondary)
                                    Stepper(items[index].visibleCount.map { "\($0) visible" } ?? "Count uncertain", value: Binding(get: { items[index].visibleCount ?? 0 }, set: { items[index].visibleCount = $0 == 0 ? nil : $0; confirmedItems = false }), in: 0...30).font(.caption)
                                }
                                Button { items.remove(at: index); confirmedItems = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 44) }.accessibilityLabel("Remove \(items[index].label)")
                            }
                            if index < items.count - 1 { Divider() }
                        }
                        Toggle("This list matches my packing", isOn: $confirmedItems).font(.subheadline).tint(TripTheme.ink)
                    }.padding(18).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 20))
                }
                HStack {
                    Picker("Add an item", selection: $category) { ForEach(["clothes", "laptop", "gifts", "sports", "liquids", "bag"], id: \.self) { Text($0.capitalized).tag($0) } }.labelsHidden()
                    Spacer()
                    Button("Add item") { items.append(V2PackingItem(id: UUID().uuidString, category: category, label: category.capitalized, visibleCount: 1, confidence: "high")); confirmedItems = false }.font(.subheadline.bold()).frame(minHeight: 44)
                }
                if booking.selectedOffer?.effectiveCapabilities.ancillaries == true {
                Panel {
                    Text("Check the bag, too.").font(.title3.bold())
                    Text("A photo cannot measure weight or size. Enter your measurements to compare eligible options.").font(.caption).foregroundStyle(.secondary)
                    Picker("Traveller", selection: Binding(get: { activePassengerID }, set: { passengerID = $0 })) { ForEach(booking.passengers) { Text(passengerLabel($0)).tag($0.id) } }
                    Picker("Direction", selection: $direction) { Text("Outbound").tag("outbound"); if booking.intent.tripType == "round_trip" { Text("Return").tag("return") } }.pickerStyle(.segmented)
                    Stepper("\(pieces) bag\(pieces == 1 ? "" : "s")", value: $pieces, in: 1...3)
                    measurementField("Total weight · kg", text: $weight)
                    if pieces > 1 { measurementField("Heaviest bag · kg", text: $largestWeight) }
                    Text("Largest piece · centimetres").font(.caption).foregroundStyle(.secondary)
                    HStack { measureBox("Length", text: $length); measureBox("Width", text: $width); measureBox("Height", text: $height) }
                    Button("Confirm these measurements") { saveMeasurement() }.font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44).disabled(currentMeasurement == nil)
                    ForEach(measurements) { measurement in
                        HStack(alignment: .top) { Text("\(measurement.passengerId) · \(measurement.direction) · \(measurement.pieces) bags · \(measurement.totalWeightKg) kg").font(.caption); Spacer(); Button { measurements.removeAll { $0.id == measurement.id } } label: { Image(systemName: "xmark.circle").frame(minWidth: 32, minHeight: 32) }.accessibilityLabel("Remove measurements") }
                    }
                    if booking.intent.tripType == "round_trip" { Text("Bringing things home? Add separate return measurements. We won't change outbound bags.").font(.caption).foregroundStyle(.secondary) }
                }
                Button { Task { await booking.loadPackingOptions(measurements: measurements, items: items) } } label: { HStack { if booking.busy { ProgressView() }; Text("Compare baggage options") } }.buttonStyle(PrimaryButtonStyle()).disabled(measurements.isEmpty || (!items.isEmpty && !confirmedItems) || booking.busy)
                ForEach(booking.packingQuestions, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(booking.packingOptions) { option in
                    Panel {
                        HStack(alignment: .top) { Text(option.title).font(.headline); Spacer(); Text(option.total.formatted).font(.title3.bold()) }
                        Text(option.explanation).font(.subheadline).foregroundStyle(.secondary)
                        Text(option.differenceMinor == 0 ? "Same trip total" : option.differenceMinor < 0 ? "Save \(V2Money(amountMinor: -option.differenceMinor).formatted)" : "+\(V2Money(amountMinor: option.differenceMinor).formatted) to your trip").font(.caption.bold())
                        Button(option.action == "keep" ? "Keep this allowance" : "Choose this option") { Task { await booking.applyPackingOption(option); if booking.error == nil { dismiss() } } }.buttonStyle(PrimaryButtonStyle()).disabled(booking.busy)
                    }
                    .background { GeometryReader { proxy in Color.clear.preference(key: PackingVisibleFrames.self, value: [option.id: proxy.frame(in: .global)]) } }
                }
                if booking.canUndoPacking { Button("Undo last baggage change") { Task { await booking.undoPackingOption() } }.frame(minHeight: 44) }
                } else {
                    InfoNote(text: "Your item list helps you plan. Pegasus confirms bag dimensions, weight limits and baggage prices during booking. A photo cannot measure size or weight.")
                }
            }.padding(24) }
            .background { GeometryReader { proxy in Color.clear.onChange(of: proxy.frame(in: .global), initial: true) { _, rect in visibleViewport = rect } } }
            .onPreferenceChange(PackingVisibleFrames.self) { frames in
                guard booking.analytics.enabled, scenePhase == .active else { return }
                for (id, rect) in frames where rect.height > 0 && rect.intersection(visibleViewport).height >= min(rect.height / 2, 120) {
                    let key = "\(booking.intent.revision):\(id)"
                    if visibleRecommendations.insert(key).inserted { booking.analytics.emit("recommendation_visible", "baggage.packing", ["recommendationId": .string(id), "recommendationType": .string("baggage"), "recommendationVersion": .int(booking.intent.revision)]) }
                }
            }
            .navigationTitle("Packing").tripInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: photo) { _, item in
            let generation = UUID(); photoGeneration = generation; booking.cancelPhotoRequests(); imageData = nil; booking.packingOptions = []; items = []; confirmedItems = false; photoError = nil; loadingPhoto = item != nil
            Task {
                guard let item else { return }
                let data = try? await item.loadTransferable(type: Data.self)
                guard generation == photoGeneration else { return }
                loadingPhoto = false
                guard let data, let jpeg = packingJPEG(data) else { photoError = "This photo could not be opened. Try a different photo or download it from iCloud first."; return }
                imageData = jpeg; photoError = nil
            }
        }
        .onChange(of: booking.packingAssessment?.requestId) { _, _ in items = booking.packingAssessment?.items ?? []; confirmedItems = false }
        .onChange(of: items) { _, _ in confirmedItems = false; booking.cancelPackingOptions() }
        .onChange(of: measurements) { _, _ in booking.cancelPackingOptions() }
        .onChange(of: [weight, largestWeight, length, width, height, String(pieces)]) { _, _ in
            measurements.removeAll { $0.passengerId == activePassengerID && $0.direction == direction }
            booking.cancelPackingOptions()
        }

        .onAppear { booking.cancelPhotoRequests(); booking.packingOptions = [] }
        .onDisappear { photoGeneration = UUID(); booking.cancelPhotoRequests() }
        #if os(iOS)
        .sheet(isPresented: $camera) { TripCameraPicker { data in photoGeneration = UUID(); booking.cancelPhotoRequests(); imageData = data; booking.packingOptions = []; items = []; confirmedItems = false } }
        #endif
    }
    private var activePassengerID: String { booking.passengers.contains { $0.id == passengerID } ? passengerID : booking.passengers.first?.id ?? "" }
    private var currentMeasurement: V2PackingMeasurement? {
        guard let w = Int(weight), let l = Int(length), let d = Int(width), let h = Int(height), w > 0, w <= 100, [l,d,h].allSatisfy({ $0 > 0 && $0 < 300 }) else { return nil }
        let maxWeight = pieces == 1 ? w : Int(largestWeight) ?? 0
        guard maxWeight > 0, maxWeight <= w else { return nil }
        return V2PackingMeasurement(passengerId: activePassengerID, direction: direction, pieces: pieces, totalWeightKg: w, maxPieceWeightKg: maxWeight, maxLinearCm: l+d+h, dimensionsCm: [l,d,h])
    }
    private func saveMeasurement() { guard let value = currentMeasurement else { return }; measurements.removeAll { $0.id == value.id }; measurements.append(value); booking.packingOptions = [] }
    private var photoControls: some View {
        HStack {
            PhotosPicker(selection: $photo, matching: .images) { Label("Photo library", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Label("Camera", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered) }
            #endif
        }
    }
    private func measurementField(_ title: String, text: Binding<String>) -> some View { HStack { Text(title).font(.subheadline); Spacer(); TextField("Required", text: text).accessibilityLabel(title).multilineTextAlignment(.trailing).tripNumberInput().frame(width: 100) } }
    private func measureBox(_ title: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption2); TextField("cm", text: text).accessibilityLabel("\(title) in centimetres").tripNumberInput().padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10)) } }
}

struct TripImportScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var draft: V2TripImport?
    @State private var buffer = 180
    @State private var confirmed = false
    @State private var generation = UUID()
    @State private var loadingPhoto = false
    @State private var photoError: String?
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 23) {
                Text("Your plans.\nYour next flight.").font(.largeTitle.bold()).tracking(-1)
                Text("Import an event, a stay or an incoming flight. Confirm the details before they shape your search.").font(.subheadline).foregroundStyle(.secondary)
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose screenshot", systemImage: "photo.badge.plus").frame(maxWidth: .infinity, minHeight: 50) }.buttonStyle(.bordered)
                if loadingPhoto { ProgressView("Loading your screenshot…") }
                if let photoError { Text(photoError).font(.subheadline).foregroundStyle(.secondary) }
                if let imageData { PackingPhoto(data: imageData).frame(maxHeight: 210).clipShape(RoundedRectangle(cornerRadius: 18)) }
                if imageData != nil {
                    Button { if let imageData { Task { await booking.importTrip(imageData) } } } label: { HStack { if booking.aiBusy { ProgressView() }; Text(booking.aiBusy ? "Reading the details…" : "Extract trip details") } }.buttonStyle(PrimaryButtonStyle()).disabled(booking.aiBusy)
                    Text("Only the selected screenshot is sent for extraction.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = booking.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                if let value = draft {
                    Panel {
                        Text("Confirm what we found.").font(.title3.bold())
                        Picker("Use as", selection: Binding(get: { draft?.kind ?? "unknown" }, set: { kind in
                            draft?.kind = kind; confirmed = false
                            if kind == "incoming_flight" && draft?.incomingFlight == nil { draft?.incomingFlight = V2IncomingFlight(airline: "", arrivalAirport: "", arrivalAt: ""); buffer = max(60, buffer) }
                            if kind != "incoming_flight" { draft?.incomingFlight = nil }
                        })) { Text("Event or stay").tag("event"); Text("Incoming flight").tag("incoming_flight"); if value.kind == "unknown" { Text("Choose type").tag("unknown") } }
                        if value.kind == "incoming_flight", value.incomingFlight != nil { incomingFields }
                        else { eventFields }
                        ForEach(value.unresolved) { field in Text(field.question).font(.caption).foregroundStyle(.secondary) }
                        Stepper(value.kind == "incoming_flight" ? "Connection buffer: \(buffer) min" : "Airport arrival buffer: \(buffer) min", value: $buffer, in: (value.kind == "incoming_flight" ? 60 : 30)...1440, step: 30).font(.subheadline)
                        Text(value.kind == "incoming_flight" ? "A time buffer is not connection protection. Verify baggage reclaim, entry requirements and check-in deadlines." : "Your estimate must include travel from the airport to the venue. Airport arrival is not venue arrival.").font(.caption).foregroundStyle(.secondary)
                        Toggle("These details are correct", isOn: $confirmed).font(.subheadline).tint(TripTheme.ink)
                    }
                    Button("Use in my flight search") {
                        guard var imported = draft else { return }
                        guard confirmed else { return }
                        imported.unresolved = []
                        if imported.kind == "incoming_flight" { imported.incomingFlight?.confirmed = true; imported.incomingFlight?.minimumConnectionMinutes = buffer }
                        Task { await booking.applyImport(imported, bufferMinutes: buffer); if booking.error == nil { dismiss() } }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!confirmed || booking.busy || value.kind == "unknown")
                }
            }.padding(24) }.navigationTitle("Import screenshot").tripInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: photo) { _, item in
            let current = UUID(); generation = current; booking.cancelPhotoRequests(); imageData = nil; draft = nil; confirmed = false; photoError = nil; loadingPhoto = item != nil
            Task {
                guard let item else { return }
                let data = try? await item.loadTransferable(type: Data.self)
                guard generation == current else { return }
                loadingPhoto = false
                guard let data, let jpeg = packingJPEG(data) else { photoError = "This screenshot could not be opened. Try another image or download it from iCloud first."; return }
                imageData = jpeg
            }
        }
        .onChange(of: booking.tripImport?.requestId) { _, _ in draft = booking.tripImport; buffer = booking.tripImport?.suggestedArrivalBufferMinutes ?? 180; confirmed = false }
        .onAppear { booking.cancelPhotoRequests() }
        .onDisappear { generation = UUID(); booking.cancelPhotoRequests() }
    }
    private var eventFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Event or stay", text: optionalBinding(\.title))
            TextField("City / venue", text: optionalBinding(\.location))
            Picker("Arrival airport", selection: Binding(get: { draft?.airportCandidates.first ?? "" }, set: { draft?.airportCandidates = $0.isEmpty ? [] : [$0]; confirmed = false })) { Text("Confirm airport").tag(""); ForEach(booking.airports) { Text("\($0.city) · \($0.code)").tag($0.code) } }
            TextField("Date · YYYY-MM-DD", text: Binding(get: { draft?.localDate ?? "" }, set: { value in draft?.localDate = value; draft?.year = Int(value.prefix(4)); confirmed = false })).autocorrectionDisabled()
            TextField("Local event time · HH:mm", text: optionalBinding(\.localTime)).autocorrectionDisabled()
            Picker("Event time zone", selection: optionalBinding(\.timeZone)) { Text("Confirm time zone").tag(""); ForEach(Array(Set(booking.airports.map(\.timeZone))).sorted(), id: \.self) { Text($0).tag($0) } }
        }.font(.subheadline)
    }
    private var incomingFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Operating airline", text: Binding(get: { draft?.incomingFlight?.airline ?? "" }, set: { draft?.incomingFlight?.airline = $0; confirmed = false }))
            TextField("Flight number", text: Binding(get: { draft?.incomingFlight?.flightNumber ?? "" }, set: { draft?.incomingFlight?.flightNumber = $0; confirmed = false }))
            Picker("Arrival airport", selection: Binding(get: { draft?.incomingFlight?.arrivalAirport ?? "" }, set: { draft?.incomingFlight?.arrivalAirport = $0; confirmed = false })) { Text("Confirm airport").tag(""); ForEach(booking.airports) { Text("\($0.city) · \($0.code)").tag($0.code) } }
            DatePicker("Local arrival", selection: Binding(get: { V2Dates.instant(draft?.incomingFlight?.arrivalAt ?? "") ?? Date() }, set: { draft?.incomingFlight?.arrivalAt = ISO8601DateFormatter().string(from: $0); confirmed = false }), displayedComponents: [.date, .hourAndMinute])
                .environment(\.timeZone, TimeZone(identifier: booking.airports.first { $0.code == draft?.incomingFlight?.arrivalAirport }?.timeZone ?? "UTC") ?? .gmt)
            Text("Time zone: \(booking.airports.first { $0.code == draft?.incomingFlight?.arrivalAirport }?.timeZone ?? "Choose airport")").font(.caption).foregroundStyle(.secondary)
            Toggle("Collect and re-check baggage", isOn: Binding(get: { draft?.incomingFlight?.baggageReclaim ?? true }, set: { draft?.incomingFlight?.baggageReclaim = $0; confirmed = false }))
            Text("The incoming flight is already booked and won't be charged again.").font(.caption).foregroundStyle(.secondary)
        }.font(.subheadline)
    }
    private func optionalBinding(_ key: WritableKeyPath<V2TripImport, String?>) -> Binding<String> { Binding(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0.isEmpty ? nil : $0; confirmed = false }) }
    private func stringBinding(_ key: WritableKeyPath<V2TripImport, String>) -> Binding<String> { Binding(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0; confirmed = false }) }
}

#if os(iOS)
struct TripCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (Data) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera; controller.cameraCaptureMode = .photo; controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: TripCameraPicker
        init(parent: TripCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8), let resized = packingJPEG(data) { parent.onCapture(resized) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif

private struct PackingVisibleFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
