import SwiftUI
import TripFitCore

struct SeatsScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var passengerID = "adult-1"
    @State private var segmentID = ""
    var segment: Segment? { store.itinerary?.segments.first { $0.id == segmentID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "A window. An aisle. Together.", subtitle: "Select a seat for each traveller. Only seats you select are held in this demo booking.")
            Panel {
                Picker("Flight", selection: $segmentID) { ForEach(store.itinerary?.segments.filter(\.isPegasus) ?? []) { Text("\($0.direction.title) · \($0.origin)–\($0.destination)").tag($0.id) } }
                Picker("Traveller", selection: $passengerID) { ForEach(store.passengers) { Text($0.displayName).tag($0.id) } }
            }
            if let segment {
                if store.needs.stayTogether && store.passengers.contains(where: \.isChild) {
                    Panel(selected: true) {
                        Label("Keep a parent beside each child", systemImage: "person.2.fill").font(.headline)
                        if let seats = Catalog.familySeats(passengers: store.passengers, segment: segment, existing: store.selection.seats) {
                            Text("Available arrangement: \(seats.map(\.seatID).joined(separator: ", ")). Selecting it assigns seats for this flight.").font(.subheadline)
                            Button("Select this arrangement") { for seat in seats { store.setSeat(seat.seatID, passenger: seat.passengerID, segment: segment.id) } }.frame(minHeight: 44)
                        } else {
                            Text("No adjacent arrangement is available for this party in the small demo seat map. Choose seats individually or change the itinerary. Across the aisle isn't beside a parent.").font(.subheadline)
                            InfoNote(text: "We cannot promise adjacent seats that have not been selected.")
                        }
                    }
                }
                HStack(spacing: 16) { legend("Available", color: .white); legend("Selected", color: TripTheme.yellow); legend("Unavailable", color: .gray.opacity(0.25)) }.font(.caption2)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 10) {
                        Image(systemName: "airplane").font(.largeTitle).foregroundStyle(.secondary).padding(.bottom, 16).accessibilityHidden(true)
                        HStack { ForEach(["A","B","C","","D","E","F"], id: \.self) { Text($0).font(.caption.bold()).frame(width: $0.isEmpty ? 18 : 43) } }
                        ForEach(1...8, id: \.self) { row in HStack(spacing: 7) {
                            ForEach(["A","B","C","","D","E","F"], id: \.self) { letter in
                                if letter.isEmpty { Text("\(row)").font(.caption2).foregroundStyle(.secondary).frame(width: 18) }
                                else if let seat = Catalog.seats(for: segment).first(where: { $0.id == "\(row)\(letter)" }) { seatButton(seat, segment: segment) }
                            }
                        } }
                        Text("Front of aircraft ↑ · row 1 extra legroom").font(.caption2).foregroundStyle(.secondary).padding(.top, 14)
                    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 60)).overlay(RoundedRectangle(cornerRadius: 60).stroke(TripTheme.line))
                }
                ForEach(store.passengers) { passenger in
                    HStack { Label(passenger.displayName, systemImage: passenger.isChild ? "figure.child" : "person"); Spacer(); Text(store.selection.seats.first { $0.passengerID == passenger.id && $0.segmentID == segment.id }?.seatID ?? "Unassigned").bold() }.font(.subheadline)
                }
                Button("Remove this traveller's seat choice") { store.setSeat(nil, passenger: passengerID, segment: segment.id) }.frame(minHeight: 44)
                Text("Standard seat €15; extra legroom €30 per flight. Bundles include standard seats; only the upgrade difference is charged. Children cannot use the exit row.").font(.footnote).foregroundStyle(.secondary)
                if let external = store.itinerary?.segments.first(where: { !$0.isPegasus }) { InfoNote(text: "Seats for \(external.carrier) aren't selectable here. The incoming ticket's own rules apply.") }
            }
            Button("Skip seat selection") { store.navigate(.meals) }.frame(minHeight: 44)
        }.onAppear { if segmentID.isEmpty { segmentID = store.itinerary?.segments.first(where: \.isPegasus)?.id ?? "" } }
    }
    func legend(_ text: String, color: Color) -> some View { HStack(spacing: 4) { RoundedRectangle(cornerRadius: 4).fill(color).overlay(RoundedRectangle(cornerRadius: 4).stroke(TripTheme.line)).frame(width: 14, height: 14); Text(text) } }
    func seatButton(_ seat: Seat, segment: Segment) -> some View {
        let assigned = store.selection.seats.first { $0.segmentID == segment.id && $0.seatID == seat.id }
        let isChild = store.passengers.first { $0.id == passengerID }?.isChild == true
        let disabled = !seat.isAvailable || (isChild && seat.isExitRow) || (assigned != nil && assigned?.passengerID != passengerID)
        return Button {
            store.setSeat(assigned?.passengerID == passengerID ? nil : seat.id, passenger: passengerID, segment: segment.id)
        } label: {
            VStack(spacing: 1) { Text(seat.id).font(.caption.bold()); if seat.isExitRow { Image(systemName: "arrow.up.and.down").font(.system(size: 9)) } }
                .frame(width: 43, height: 44)
                .background(assigned != nil ? TripTheme.yellow : disabled ? Color.gray.opacity(0.15) : .white, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(seat.isExitRow ? TripTheme.yellow : TripTheme.line, lineWidth: 2))
                .foregroundStyle(disabled && assigned == nil ? .secondary : TripTheme.ink)
        }.buttonStyle(.plain).disabled(disabled)
            .accessibilityLabel("Seat \(seat.id), \(seat.isExitRow ? "extra legroom, " : "")\(disabled ? "unavailable" : euros(seat.priceCents))\(assigned != nil ? ", assigned" : "")")
            .accessibilityAddTraits(assigned?.passengerID == passengerID ? .isSelected : [])
    }
}

