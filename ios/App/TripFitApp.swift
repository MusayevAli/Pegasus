import SwiftUI
import TripFitCore

@main struct TripFitApp: App {
    @State private var store: BookingStore
    @State private var booking: BookingV2Store
    @State private var memory: TravelProfileStore
    init() {
        let legacy = BookingStore()
        _store = State(initialValue: legacy)
        let booking = BookingV2Store(analytics: legacy.analytics)
        let memory = TravelProfileStore(analytics: legacy.analytics)
        booking.onConfirmedSearch = { [weak booking, weak memory] intent in
            guard let booking, let memory else { return }
            let provenance = booking.providerID == "sample" ? "sample_search" : "live_search"
            Task { await memory.record(intent: intent, kind: "confirmed_search", provenance: provenance) }
        }
        booking.onDemoOrder = { [weak memory] intent, selection in
            Task { await memory?.record(intent: intent, kind: "confirmed_trip", selection: selection, provenance: "demo_booking") }
        }
        _booking = State(initialValue: booking)
        _memory = State(initialValue: memory)
    }
    var body: some Scene {
        WindowGroup { BookingHomeRoot().environment(store).environment(booking).environment(memory).tint(TripTheme.ink).preferredColorScheme(.light)
            #if os(macOS)
            .frame(width: 430, height: 850)
            #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}

enum TripTheme {
    static let yellow = Color(red: 253/255, green: 203/255, blue: 10/255)
    static let ink = Color(red: 24/255, green: 25/255, blue: 24/255)
    static let canvas = Color.white
    static let card = Color(red: 246/255, green: 246/255, blue: 244/255)
    static let line = Color.black.opacity(0.08)
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(TripTheme.ink).frame(maxWidth: .infinity)
            .padding(.vertical, 17).padding(.horizontal, 18)
            .background(TripTheme.yellow.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 17))
    }
}
struct Panel<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 15) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(selected ? TripTheme.yellow.opacity(0.07) : TripTheme.card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? TripTheme.yellow : .clear, lineWidth: 2))
    }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
}
struct SectionTitle: View {
    var title: String; var subtitle: String? = nil
    var body: some View { VStack(alignment: .leading, spacing: 8) {
        Text(title).font(.system(.title2, design: .default, weight: .bold))
        if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    } }
}
struct InfoNote: View {
    var text: String; var symbol = "info.circle"
    var body: some View { Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
struct Pill: View {
    var text: String; var yellow = false
    var body: some View { Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7).background(yellow ? TripTheme.yellow : TripTheme.canvas, in: Capsule()) }
}
struct ChoiceRow: View {
    var title: String; var detail: String; var selected: Bool; var price: String? = nil; var action: () -> Void
    var body: some View { Button(action: action) { Panel(selected: selected) {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(selected ? TripTheme.ink : .secondary)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
            Spacer(minLength: 0)
            if let price { Text(price).font(.subheadline.weight(.semibold)).fixedSize() }
        }
    } }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []) }
}

