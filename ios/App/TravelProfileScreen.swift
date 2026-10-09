import SwiftUI

struct TravelProfileScreen: View {
    @Environment(TravelProfileStore.self) private var memory
    @Environment(BookingV2Store.self) private var booking
    @Environment(\.dismiss) private var dismiss
    @State private var settings = false
    @State private var editing: TravelPreference?
    @State private var addingPreference = false
    @State private var applied: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "person.text.rectangle").font(.title).padding(15).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 18))
                        Text("What we know\nabout you.").font(.largeTitle.bold()).tracking(-1)
                        Text("A little memory. A more personal journey.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let error = memory.error { InfoNote(text: error, symbol: "exclamationmark.circle") }
                    if memory.busy { ProgressView("Updating your travel memory…") }
                    if let profile = memory.profile {
                        HStack { Label(profile.collectionEnabled ? "Travel memory is on" : "Collection paused", systemImage: profile.collectionEnabled ? "checkmark.shield" : "pause.circle").font(.subheadline.bold()); Spacer() }
                        Text("Preferences come from the routes and choices you confirm. Searches show interest; they don't prove you've visited a destination.").font(.subheadline).foregroundStyle(.secondary)
                        if profile.preferences.isEmpty {
                            Panel { Text("Your story starts here.").font(.title3.bold()); Text("Confirm a flight search to begin. We'll show each preference with its source, and you can correct or forget it.").font(.subheadline).foregroundStyle(.secondary) }
                        }
                        ForEach(profile.preferences) { preference in
                            Panel {
                                HStack(alignment: .top) { Text(preference.label).font(.headline); Spacer(); Image(systemName: preference.locked ? "lock.fill" : "sparkles").foregroundStyle(.secondary).accessibilityLabel(preference.locked ? "Locked preference" : "Can be updated by learning") }
                                Text(preferenceValueLabel(preference)).font(.title3.weight(.semibold))
                                Text("\(sourceLabel(preference.source)) · \(preference.confidence.capitalized)").font(.caption).foregroundStyle(.secondary)
                                if !preference.evidenceIds.isEmpty {
                                    DisclosureGroup("Why we think this") {
                                        ForEach(profile.facts.filter { preference.evidenceIds.contains($0.id) }) { fact in
                                            Text("\(fact.origin) → \(fact.destination) · \(fact.departureDate) · \(factLabel(fact))").font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                                        }
                                    }.font(.subheadline)
                                }
                                HStack {
                                    Button("Correct") { editing = preference }.frame(minHeight: 44)
                                    Spacer()
                                    Button("Forget", role: .destructive) { Task { await memory.forgetPreference(key: preference.key) } }.frame(minHeight: 44)
                                }.font(.subheadline.weight(.semibold)).disabled(memory.busy)
                                if ["originAirport", "destinationAirport", "maximumStops"].contains(preference.key) {
                                    Button("Use in my search") { apply(preference) }.font(.subheadline.bold()).frame(minHeight: 44)
                                }
                            }
                        }
                        Button { addingPreference = true } label: { Label("Add or restore a preference", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44) }.disabled(memory.busy)
                        if let applied { Text(applied).font(.subheadline).foregroundStyle(.secondary) }
                        Button { Task { await memory.learn() } } label: { Label("Update what you know", systemImage: "sparkles").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle()).disabled(memory.busy || !profile.collectionEnabled || profile.facts.isEmpty)
                        Text(profile.learning.message).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Panel {
                            Text("You choose what stays.").font(.title3.bold())
                            Text("Turn on travel memory to save confirmed routes, dates and travel choices on the TripFit server. AI can use those details to suggest preferences.").font(.subheadline).foregroundStyle(.secondary)
                            Text("Names, children's details, payments, raw messages and photos are excluded. This is separate from optional product analytics.").font(.caption).foregroundStyle(.secondary)
                            Button("Enable travel memory") { Task { await memory.enableCollection() } }.buttonStyle(PrimaryButtonStyle()).disabled(memory.busy)
                        }
                    }
                    NavigationLink { TravelDataScreen() } label: { profileRow("Your data & collection", detail: "View, export, pause or erase", symbol: "externaldrive") }.buttonStyle(.plain)
                    Button { settings = true } label: { profileRow("App settings", detail: "Analytics and connection", symbol: "gearshape") }.buttonStyle(.plain)
                }.padding(24)
            }.navigationTitle("For you").tripInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { await memory.load() }
                .sheet(isPresented: $settings) { BookingPreferencesScreen() }
                .sheet(item: $editing) { PreferenceEditor(preference: $0) }
                .sheet(isPresented: $addingPreference) { PreferenceEditor() }
        }
    }
    private func profileRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) { Image(systemName: symbol).font(.title3); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(18).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
    private func preferenceValueLabel(_ preference: TravelPreference) -> String {
        let value = preference.value.rawText
        if ["originAirport", "destinationAirport"].contains(preference.key) {
            if let airport = booking.airports.first(where: { $0.code == value }) { return "\(airport.city) · \(airport.code)" }
            return value
        }
        if preference.key == "maximumStops" { return value == "0" ? "Direct flights" : value == "1" ? "Up to one stop" : "Up to two stops" }
        return ["any": "No seat preference", "window": "Window seat", "aisle": "Aisle seat", "personal_item": "Personal item", "cabin": "Cabin bag", "checked": "Checked bag"][value] ?? preference.value.displayText
    }
    private func sourceLabel(_ value: String) -> String { value == "user" ? "Confirmed by you" : value == "openai" ? "AI, based on your history" : "Observed in your choices" }
    private func apply(_ preference: TravelPreference) {
        let field = preference.key == "destinationAirport" ? "destinationAirports" : preference.key == "maximumStops" ? "maxConnections" : preference.key
        guard !booking.intent.lockedFields.contains(field) else { applied = "That search requirement is locked. Unlock it in your search to change it."; return }
        booking.editIntent { intent in
            switch preference.key {
            case "originAirport": intent.originAirport = preference.value.displayText
            case "destinationAirport": intent.destinationAirports = [preference.value.displayText]
            case "maximumStops": intent.maxConnections = Int(preference.value.displayText)
            default: break
            }
            intent.unresolved.removeAll { $0.field == field }
        }
        applied = "Applied to your search. Review dates and travellers before searching."
    }
}