struct MealsScreen: View {
    @Environment(BookingStore.self) private var store
    @State private var passengerID = "adult-1"
    @State private var segmentID = ""
    var segment: Segment? { store.itinerary?.segments.first { $0.id == segmentID } }
    var passenger: Passenger? { store.passengers.first { $0.id == passengerID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(title: "Good food. Your choice.", subtitle: "Meal selections are per traveller and per flight. No meal is always an option.")
            Panel {
                Picker("Flight", selection: $segmentID) { ForEach(store.itinerary?.segments.filter(\.isPegasus) ?? []) { Text("\($0.direction.title) · \($0.origin)–\($0.destination) · \($0.localDeparture("HH:mm"))").tag($0.id) } }
                Picker("Traveller", selection: $passengerID) { ForEach(store.passengers) { Text($0.displayName).tag($0.id) } }
                Toggle("Prefer vegetarian choices", isOn: Binding(get: { store.needs.packingItems.contains("vegetarian") }, set: { value in store.preference("vegetarian") { store.needs.packingItems.removeAll { $0 == "vegetarian" }; if value { store.needs.packingItems.append("vegetarian") } } }))
            }
            if let segment, let passenger {
                if segment.durationMinutes < 100 { InfoNote(text: "A short morning flight: skipping a meal may be a good fit. You can still choose one below.") }
                ChoiceRow(title: "No meal for me", detail: "Keep things simple.", selected: selectedMeal == nil, price: "€0") { store.setMeal(nil, passenger: passengerID, segment: segment.id) }
                ForEach(Catalog.orderedMeals(passenger: passenger, needs: store.needs)) { meal in
                    Button { store.setMeal(meal.id, passenger: passengerID, segment: segment.id) } label: {
                        Panel(selected: selectedMeal == meal.id) {
                            HStack(spacing: 18) {
                                MealArt(productID: meal.id).frame(width: 96, height: 96).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 8) { Text(meal.name).font(.headline); Text(meal.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary); Text(store.selection.bundle == .basic ? euros(meal.priceCents) : "Included in your bundle").font(.subheadline.bold()) }
                                Spacer(minLength: 0)
                            }
                            Text(meal.description).font(.footnote).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityAddTraits(selectedMeal == meal.id ? .isSelected : [])
                }
            }
            InfoNote(text: "Illustrative menu and food artwork. Dietary tags are not an allergy-safety guarantee. This demo catalogue has no alcohol products; minors never receive alcohol suggestions.")
            Button("Skip meals and review") { store.navigate(.review) }.frame(minHeight: 44)
        }.onAppear { if segmentID.isEmpty { segmentID = store.itinerary?.segments.first(where: \.isPegasus)?.id ?? "" } }
    }
    var selectedMeal: String? { store.selection.meals.first { $0.passengerID == passengerID && $0.segmentID == segmentID }?.productID }
}
/// Original bundled-style vector food illustration; no remote images required.
struct MealArt: View {
    var productID: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.95, green: 0.93, blue: 0.87))
            Circle().fill(.white).padding(10).shadow(color: .black.opacity(0.1), radius: 5, y: 3)
            if productID.contains("veggie") {
                ForEach(0..<8) { i in Ellipse().fill(i.isMultiple(of: 2) ? Color.green.opacity(0.65) : Color(red: 0.6, green: 0.72, blue: 0.3)).frame(width: 18, height: 30).offset(y: -15).rotationEffect(.degrees(Double(i) * 45)) }
                Circle().fill(Color.orange).frame(width: 20)
            } else if productID.contains("child") {
                ForEach(0..<5) { i in Capsule().fill(Color.orange.opacity(0.8)).frame(width: 36, height: 7).rotationEffect(.degrees(Double(i) * 32)).offset(x: CGFloat(i % 2) * 9 - 4, y: CGFloat(i) * 7 - 14) }
                Image(systemName: "leaf.fill").foregroundStyle(.green).offset(x: 13, y: -15)
            } else {
                Ellipse().fill(Color(red: 0.76, green: 0.43, blue: 0.2)).frame(width: 42, height: 29).rotationEffect(.degrees(-25)).offset(x: -9)
                ForEach(0..<5) { i in Capsule().fill(Color(red: 0.9, green: 0.82, blue: 0.55)).frame(width: 19, height: 5).rotationEffect(.degrees(30)).offset(x: 15, y: CGFloat(i) * 6 - 12) }
            }
        }
    }
}
