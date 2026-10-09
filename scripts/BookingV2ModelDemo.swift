import Foundation

// Headless model/contract tests. Mock prices below are isolated test fixtures, not app inventory.
private struct CheckFailure: Error, CustomStringConvertible { var description: String }
private actor MockBookingClient: BookingV2Client {
    var bodies: [String: Data] = [:]
    var delayAI = false
    var failAI = false
    var failSearch = false
    var crossSource = false
    var malformedQuote = false
    var keepPacking = false
    var checkoutCount = 0
    var dropCheckoutResponse = false
    var savedCheckouts: [String: Data] = [:]
    static let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
    static let origin = V2Airport(code: "SAW", name: "Sabiha", city: "Istanbul", country: "TR", timeZone: "Europe/Istanbul")
    static let destination = V2Airport(code: "BCN", name: "Barcelona", city: "Barcelona", country: "ES", timeZone: "Europe/Madrid")
    static let segment = V2FlightSegment(id: "test-segment", operatingCarrier: "Test sample", flightNumber: "TEST1", origin: origin, destination: destination, departureAt: "2030-01-01T10:00:00+03:00", arrivalAt: "2030-01-01T12:00:00+01:00", durationMinutes: 240, direction: "outbound", ticketGroup: "test", checkedBaggage: .init(pieces: 0,totalWeightKg: 0,maxPieceWeightKg: 0,maxLinearCm: 158), underseat: .init(weightKg: 3,dimensionsCm: [40,30,15]), independentlyBooked: false)
    static let itinerary = V2Itinerary(id: "test-itinerary", segments: [segment], durationMinutes: 240,connectionMinutes: [],overnight: false,transferType: "direct",transferSteps: [],terms: "Test fixture",entryRequirements: "not_checked")
    static func offer(_ id: String = "test-offer", party: Int = 1) -> V2FlightOffer { .init(id: id,provider: "sample",source: "sample",itinerary: itinerary,basePrice: .init(amountMinor: 10000 * party),totalPrice: .init(amountMinor: 10000 * party),extrasPrice: .init(amountMinor: 0),priceScope: "party",partySize: party,bundleId: "light",includedCheckedPieces: 0,includedCheckedWeightKg: 0,baggageSummary: "Underseat",requestedExtrasPriced: true,available: true,remainingSeats: 9,expiresAt: expiry,requestFingerprint: "test",notices: []) }
    static let bundle = V2FareBundle(id: "light",name: "Light",pricePerPassengerSegmentMinor: 0,checkedPieces: 0,checkedWeightKg: 0,cabinIncluded: false,standardSeatIncluded: false,mealIncluded: false,conditions: "Test fixture")
    static let products: [V2AncillaryProduct] = [
        .init(id: "checked20",type: "checked",name: "20kg",priceMinor: 3000,weightKg: 20,pieces: 1,tags: [],childOnly: false,eligibleSegmentIds: [segment.id]),
        .init(id: "checked25",type: "checked",name: "25kg",priceMinor: 4000,weightKg: 25,pieces: 1,tags: [],childOnly: false,eligibleSegmentIds: [segment.id]),
        .init(id: "cabin8",type: "cabin",name: "Cabin",priceMinor: 1000,weightKg: 8,pieces: 1,tags: [],childOnly: false,eligibleSegmentIds: [segment.id]),
        .init(id: "meal",type: "meal",name: "Meal",priceMinor: 800,weightKg: nil,pieces: nil,tags: [],childOnly: false,eligibleSegmentIds: [segment.id])]
    func dropNextCheckout() { dropCheckoutResponse = true }
    func setDelay(_ value: Bool) { delayAI = value }
    func setFailure(_ value: Bool) { failAI = value }
    func setSearchFailure(_ value: Bool) { failSearch = value }
    func setCrossSource(_ value: Bool) { crossSource = value }
    func setKeepPacking(_ value: Bool) { keepPacking = value }
    func setMalformed(_ value: Bool) { malformedQuote = value }
    func body(_ path: String) -> Data? { bodies[path] }
    func count() -> Int { checkoutCount }
    func request(path: String, method: String, body: Data?) async throws -> Data {
        if let body { bodies[path] = body }
        let object = try body.map { try JSONSerialization.jsonObject(with: $0) as! [String: Any] } ?? [:]
        func encoded<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
        func decoded<T: Decodable>(_ key: String, as: T.Type) throws -> T { try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object[key]!)) }
        let revision = object["revision"] as? Int ?? 0
        if path == "/api/v2/catalog" {
            return try encoded(V2Catalog(capabilities: .init(liveAI: false,textModel: "test",visionModel: "test",inventory: "sample",payments: "demo",fulfilment: "simulated",sampleWindow: .init(start: "2030-01-01",end: "2030-01-30"),offerCount: 100,routePairs: 15,providerNotice: "Test fixture"),airports: [Self.origin,Self.destination],bundles: [Self.bundle],routes: [.init(origin: "SAW",destination: "BCN")]))
        }
        if path == "/api/v2/providers" {
            return try encoded(V2ProvidersResponse(defaultProvider:"pegasus_mcp",providers:[.init(id:"pegasus_mcp",label:"Pegasus live",source:"live",search:true,ancillaries:false,seats:false,quote:false,checkout:false,externalBooking:true,authenticationRequired:false,notice:"Live flight prices only"),.init(id:"sample",label:"Sample inventory",source:"sample",search:true,ancillaries:true,seats:true,quote:true,checkout:true,externalBooking:false,authenticationRequired:false,notice:"No tickets")]))
        }
        if path == "/api/v2/ai/search-intent" {
            if delayAI { try? await Task.sleep(for: .milliseconds(100)) }
            if failAI { throw V2APIError.rejected(status: 503,message: "AI unavailable") }
            var intent: V2SearchIntent = try decoded("currentIntent",as: V2SearchIntent.self)
            intent.originAirport = "AYT"; intent.destinationAirports = ["BER"]; intent.outboundDate = "2030-01-01"
            return try encoded(V2AIExtraction(revision: revision,source: "openai",model: "test-mock",requestId: "test-ai",latencyMs: 1,intent: intent,summary: "Test extraction"))
        }
        if path == "/api/v2/flights/search" {
            if failSearch { throw V2APIError.rejected(status:503,message:"Live inventory unavailable") }
            let intent: V2SearchIntent = try decoded("intent",as: V2SearchIntent.self)
            if object["provider"] as? String == "pegasus_mcp", !crossSource {
                var live=Self.offer("live-test",party:intent.partySize)
                live.provider="pegasus_mcp";live.source="live";live.basePrice=nil;live.extrasPrice=nil;live.bundleId=nil;live.includedCheckedPieces=nil;live.includedCheckedWeightKg=nil;live.remainingSeats=nil;live.expiresAt=nil
                live.requestedExtrasPriced=false;live.totalPrice = .init(amountMinor:980050,currency:"TRY")
                live.itinerary.segments[0].flightNumber=nil;live.itinerary.segments[0].checkedBaggage=nil;live.itinerary.segments[0].underseat=nil
                live.bookingURL="https://web.flypgs.com/booking?test=fixture";live.capabilities = .init(ancillaries:false,seats:false,quote:false,checkout:false,externalBooking:true)
                return try encoded(V2SearchResponse(revision:intent.revision,source:"live",offers:[live],totalMatches:1,unresolved:[],notice:"Live test fixture",searchedWindow:.init(start:"2030-01-01",end:"2030-01-01"),requestFingerprint:"live-test"))
            }
            return try encoded(V2SearchResponse(revision: intent.revision,source: "sample",offers: [Self.offer(party:intent.partySize),Self.offer("test-second",party:intent.partySize)],totalMatches: 2,unresolved: [],notice: "Test fixture",searchedWindow: .init(start:"2030-01-01",end:"2030-01-30"),requestFingerprint:"test"))
        }
        if path.contains("/services?") {
            let seats = ["10A","10B","10C"].map { V2Seat(id:$0,row:10,column:String($0.suffix(1)),available:true,extraLegroom:false,childAllowed:true,priceMinor:500) }
            return try encoded(V2OfferServices(offerId: "test-offer",bundles:[Self.bundle],products:Self.products,seatMaps:[.init(segmentId:Self.segment.id,seats:seats,suggestedFamilySeats:["10A","10B","10C"],familyAvailable:true)],passengers:[.init(id:"adult-1",type:"adult",age:nil)],defaultSelection:.init()))
        }
        if path == "/api/v2/quotes" {
            let intent: V2SearchIntent = try decoded("intent",as: V2SearchIntent.self)
            let selection = object["selection"] is NSNull ? V2Selection() : try decoded("selection",as:V2Selection.self)
            let extra = selection.bags.reduce(0) { sum, bag in sum + (Self.products.first { $0.id == bag.productId }?.priceMinor ?? 0) }
            let meal = selection.meals.count * 800, seats = selection.seats.count * 500
            let total = 10000 + extra + meal + seats
            return try encoded(V2Quote(id: UUID().uuidString,revision:revision,source:"sample",provider:"sample",offerId:object["offerId"] as! String,selection:selection,passengers:[.init(id:"adult-1",type:"adult",age:nil)],items:[.init(id:"base",label:"Test base",amountMinor:10000,passengerId:nil,segmentId:nil),.init(id:"extras",label:"Test extras",amountMinor:total-10000,passengerId:nil,segmentId:nil)],basePrice:.init(amountMinor:10000),extrasPrice:.init(amountMinor:total-10000),total:.init(amountMinor:malformedQuote ? total+1:total),status:"valid",expiresAt:Self.expiry,priceScope:"party",notices:intent.noAlcohol ? ["Alcohol excluded"]:[]))
        }
        if path.contains("/packing-options") {
            if delayAI { try? await Task.sleep(for: .milliseconds(100)) }
            var selection: V2Selection = try decoded("selection",as:V2Selection.self)
            if !keepPacking { selection.bags.removeAll { $0.productId == "checked20" }; selection.bags.append(.init(passengerId:"adult-1",segmentId:Self.segment.id,productId:"checked25")) }
            return try encoded(V2PackingOptionsResponse(status:"ready",questions:[],options:[.init(id:"test-pack",title:"Test checked upgrade",explanation:"Measured test",selection:selection,total:.init(amountMinor:14000),differenceMinor:1000,action:keepPacking ? "keep":"add_bag",requiresConfirmation:true)],notice:"Test fixture"))
        }
        if path == "/api/v2/ai/packing" {
            if delayAI { try? await Task.sleep(for: .milliseconds(100)) }
            return try encoded(V2PackingAssessment(revision:revision,source:"openai",model:"test-mock",requestId:"test-photo",latencyMs:1,summary:"Test photo",items:[],uncertainties:["Weigh the bag"],requiresMeasurements:true))
        }
        if path == "/api/v2/checkout" {
            let key=object["idempotencyKey"] as! String
            if let saved=savedCheckouts[key] { return saved }
            checkoutCount += 1
            let result = try encoded(V2Order(id:"test-order-\(checkoutCount)",quoteId:object["quoteId"] as! String,reference:"TEST-\(checkoutCount)",state:"confirmed_demo",paymentStatus:"simulated",fulfilmentStatus:"not_issued",ticketIssued:false,total:.init(amountMinor:10000),createdAt:ISO8601DateFormatter().string(from:Date()),itinerary:Self.itinerary,selection:.init(),travellerNames:object["travellerNames"] as! [String],notice:"Test fixture"))
            savedCheckouts[key]=result
            if dropCheckoutResponse { dropCheckoutResponse=false;throw URLError(.networkConnectionLost) }
            return result
        }
        throw V2APIError.rejected(status:404,message:"Unmocked \(path)")
    }
}

