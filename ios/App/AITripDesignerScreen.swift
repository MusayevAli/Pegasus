import SwiftUI
import TripFitCore

struct AIEntryCard: View {
    @State private var presented = false
    var compact = false
    var body: some View {
        Button { presented = true } label: {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 25, weight: .medium))
                    .frame(width: 54, height: 54).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 5) {
                    Text("AI Trip Designer").font(.headline)
                    Text(compact ? "Describe your needs. Preview your fit." : "A few words. A trip made for you.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.headline)
            }.padding(19).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 23))
        }.buttonStyle(.plain).accessibilityLabel("Open AI Trip Designer")
            .sheet(isPresented: $presented) { AITripDesignerScreen() }
    }
}

struct AITripDesignerScreen: View {
    @Environment(BookingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var journey: DemoJourney = .barcelonaFamily
    @State private var draft: AITripPlan?
    @State private var settings = false
    @State private var packing = false
    @State private var applied = false
    @State private var viewedPlanIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        introduction
                        context
                        if applied { appliedCard }
                        input
                        if let draft {
                            planCard(draft).id("plan").onAppear {
                                if viewedPlanIDs.insert(draft.id).inserted {
                                    store.analytics.emit("recommendation_visible", "trip_designer.plan", ["recommendationId": .string(draft.id), "recommendationType": .string("bundle")])
                                }
                            }
                        } else if store.aiPlanBusy {
                            Panel {
                                ProgressView("Understanding your trip…")
                                Text("Finding the right preferences. Your booking stays unchanged.").font(.footnote).foregroundStyle(.secondary)
                            }.id("plan")
                        } else if !store.aiPlanStatus.isEmpty {
                            Text(store.aiPlanStatus).font(.footnote).foregroundStyle(.secondary)
                        }
                    }.padding(24).frame(maxWidth: 680)
                }
                .onChange(of: store.aiPlanBusy) { _, busy in
                    if !busy, let plan = store.aiTripPlan { draft = plan; withAnimation { scroll.scrollTo("plan", anchor: .top) } }
                }
            }
            .navigationTitle("AI Trip Designer").tripInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .background(.white).foregroundStyle(TripTheme.ink)
            .task { note = store.needs.note; await store.checkAIConnection() }
            .sheet(isPresented: $settings, onDismiss: { Task { await store.checkAIConnection() } }) { SettingsScreen() }
            .sheet(isPresented: $packing, onDismiss: addPackingContext) { PackingScreen() }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "sparkles").font(.system(size: 30)).frame(width: 64, height: 64).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 21))
                Spacer()
                Label(store.aiConnection?.configured == true ? "AI configured" : "Local preview available", systemImage: store.aiConnection?.configured == true ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text("Your trip.\nThought through.").font(.system(.largeTitle, weight: .bold)).tracking(-1)
            Text("Tell us what matters. Get an editable plan for bags, seats and meals—with the price before you choose.")
                .font(.subheadline).foregroundStyle(.secondary)
            if store.aiConnection?.configured != true {
                Button { settings = true } label: { Label("Connect live AI", systemImage: "network").font(.subheadline.weight(.semibold)) }.frame(minHeight: 44)
            }
        }
    }

    private var context: some View {
        Panel {
            Eyebrow(text: "YOUR JOURNEY")
            if let itinerary = store.itinerary, store.completedTrip == nil {
                Text(itinerary.title).font(.headline)
                Text("\(store.passengers.count) travellers · \(store.request.nights == 0 ? "One way" : "\(store.request.nights) nights") · Current total \(euros(store.total))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Demo journey", selection: $journey) { ForEach(DemoJourney.allCases) { Text($0.title).tag($0) } }
                Text("Choose a journey from our demo catalogue. Dates and travellers are editable in Search.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 14) {
            Panel {
                Text("What would make this trip better?").font(.headline)
                TextField("We want to sit together, bring checked bags and leave room for gifts on the way home…", text: $note, axis: .vertical)
                    .lineLimit(4...7).font(.body).accessibilityLabel("Describe your trip needs")
                    .onChange(of: note) { _, text in if text.count > 600 { note = String(text.prefix(600)) } }
                HStack {
                    Button { packing = true } label: { Label("Start with a photo", systemImage: "camera").font(.subheadline.weight(.medium)) }
                    Spacer()
                    Text("\(note.count)/600").font(.caption2).foregroundStyle(.secondary)
                }.frame(minHeight: 44)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    prompt("Family & gifts", note: "We need checked bags and meals for everyone on each flight, seats together and space for gifts on the return. No alcohol.")
                    prompt("Just a backpack", note: "I am travelling light with one small backpack. No checked bags and no meals. Keep my existing seat choices.")
                    prompt("Vegetarian trip", note: "We want vegetarian meals for the adults on each flight and seats together. Keep our current baggage choices.")
                }
            }
            Button { generate() } label: {
                HStack { if store.aiPlanBusy { ProgressView() } else { Image(systemName: "sparkles") }; Text(store.aiConnection?.configured == true ? "Create my AI plan" : "Preview my trip plan") }
            }.buttonStyle(PrimaryButtonStyle()).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.aiPlanBusy)
            Text("When you tap, your note and trip context go to your configured service. With live AI connected, OpenAI interprets your needs. You review every change.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func prompt(_ label: String, note value: String) -> some View {
        Button(label) { note = value; applied = false }.font(.caption.weight(.semibold))
            .padding(.horizontal, 13).frame(minHeight: 44).background(TripTheme.card, in: Capsule()).buttonStyle(.plain)
    }

    private func planCard(_ plan: AITripPlan) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Panel(selected: true) {
                Label(plan.source == "openai" ? "AI PERSONALIZED PLAN" : "LOCAL RULES PREVIEW", systemImage: "sparkles").font(.caption.bold())
                Text(plan.summary).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if plan.source != "openai" { Text(plan.notice).font(.footnote).foregroundStyle(.secondary) }
                Text("Review what we understood.").font(.headline)
                Text("Unmentioned preferences stay as they are. Edit any preference before applying.").font(.caption).foregroundStyle(.secondary)
                preference("Travel light", key: \.travellingLight, fallback: store.needs.travellingLight)
                preference("Checked bag for each traveller, every flight", key: \.checkedBagEachWay, fallback: store.needs.packingItems.contains("checked-bag-each-way"))
                preference("Room for gifts on the return", key: \.giftsOnReturn, fallback: store.needs.giftsOnReturn)
                preference("Sit together", key: \.stayTogether, fallback: store.needs.stayTogether)
                preference("Meals for each traveller, every flight", key: \.mealsEachFlight, fallback: store.needs.packingItems.contains("meals-each-flight"))
                preference("Vegetarian meals for adults", key: \.vegetarian, fallback: store.needs.packingItems.contains("vegetarian"))
                preference("No alcohol", key: \.noAlcohol, fallback: store.needs.noAlcohol)
            }
            ForEach(plan.clarifications, id: \.id) { clarification in
                Panel {
                    Text(clarification.question).font(.headline)
                    ForEach(clarification.choices, id: \.self) { choice in
                        Button(choiceTitle(choice)) { clarify(choice, questionID: clarification.id) }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }
                }
            }
            if plan.needs.travellingLight == true && (plan.needs.checkedBagEachWay == true || plan.needs.giftsOnReturn == true) {
                InfoNote(text: "Choose light travel or extra room for checked bags and return gifts. Update the preferences above to compare a consistent plan.", symbol: "slider.horizontal.3")
            } else if let proposal = store.proposal(for: plan) {
                let hasChanges = proposal.selection != store.selection || proposal.needs != store.needs
                Panel {
                    Eyebrow(text: "YOUR PLAN, PRICED")
                    HStack(alignment: .firstTextBaseline) {
                        Text(euros(proposal.totalCents)).font(.system(.largeTitle, weight: .bold))
                        Spacer()
                        Text(proposal.deltaCents == 0 ? "Same total" : proposal.deltaCents < 0 ? "Save \(euros(-proposal.deltaCents))" : "+\(euros(proposal.deltaCents))")
                            .font(.subheadline.bold())
                    }
                    Text("Complete party · EUR · calculated from the demo catalogue").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in Label(change, systemImage: "checkmark.circle").font(.subheadline) }
                    ForEach(Array(proposal.warnings.enumerated()), id: \.offset) { _, warning in InfoNote(text: warning) }
                    Button(hasChanges ? "Use this plan" : "Your choices already match") {
                        store.applyAITripPlan(plan)
                        applied = store.canUndoAIPlan
                        if applied { draft = nil; store.navigate(.configuration); dismiss() }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!plan.clarifications.isEmpty || !hasChanges)
                    if !plan.clarifications.isEmpty { Text("Answer the questions above to finish your plan.").font(.caption).foregroundStyle(.secondary) }
                    Text("Applies only the choices shown. You can undo the plan or edit individual items.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                InfoNote(text: "Your trip changed while this plan was being prepared. Generate a fresh plan to see the correct price.", symbol: "arrow.clockwise")
            }
        }
    }

    private func preference(_ title: String, key: WritableKeyPath<AIPlanNeeds, Bool?>, fallback: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { draft?.needs[keyPath: key] ?? fallback }, set: { draft?.needs[keyPath: key] = $0 }))
            .font(.subheadline).tint(TripTheme.ink)
    }

    private var appliedCard: some View {
        Panel(selected: true) {
            Label("Your plan is applied", systemImage: "checkmark.circle.fill").font(.headline)
            Button("Undo AI plan") { store.undoAITripPlan(); applied = false; draft = nil }
        }
    }

    private func generate() {
        if store.itinerary == nil || store.completedTrip != nil {
            store.demo(journey)
            if let result = store.results.first { store.choose(result) }
        }
        draft = nil; applied = false
        Task { await store.makeAITripPlan(note: note) }
    }

    private func addPackingContext() {
        let items = store.needs.packingItems.filter { ["clothes", "laptop", "gifts", "sports", "liquids"].contains($0) }
        guard !items.isEmpty else { return }
        let line = "My confirmed packing items: " + items.map(packingLabel).joined(separator: ", ") + "."
        if !note.contains(line) { note = String((note.isEmpty ? line : note + "\n" + line).prefix(600)) }
    }

    private func choiceTitle(_ value: String) -> String {
        ["travel_light":"Only my small bag", "checked_bag":"Checked bags for everyone, every flight", "vegetarian":"Meals for everyone, vegetarian for adults", "meals":"Meals for everyone, every flight", "no_meal":"No meals", "together":"Seats together", "skip":"Keep my current choices"][value] ?? "Keep my current choices"
    }

    private func clarify(_ value: String, questionID: String) {
        switch value {
        case "travel_light": draft?.needs.travellingLight = true; draft?.needs.checkedBagEachWay = false; draft?.needs.giftsOnReturn = false
        case "checked_bag": draft?.needs.checkedBagEachWay = true; draft?.needs.travellingLight = false
        case "vegetarian": draft?.needs.vegetarian = true; draft?.needs.mealsEachFlight = true
        case "meals": draft?.needs.mealsEachFlight = true
        case "no_meal": draft?.needs.mealsEachFlight = false
        case "together": draft?.needs.stayTogether = true
        default: break
        }
        draft?.clarifications.removeAll { $0.id == questionID }
    }
}