struct TravelDataScreen: View {
    @Environment(TravelProfileStore.self) private var memory
    @State private var clear = false
    @State private var erase = false
    @State private var restoringPreference = false
    var body: some View {
        Form {
            Section("Data collection") {
                if let profile = memory.profile {
                    Toggle("Remember my travel choices", isOn: Binding(get: { profile.collectionEnabled }, set: { value in Task { await memory.setCollection(value) } }))
                    Text("When enabled, future confirmed searches and booking choices are saved. Pausing stops new collection and AI updates; existing memory stays until you erase it.").font(.caption)
                } else {
                    Text("Travel memory is off. No travel profile is connected on this device.")
                    Button("Enable travel memory") { Task { await memory.enableCollection() } }.disabled(memory.busy)
                }
            }
            Section("What is collected") {
                Label("Routes, departure and return dates", systemImage: "airplane")
                Label("Confirmed stop, seat and bag preferences", systemImage: "checklist")
                Label("Search or booking source and time", systemImage: "clock")
                Text("No names, raw chat, screenshots, photographs, child ages, passport or payment details. AI receives only these structured travel facts. Product analytics has its own separate switch in App settings.").font(.caption)
            }
            if let profile = memory.profile {
                Section("Saved travel activity · \(profile.facts.count)") {
                    if profile.facts.isEmpty { Text("Nothing collected yet.").foregroundStyle(.secondary) }
                    ForEach(profile.facts.reversed()) { fact in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(fact.origin) → \(fact.destination)").font(.headline)
                            Text("\(fact.departureDate)\(fact.returnDate.map { " – " + $0 } ?? "")").font(.subheadline)
                            Text(factLabel(fact)).font(.caption).foregroundStyle(.secondary)
                            Button("Forget this activity", role: .destructive) { Task { await memory.deleteFact(id: fact.id) } }.font(.caption).disabled(memory.busy)
                        }.padding(.vertical, 4)
                    }
                }
                if !profile.suppressedPreferenceKeys.isEmpty {
                    Section("Forgotten preferences") { Text(profile.suppressedPreferenceKeys.map(preferenceTitle).joined(separator: ", ")).font(.subheadline); Text("These preferences won't be learned again unless you explicitly restore them.").font(.caption); Button("Restore a preference") { restoringPreference = true }.disabled(memory.busy) }
                }
                Section("Your controls") {
                    Button("Prepare JSON export") { Task { await memory.exportProfile() } }.disabled(memory.busy)
                    if let url = memory.exportURL { ShareLink("Share your data export", item: url) }
                    Button("Clear travel history", role: .destructive) { clear = true }.disabled(memory.busy)
                    Button("Erase my entire travel profile", role: .destructive) { erase = true }.disabled(memory.busy)
                    Text("Export contains your saved facts and preferences, with no access token. Erasing the profile also revokes this device's profile access.").font(.caption)
                }
            }
            if let error = memory.error { Section { Text(error).foregroundStyle(.secondary) } }
        }.navigationTitle("Your data").tripInlineTitle()
            .sheet(isPresented: $restoringPreference) { PreferenceEditor() }
            .confirmationDialog("Clear travel history and learned preferences?", isPresented: $clear, titleVisibility: .visible) { Button("Clear history", role: .destructive) { Task { await memory.clearHistory() } } }
            .confirmationDialog("Erase all saved travel memory? This cannot be undone.", isPresented: $erase, titleVisibility: .visible) { Button("Erase profile", role: .destructive) { Task { await memory.deleteProfile() } } }
    }
}