@main struct BookingV2ModelDemo {
    @MainActor static func main() async throws {
        var checks: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws { guard condition() else { throw CheckFailure(description:label) }; checks.append(label) }
        let domain = "BookingV2Tests.\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let analytics = Analytics(); analytics.enabled = false
        let api = MockBookingClient(), store = BookingV2Store(analytics:analytics,client:api,defaults:defaults,providerID:"sample")
        try check(store.intent.originAirport == nil && store.intent.adults == 1 && store.intent.childAges.isEmpty,"unbiased manual defaults")
        store.editIntent { $0.originAirport="SAW"; $0.destinationAirports=["BCN"]; $0.outboundDate="2030-01-01" }
        store.intent.unresolved=[.init(field:"year",question:"Which year?",choices:[]),.init(field:"budgetScope",question:"Party budget?",choices:[])]
        store.aiStatus="Budget scope is unclear"
        store.editIntent { $0.budgetScope="party" }
        try check(store.aiStatus.isEmpty,"manual field edit clears stale AI summary")
        try check(store.intent.unresolved.map(\.field) == ["year"],"manual edit preserves unrelated unresolved year")
        store.editIntent { $0.outboundDate="2030-01-02" }
        try check(store.intent.unresolved.isEmpty,"confirmed date resolves year")
        let intentJSON=try JSONSerialization.jsonObject(with:JSONEncoder().encode(store.intent)) as! [String:Any]
        try check(intentJSON["incomingFlight"] is NSNull && intentJSON["budgetMinor"] is NSNull && intentJSON["dateWindow"] is NSNull,"nullable wire fields encoded as null")
        store.intent.childAges=[nil]
        try check(store.missingFields.contains {$0.field=="childAges"},"child age is required")
        store.intent.childAges=[]
        await api.setDelay(true)
        let pending=Task { await store.interpret("test pending") }; try await Task.sleep(for:.milliseconds(10)); store.cancelInterpretation(); await pending.value
        try check(store.intent.originAirport=="SAW" && store.lastAIRequestId==nil,"cancelled AI cannot apply a late response at same revision")
        let stale=Task { await store.interpret("test stale") }; try await Task.sleep(for:.milliseconds(10)); store.editIntent {$0.originAirport="LGW"}; await stale.value
        try check(store.intent.originAirport=="LGW","manual edit rejects stale AI")
        await api.setDelay(false); store.editIntent {$0.originAirport="SAW"}; store.setLocked("originAirport",true)
        await store.interpret("test locks")
        try check(store.intent.originAirport=="SAW" && store.intent.destinationAirports==["BER"],"locked fields survive valid AI extraction")
        await api.setFailure(true); let preserved=store.intent; await store.interpret("test unavailable")
        try check(store.intent==preserved && store.aiStatus.contains("unavailable"),"AI failure keeps fields with no canned fallback")
        await api.setFailure(false); await store.search()
        try check(store.offers.count==2 && store.stage == .results,"inventory result transition")
        await store.select(store.offers[0])
        let quoteBody=try JSONSerialization.jsonObject(with:await api.body("/api/v2/quotes")!) as! [String:Any]
        try check(quoteBody["selection"] is NSNull,"initial quote requests cheapest server default")
        try check(store.stage == .configuration && store.quote?.total.amountMinor==10000,"authoritative quote accepted")
        await store.setBag("checked20",passengerId:"adult-1",segmentId:"test-segment")
        await store.setBag("cabin8",passengerId:"adult-1",segmentId:"test-segment",kind:"cabin")
        await store.setBag(nil,passengerId:"adult-1",segmentId:"test-segment")
        try check(store.selection.bags.map(\.productId)==["cabin8"],"bag toggle preserves unrelated cabin allowance")
        await store.setBag("checked20",passengerId:"adult-1",segmentId:"test-segment")
        await store.loadPackingOptions(measurements:[.init(passengerId:"adult-1",direction:"outbound",pieces:1,totalWeightKg:22,maxPieceWeightKg:22,maxLinearCm:140,dimensionsCm:[65,45,30])],items:[])
        let original=store.selection
        try check(store.packingOptions.count==1 && store.selection==original,"packing recommendation waits for explicit apply")
        await store.applyPackingOption(store.packingOptions[0]); await store.setSeat("10A",passengerId:"adult-1",segmentId:"test-segment"); await store.undoPackingOption()
        try check(store.selection.bags==original.bags && store.selection.seats.first?.seatId=="10A","packing undo preserves subsequent manual seat")
        await api.setDelay(true)
        let pendingOptions=Task { await store.loadPackingOptions(measurements:[.init(passengerId:"adult-1",direction:"outbound",pieces:1,totalWeightKg:2,maxPieceWeightKg:2,maxLinearCm:75,dimensionsCm:[35,25,15])],items:[]) }
        try await Task.sleep(for:.milliseconds(10));store.cancelPackingOptions();await pendingOptions.value
        try check(store.packingOptions.isEmpty,"edited packing inputs reject an in-flight old proposal")
        await api.setDelay(false)
        await api.setKeepPacking(true)
        await store.loadPackingOptions(measurements:[.init(passengerId:"adult-1",direction:"outbound",pieces:1,totalWeightKg:2,maxPieceWeightKg:2,maxLinearCm:75,dimensionsCm:[35,25,15])],items:[])
        await store.applyPackingOption(store.packingOptions[0]);await store.setSeat("10B",passengerId:"adult-1",segmentId:"test-segment")
        try check(store.retainsPackingRecommendation,"keep allowance retained despite unrelated seat edit")
        await store.setBag(nil,passengerId:"adult-1",segmentId:"test-segment")
        try check(!store.retainsPackingRecommendation,"manual baggage change removes keep-allowance retention")
        store.error="Previous analysis failed"
        let photo=Data([0xFF,0xD8,1,2,3]); await store.analysePacking(photo)
        try check(store.error==nil,"successful photo retry clears stale error")
        let photoJSON=try JSONSerialization.jsonObject(with:await api.body("/api/v2/ai/packing")!) as! [String:Any]
        try check(photoJSON["imageBase64"] as? String==photo.base64EncodedString() && photoJSON["context"]==nil,"packing sends actual supplied image without unsupported fields")
        await api.setDelay(true)
        let photoTask=Task { await store.analysePacking(Data([4,5,6])) };try await Task.sleep(for:.milliseconds(10))
        try check(store.aiBusy,"photo request exposes AI progress")
        store.cancelPhotoRequests();await photoTask.value
        try check(store.packingAssessment==nil && !store.aiBusy,"cleared photo rejects late image response")
        await api.setDelay(false)
        await api.setMalformed(true); await store.requote()
        try check(store.quote==nil,"malformed server quote totals rejected")
        await api.setMalformed(false)
        var confirmedTrip: V2SearchIntent?
        store.onDemoOrder = { intent, _ in confirmedTrip = intent }
        store.intent.dateWindow = .init(start:"2030-01-01",end:"2030-01-05")
        store.selection = .init(); await store.requote(); await store.review()
        try check(store.stage != .review,"missing passenger names block review")
        store.passengers[0].givenName="Sample"; store.passengers[0].familyName="Traveller"
        await store.review(); try check(store.stage == .review && store.error==nil,"valid names and refreshed quote reach review")
        await store.checkoutDemo(); try check(store.stage == .confirmation && store.orders.count==1,"backend demo order persisted")
        try check(confirmedTrip?.dateWindow==nil && confirmedTrip?.outboundDate=="2030-01-01" && confirmedTrip?.destinationAirports==["BCN"],"confirmed trip hook uses selected flight dates and route instead of search window")
        let restored=BookingV2Store(analytics:analytics,client:api,defaults:defaults,providerID:"sample")
        try check(restored.stage == .confirmation && restored.completedOrder?.id==store.completedOrder?.id,"completed booking restores confirmation")
        await restored.checkoutDemo(); let firstCount=await api.count(); try check(firstCount==1,"relaunch duplicate checkout creates no order")
        restored.editIntent {$0.destinationAirports=["BCN"]}; await restored.search(); await restored.select(restored.offers[0]); await restored.review(); await restored.checkoutDemo()
        try check(restored.orders.count==2,"fresh search after completion can book again")
        restored.reset();restored.editIntent {$0.originAirport="SAW";$0.destinationAirports=["BCN"];$0.outboundDate="2030-01-01"}
        await restored.search();await restored.select(restored.offers[0]);await restored.review()
        let pendingQuote=restored.quote!.id,pendingAttempt=restored.checkoutAttempt
        await api.dropNextCheckout();await restored.checkoutDemo()
        try check(restored.completedOrder==nil && restored.hasPendingCheckout,"lost checkout response remains unconfirmed")
        let recovered=BookingV2Store(analytics:analytics,client:api,defaults:defaults,providerID:"sample");await recovered.initialize()
        try check(recovered.quote?.id==pendingQuote && recovered.checkoutAttempt==pendingAttempt && recovered.hasPendingCheckout,"pending checkout relaunch preserves exact quote and attempt")
        recovered.quote?.expiresAt="2000-01-01T00:00:00Z"
        try check(recovered.quote?.isExpired==true && recovered.hasPendingCheckout,"expired pending quote exposes recovery action")
        await recovered.checkoutDemo();let recoveredCount=await api.count()
        try check(recovered.completedOrder != nil && recoveredCount==3 && !recovered.hasPendingCheckout,"retry recovers accepted order without duplicate")
        let importDomain="V2ImportTests.\(UUID().uuidString)";let importDefaults=UserDefaults(suiteName:importDomain)!
        defer { importDefaults.removePersistentDomain(forName:importDomain) }
        let importing=BookingV2Store(analytics:analytics,client:api,defaults:importDefaults,providerID:"sample");await importing.initialize()
        importing.editIntent {$0.originAirport="SAW";$0.destinationAirports=["BCN"];$0.outboundDate="2030-01-01";$0.returnDate="2030-01-08";$0.tripType="round_trip";$0.dateWindow = .init(start:"2030-01-01",end:"2030-01-05");$0.durationNights=7}
        func imported(_ incoming:V2IncomingFlight?,kind:String="incoming_flight") -> V2TripImport { .init(revision:importing.intent.revision,source:"openai",model:"test",requestId:"test-import",latencyMs:1,kind:kind,title:nil,location:nil,airportCandidates:["BCN"],localDate:"2030-01-04",localTime:"16:00",year:2030,timeZone:"Europe/Madrid",incomingFlight:incoming,unresolved:[],suggestedArrivalBufferMinutes:180,notice:"Test") }
        var incoming=V2IncomingFlight(airline:"Test Air",flightNumber:nil,arrivalAirport:"ZZZ",arrivalAt:"2030-01-01T08:00:00+03:00",departureAirport:nil,confirmed:true)
        let beforeImport=importing.intent
        await importing.applyImport(imported(incoming),bufferMinutes:180)
        try check(importing.intent==beforeImport,"unknown incoming airport rejected")
        incoming.arrivalAirport="SAW";incoming.arrivalAt="not a date"
        await importing.applyImport(imported(incoming),bufferMinutes:180)
        try check(importing.intent==beforeImport,"invalid incoming instant rejected")
        incoming.arrivalAt="2030-01-01T08:00:00+03:00";incoming.airline=" "
        await importing.applyImport(imported(incoming),bufferMinutes:180)
        try check(importing.intent==beforeImport,"missing incoming airline rejected")
        incoming.airline="Test Air";importing.intent.lockedFields=["returnDate"]
        await importing.applyImport(imported(incoming),bufferMinutes:180)
        try check(importing.intent.returnDate=="2030-01-08" && importing.intent.incomingFlight==nil,"incoming import preserves locked return date")
        importing.intent.lockedFields=[]
        await importing.applyImport(imported(nil,kind:"event"),bufferMinutes:180)
        try check(importing.intent.outboundDate=="2030-01-04" && importing.intent.dateWindow==nil && importing.intent.durationNights==nil,"confirmed screenshot clears obsolete flexible dates")
        incoming.arrivalAt="2030-01-01T22:30:00Z"
        await importing.applyImport(imported(incoming),bufferMinutes:180)
        try check(importing.intent.outboundDate=="2030-01-02","incoming screenshot uses arrival airport local calendar day")
        let localArrivalIntent=importing.intent
        await importing.applyImport(imported(incoming,kind:"event"),bufferMinutes:180)
        try check(importing.intent==localArrivalIntent && importing.error != nil,"contradictory screenshot kind rejected")
        var alternativeIntent=importing.intent;alternativeIntent.revision += 1;alternativeIntent.budgetMinor=90000;alternativeIntent.budgetScope="party"
        let alternative=V2Alternative(id:"test-alternative",offer:MockBookingClient.offer(),changes:[.init(field:"budgetMinor",from:"50000",to:"90000")],intent:alternativeIntent,explanation:"Backend-shape fixture",requiresConfirmation:true)
        importing.alternatives=[alternative]
        await importing.chooseAlternative(alternative)
        try check(importing.intent==alternativeIntent && importing.offers.count==2,"server alternative with next revision applies and refreshes inventory")
        let afterAlternative=importing.intent
        await importing.chooseAlternative(alternative)
        try check(importing.intent==afterAlternative && importing.error != nil,"stale alternative replay cannot modify current search")
        analytics.enabled=true;store.stage = .results;store.back()
        let backEvent=analytics.queue.last { $0.name == "back_navigation" }
        if case .string(let previous)? = backEvent?.properties["previousScreen"] { try check(previous=="itinerary","results back navigation emits canonical analytics screen") }
        else { throw CheckFailure(description:"Missing canonical back-navigation event") }
        analytics.enabled=false
        let liveDomain="V2LiveTests.\(UUID().uuidString)",liveDefaults=UserDefaults(suiteName:liveDomain)!
        defer { liveDefaults.removePersistentDomain(forName:liveDomain) }
        let liveAPI=MockBookingClient(),live=BookingV2Store(analytics:analytics,client:liveAPI,defaults:liveDefaults)
        try check(live.providerID=="pegasus_mcp","new app defaults to explicit live provider")
        var confirmedSearches=0
        live.onConfirmedSearch={ _ in confirmedSearches += 1 }
        await live.initialize()
        try check(live.providers.count==2 && live.selectedProvider?.source=="live","provider catalogue exposes live and sample capabilities")
        live.editIntent { $0.originAirport="SAW";$0.destinationAirports=["BCN"];$0.outboundDate="2030-01-01" }
        await live.search()
        let liveBody=try JSONSerialization.jsonObject(with:await liveAPI.body("/api/v2/flights/search")!) as! [String:Any]
        try check(liveBody["provider"] as? String == "pegasus_mcp" && live.offers.first?.source=="live","live search uses explicit provider and source")
        try check(confirmedSearches==1,"confirmed search hook runs only after successful inventory response")
        let liveOffer=live.offers[0]
        try check(liveOffer.basePrice==nil && liveOffer.extrasPrice==nil && liveOffer.itinerary.segments[0].flightNumber==nil && liveOffer.itinerary.segments[0].underseat==nil && liveOffer.totalPrice.currency=="TRY","unknown live fares and allowances remain nil; actual currency preserved")
        try check(liveOffer.externalBookingURL?.host=="web.flypgs.com","official Pegasus continuation URL accepted")
        var hostile=liveOffer;hostile.bookingURL="https://web.flypgs.com.evil.example/booking"
        try check(hostile.externalBookingURL==nil,"lookalike continuation domain rejected")
        await live.select(liveOffer)
        await live.setBag("checked20",passengerId:"adult-1",segmentId:"test-segment")
        await live.setMeal("meal",passengerId:"adult-1",segmentId:"test-segment")
        await live.setSeat("10A",passengerId:"adult-1",segmentId:"test-segment")
        await live.review();await live.checkoutDemo()
        let liveQuoteBody=await liveAPI.body("/api/v2/quotes"),liveCheckoutBody=await liveAPI.body("/api/v2/checkout")
        try check(live.stage == .configuration && live.quote==nil && live.services.isEmpty && live.seatMaps.isEmpty && live.selection.bags.isEmpty && live.selection.meals.isEmpty && live.selection.seats.isEmpty && !live.readyForReview && liveQuoteBody==nil && liveCheckoutBody==nil,"live selection cannot fabricate extras, quote or demo purchase")
        live.persist()
        let liveRestored=BookingV2Store(analytics:analytics,client:liveAPI,defaults:liveDefaults)
        await liveRestored.initialize()
        try check(liveRestored.providerID=="pegasus_mcp" && liveRestored.quote==nil && liveRestored.selectedOffer?.source=="live","live details restore without sample reprice")
        live.stage = .search;live.setProvider("sample")
        try check(live.selectedOffer==nil && live.offers.isEmpty,"switching providers invalidates incompatible offers and selection")
        await live.search();try check(live.offers.first?.source=="sample","sample search remains an explicit separate choice")
        live.stage = .search;live.setProvider("pegasus_mcp");await liveAPI.setSearchFailure(true);await live.search()
        try check(live.offers.isEmpty && live.error != nil,"live outage never falls back to cached sample inventory")
        await liveAPI.setSearchFailure(false);await liveAPI.setCrossSource(true);await live.search()
        try check(live.offers.isEmpty && live.error != nil,"cross-provider response rejected")
        var report:[String:Any]=["mode":"headless Swift model run; not iOS UI", "mockChecks":checks.count,"checks":checks]
        if let index=CommandLine.arguments.firstIndex(of:"--online"),CommandLine.arguments.count>index+1 {
            report["http"]=try await online(CommandLine.arguments[index+1])
        }
        if let index=CommandLine.arguments.firstIndex(of:"--live"),CommandLine.arguments.count>index+1 {
            report["liveHTTP"]=try await liveOnline(CommandLine.arguments[index+1])
        }
        let result=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]); print(String(decoding:result,as:UTF8.self))
    }
    @MainActor static func liveOnline(_ url:String) async throws -> [String:Any] {
        func require(_ condition:@autoclosure ()->Bool,_ label:String)throws { if !condition(){throw CheckFailure(description:"Live HTTP: "+label)} }
        let name="V2LiveOnline.\(UUID().uuidString)",defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let analytics=Analytics();analytics.enabled=false
        let store=BookingV2Store(analytics:analytics,client:BookingV2HTTPClient(baseURL:url),defaults:defaults)
        await store.initialize();try require(store.selectedProvider?.source=="live","providers \(store.error ?? "")")
        let outbound=Calendar.current.date(byAdding:.day,value:16,to:Date())!,returning=Calendar.current.date(byAdding:.day,value:22,to:Date())!
        store.editIntent { $0.originAirport="SAW";$0.destinationAirports=["BCN"];$0.outboundDate=V2Dates.day(outbound);$0.returnDate=V2Dates.day(returning);$0.tripType="round_trip";$0.adults=2;$0.checkedBags=1;$0.baggageScope="party";$0.baggageDirection="both" }
        await store.search();try require(!store.offers.isEmpty,"live flights \(store.error ?? store.notice ?? "")")
        let count=store.offers.count,offer=store.offers[0]
        try require(store.offers.allSatisfy{$0.source=="live" && $0.provider=="pegasus_mcp" && !$0.requestedExtrasPriced && $0.basePrice==nil && $0.extrasPrice==nil && $0.externalBookingURL != nil},"truthful flight prices and official continuation")
        var compared=false
        if count>1 { await store.compareSelected(Array(store.offers.prefix(2).map(\.id)));try require(store.comparison?.offers.count==2,"live comparison \(store.error ?? "")");compared=true }
        await store.select(offer)
        try require(store.stage == .configuration && store.quote==nil && store.services.isEmpty && store.seatMaps.isEmpty && !store.readyForReview,"live detail without simulated configuration")
        await store.checkoutDemo();try require(store.orders.isEmpty && store.completedOrder==nil,"live cannot create demo order")
        return ["baseURL":url,"provider":store.providerID,"source":offer.source,"route":"SAW–BCN","outboundDate":store.intent.outboundDate!,"returnDate":store.intent.returnDate!,"partySize":2,"offers":count,"flightPriceMinor":offer.totalPrice.amountMinor,"currency":offer.totalPrice.currency,"requestedExtrasPriced":offer.requestedExtrasPriced,"officialContinuationHost":offer.externalBookingURL!.host!,"liveComparison":compared,"nativeCheckoutUnavailable":true,"ticketsIssued":false]
    }
    @MainActor static func online(_ url:String) async throws -> [String:Any] {
        func require(_ condition:@autoclosure ()->Bool,_ label:String)throws { if !condition(){throw CheckFailure(description:"HTTP: "+label)} }
        let name="V2Online.\(UUID().uuidString)";let defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let analytics=Analytics();analytics.enabled=false
        let api=BookingV2HTTPClient(baseURL:url),store=BookingV2Store(analytics:analytics,client:api,defaults:defaults,providerID:"sample")
        await store.initialize();try require(store.capabilities != nil,"catalog \(store.error ?? "")")
        let start=V2Dates.date(store.capabilities!.sampleWindow.start)!
        store.editIntent { $0.originAirport="SAW"; $0.destinationAirports=["BCN"]; $0.outboundDate=V2Dates.day(start.addingTimeInterval(86400*3)); $0.returnDate=V2Dates.day(start.addingTimeInterval(86400*9)); $0.tripType="round_trip"; $0.adults=2; $0.childAges=[7]; $0.checkedBags=1; $0.baggageScope="party"; $0.baggageDirection="both"; $0.keepTogether=true; $0.meals=true; $0.vegetarian=true; $0.noAlcohol=true }
        await store.search();try require(store.offers.count>=2,"multiple family offers \(store.error ?? "")")
        let offerCount=store.offers.count
        await store.compareSelected(Array(store.offers.prefix(2).map(\.id)));try require(store.comparison?.offers.count==2,"comparison \(store.error ?? "")")
        await store.select(store.offers[0]);try require(store.quote?.isValid==true && !store.services.isEmpty,"quote/services \(store.error ?? "")")
        let initialTotal=store.quote!.total.amountMinor
        for map in store.seatMaps { await store.applyFamilySeats(segmentId:map.segmentId) }
        try require(store.quote?.isValid==true,"family seat atomic update \(store.error ?? "")")
        let directions=Set(store.selectedOffer!.itinerary.segments.filter{ !$0.independentlyBooked }.map(\.direction))
        let measurements=store.passengers.flatMap { person in directions.map { V2PackingMeasurement(passengerId:person.id,direction:$0,pieces:1,totalWeightKg:2,maxPieceWeightKg:2,maxLinearCm:75,dimensionsCm:[35,25,15]) } }
        await store.loadPackingOptions(measurements:measurements,items:[])
        try require(!store.packingOptions.isEmpty,"measurement-backed packing options \(store.error ?? store.notice ?? "")")
        for i in store.passengers.indices { store.passengers[i].givenName="Demo\(i+1)";store.passengers[i].familyName="Traveller" }
        await store.review();try require(store.stage == .review,"review \(store.error ?? "")")
        let finalTotal=store.quote!.total.amountMinor
        await store.checkoutDemo();try require(store.completedOrder != nil,"checkout \(store.error ?? "")")
        let order=store.completedOrder!
        let read:V2Order=try await api.get("/api/v2/orders/\(order.id)")
        try require(read==order && !order.ticketIssued && order.total.amountMinor==finalTotal,"authoritative saved order")
        let restored=BookingV2Store(analytics:analytics,client:api,defaults:defaults,providerID:"sample");await restored.checkoutDemo();try require(restored.orders.count==1,"no duplicate restored order")
        return ["baseURL":url,"inventory":store.capabilities!.inventory,"liveAIConfigured":store.capabilities!.liveAI,"offers":offerCount,"initialTotalMinor":initialTotal,"finalTotalMinor":finalTotal,"orderId":order.id,"reference":order.reference,"paymentStatus":order.paymentStatus,"ticketIssued":order.ticketIssued,"savedOrderMatches":true,"packingOptions":store.packingOptions.count]
    }
}
