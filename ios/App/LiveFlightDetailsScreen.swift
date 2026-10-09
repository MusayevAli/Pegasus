import SwiftUI

struct LiveFlightDetailsScreen: View {
    @Environment(BookingV2Store.self) private var booking
    @State private var packing = false
    var offer: V2FlightOffer
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text("Your next departure.").font(.largeTitle.bold()).tracking(-1)
            Panel { FlightOfferFacts(offer: offer); InventorySourceLine() }
            Panel {
                Label("Flight details from Pegasus.", systemImage: "airplane").font(.headline)
                Text("This is the flight fare returned by Pegasus for your search. Availability and the final payable amount are confirmed on Pegasus.").font(.subheadline).foregroundStyle(.secondary)
                Text("Baggage, seat choices and meals are not priced in this result. Check the fare package and add extras before paying.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(offer.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            if offer.itinerary.transferType != "direct" { ConnectionSummary(itinerary: offer.itinerary) }
            Button { packing = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera").font(.title2).padding(14).background(TripTheme.yellow, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) { Text("Check your packing").font(.headline); Text("Identify items before choosing baggage.").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: "chevron.right")
                }.padding(18).background(TripTheme.card, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
            if let url = offer.externalBookingURL {
                Link(destination: url) { HStack { Text("Continue on Pegasus"); Spacer(); Image(systemName: "arrow.up.right") } }.buttonStyle(PrimaryButtonStyle())
                Text("Opens the official Pegasus booking page. Your search is passed to Pegasus; review the selected flights and extras there.").font(.caption).foregroundStyle(.secondary)
            } else { InfoNote(text: "A booking link wasn't supplied. Search again to retrieve a current Pegasus result.") }
        }.sheet(isPresented: $packing) { BookingPackingScreen() }
    }
}