struct TripFitRoot: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settings = false
    @State private var aiDesigner = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if store.step != .search { Button { store.back() } label: { Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44) }.accessibilityLabel("Go back") }
                HStack(spacing: 7) {
                    Image(systemName: "airplane").rotationEffect(.degrees(-25)).font(.headline).foregroundStyle(TripTheme.ink).frame(width: 30, height: 30).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 9))
                    Text("Pegasus").font(.subheadline.bold())
                    Text("TripFit").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { aiDesigner = true } label: { Image(systemName: "sparkles").font(.title3).frame(width: 40, height: 44) }.accessibilityLabel("Open AI Trip Designer")
                Button { settings = true } label: { Image(systemName: "person.crop.circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel("Demo settings and analytics")
            }.padding(.horizontal, 16).padding(.top, 5).background(.white)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    if store.step != .search && store.step != .confirmation && store.step != .trips {
                        HStack { Eyebrow(text: "Build your journey"); Spacer(); Pill(text: "DEMO", yellow: true) }
                        Text(store.step.title).font(.system(.largeTitle, design: .default, weight: .bold)).tracking(-1)
                        ProgressView(value: progress).tint(TripTheme.yellow).accessibilityLabel("Booking progress")
                    }
                    content
                }.padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: 680)
            }.id(store.step).background(TripTheme.canvas)
            if showBottomBar { bottomBar }
            if store.step == .search || store.step == .trips { tabBar }
        }
        .foregroundStyle(TripTheme.ink)
        .sheet(isPresented: $settings) { SettingsScreen().environment(store) }
        .sheet(isPresented: $aiDesigner) { AITripDesignerScreen().environment(store) }
        .alert("Let's check that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: phase) { _, new in store.analytics.setForeground(new == .active); store.persist() }
        .simultaneousGesture(TapGesture().onEnded { store.analytics.interact() })
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.step)
    }
    var progress: Double { switch store.step { case .search: 0; case .itinerary: 0.16; case .configuration: 0.3; case .baggage: 0.43; case .seats: 0.57; case .meals: 0.70; case .review: 0.85; default: 1 } }
    var showBottomBar: Bool { [.configuration,.baggage,.seats,.meals,.review].contains(store.step) && store.itinerary != nil }
    var tabBar: some View {
        HStack(spacing: 0) {
            tab("Explore", symbol: "square.grid.2x2", selected: store.step == .search) { store.navigate(.search) }
            tab("For You", symbol: "person.crop.square", selected: false) {
                if store.itinerary != nil { store.navigate(.configuration) } else { store.demo(.barcelonaFamily) }
            }
            tab("My Trips", symbol: "suitcase.rolling", selected: store.step == .trips) { store.navigate(.trips) }
        }.padding(.vertical, 10).background(.white).overlay(alignment: .top) { Divider() }
    }
    func tab(_ name: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: selected ? symbol + ".fill" : symbol).font(.system(size: 22)); Text(name).font(.caption2.weight(selected ? .semibold : .regular)) }
                .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(selected ? TripTheme.ink : .secondary)
                .background(alignment: .top) { if selected { Capsule().fill(TripTheme.yellow).frame(width: 42, height: 4).offset(y: -9) } }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder var content: some View {
        switch store.step {
        case .search: SearchScreen()
        case .itinerary: ResultsScreen()
        case .configuration: ConfigurationScreen()
        case .baggage: BaggageScreen()
        case .seats: SeatsScreen()
        case .meals: MealsScreen()
        case .review: ReviewScreen()
        case .checkout: CheckoutScreen()
        case .confirmation: ConfirmationScreen()
        case .trips: TripsScreen()
        }
    }
    var bottomBar: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) { Text(euros(store.total)).font(.title2.bold()).contentTransition(.numericText()); Text("Total for \(store.passengers.count) · EUR").font(.caption).foregroundStyle(.secondary) }
            Button(store.step == .review ? "Checkout" : "Continue") {
                let next: [BookingStep: BookingStep] = [.configuration:.baggage,.baggage:.seats,.seats:.meals,.meals:.review,.review:.checkout]
                if store.step == .review, let itinerary = store.itinerary {
                    let issues = Validation.review(request: store.request, itinerary: itinerary, selection: store.selection).filter { $0.severity == .error }
                    if !issues.isEmpty { store.error = issues.map(\.message).joined(separator: "\n"); store.analytics.emit("validation_error", "review.continue", ["code": .string(issues[0].id)]); return }
                }
                store.navigate(next[store.step] ?? .review)
            }.buttonStyle(PrimaryButtonStyle())
        }.padding(.horizontal, 22).padding(.vertical, 14).background(.white).overlay(alignment: .top) { Divider() }
    }
}

struct SettingsScreen: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var analytics = store.analytics
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("An honest prototype") { Text("All schedules, airline combinations, prices and purchases are illustrative. Live AI does not enable live inventory or ticket issuance.").font(.subheadline) }
                Section("Optional product analytics") {
                    Toggle("Share demo interactions", isOn: $analytics.enabled)
                        .onChange(of: analytics.enabled) { _, on in if on { analytics.view(store.step.rawValue); analytics.emit("search_submitted", "consent.start", ["partySize": .int(store.passengers.count)]) } }
                    Text("Pseudonymous screens, choices and time only. No names, typed notes, photos or payment details. Switch off to delete queued events.").font(.caption)
                    TextField("Backend URL", text: $analytics.baseURL).tripURLInput()
                    SecureField("Device ingest token (remote only)", text: $analytics.uploadToken)
                    Button("Sync queued events (\(analytics.queue.count))") { Task { await analytics.flush() } }.disabled(!analytics.enabled)
                    Text(analytics.status).font(.caption)
                }
                Section("AI connection") {
                    Label(store.aiConnection?.configured == true ? "Live AI configured" : "Live AI is not connected", systemImage: "sparkles")
                    if let connection = store.aiConnection { Text("Model: \(connection.model ?? "Server default")").font(.caption) }
                    Button("Check AI connection") { Task { await store.checkAIConnection() } }
                    Text("Configure OPENAI_API_KEY in the backend's .env file and restart the service. Keep API keys on the server.").font(.caption)
                    Text("The Trip Designer and packing scan send only what you explicitly submit. They work independently of analytics consent. Local previews are labelled whenever live AI is unavailable.").font(.caption)
                }
                Section("Demo controls") {
                    Button("Start a fresh booking") { store.reset(); dismiss() }
                    Button("Clear saved demo trips", role: .destructive) { store.trips = []; store.persist() }
                }
            }.navigationTitle("Demo settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.task { await store.checkAIConnection() }
        }
    }
}