struct PreferenceEditor: View {
    @Environment(TravelProfileStore.self) private var memory
    @Environment(BookingV2Store.self) private var booking
    @Environment(\.dismiss) private var dismiss
    var preference: TravelPreference? = nil
    @State private var preferenceKey = "originAirport"
    @State private var value = ""
    @State private var locked = true
    private let keys = ["originAirport", "destinationAirport", "maximumStops", "seatPreference", "baggagePreference"]
    private var key: String { preference?.key ?? preferenceKey }
    var body: some View {
        NavigationStack {
            Form {
                if preference == nil {
                    Section("What would you like us to remember?") {
                        Picker("Preference type", selection: $preferenceKey) { ForEach(keys, id: \.self) { Text(preferenceTitle($0)).tag($0) } }
                        Text("Adding a preference restores it if you previously chose to forget it.").font(.caption)
                    }
                }
                Section(preferenceTitle(key)) {
                    Picker("Your preference", selection: $value) {
                        if ["originAirport", "destinationAirport"].contains(key) {
                            if value.isEmpty { Text("Choose an airport").tag("") }
                            if !value.isEmpty && !booking.airports.contains(where: { $0.code == value }) { Text(value).tag(value) }
                            ForEach(booking.airports) { Text("\($0.city) · \($0.code)").tag($0.code) }
                        } else if key == "maximumStops" {
                            Text("Direct only").tag("0"); Text("Up to one stop").tag("1"); Text("Up to two stops").tag("2")
                        } else if key == "seatPreference" {
                            Text("No preference").tag("any"); Text("Window").tag("window"); Text("Aisle").tag("aisle")
                        } else {
                            Text("Personal item").tag("personal_item"); Text("Cabin bag").tag("cabin"); Text("Checked bag").tag("checked")
                        }
                    }
                    Toggle("Lock this preference", isOn: $locked)
                    Text(locked ? "AI won't overwrite this preference. Use it explicitly when you want to change a search." : "Future learning can update this preference using your confirmed travel facts. Your current search stays unchanged.").font(.caption)
                }
                if let error = memory.error { Text(error).font(.subheadline) }
                if memory.busy { ProgressView("Saving your preference…") }
                Button("Save my preference") {
                    Task {
                        await memory.updatePreference(key: key, value: key == "maximumStops" ? .number(Int(value) ?? 0) : .string(value), locked: locked)
                        if memory.error == nil { dismiss() }
                    }
                }.disabled(memory.busy || value.isEmpty)
            }.navigationTitle(preference == nil ? "Add preference" : "Correct preference").tripInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear {
                    preferenceKey = preference?.key ?? "originAirport"
                    value = preference?.value.rawText ?? initialValue(for: preferenceKey)
                    locked = preference?.locked ?? true
                }
                .onChange(of: preferenceKey) { _, newValue in if preference == nil { value = initialValue(for: newValue) } }
        }
    }
    private func initialValue(for key: String) -> String {
        if let existing = memory.profile?.preferences.first(where: { $0.key == key }) { return existing.value.rawText }
        switch key {
        case "maximumStops": return "0"
        case "seatPreference": return "any"
        case "baggagePreference": return "personal_item"
        default: return ""
        }
    }
}

private func preferenceTitle(_ key: String) -> String {
    ["originAirport": "Departure airport", "destinationAirport": "Destination", "maximumStops": "Connections", "seatPreference": "Seat", "baggagePreference": "Baggage"][key] ?? key
}
private func factLabel(_ fact: TravelFact) -> String {
    switch fact.provenance {
    case "demo_booking": return "Demo booking · no ticket issued"
    case "live_booking": return "Confirmed booking"
    case "live_search": return "Live flight search · not a booking"
    default: return "Sample flight search · not a booking"
    }
}
