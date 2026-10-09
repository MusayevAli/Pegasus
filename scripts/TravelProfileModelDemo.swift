import Foundation

private struct ProfileCheckFailure: Error, CustomStringConvertible { let description: String }
@MainActor private final class MemoryProfileCredentials: TravelProfileCredentialStore {
    var values: [String: String] = [:]
    var failAllWrites = false
    var failCapabilityWrite = false
    func token(for scope: String) throws -> String? { values[scope] }
    func save(_ token: String, for scope: String) throws { if failAllWrites || (failCapabilityWrite && !scope.hasSuffix("#secure-storage-check")) { throw TravelProfileKeychainError(status: -34018) }; values[scope] = token }
    func delete(for scope: String) throws { values.removeValue(forKey: scope) }
}
private actor ProfileMockServer {
    var profiles: [String: TravelProfile] = [:]
    var calls: [(String, String, String, Data?)] = []
    var failCollection = false
    var delayedFacts = false
    var failDelete = false
    func setFailCollection(_ value: Bool) { failCollection = value }
    func setFailDelete(_ value: Bool) { failDelete = value }
    func profileCount() -> Int { profiles.count }
    func delayFacts(_ value: Bool) { delayedFacts = value }
    func count(_ suffix: String) -> Int { calls.filter { $0.1.hasSuffix(suffix) }.count }
    func captured() -> [(String,String,String,Data?)] { calls }
    func request(scope: String, token: String, path: String, method: String, body: Data?) async throws -> Data {
        calls.append((scope,path,token,body))
        let encoder=JSONEncoder(),decoder=JSONDecoder()
        let object=try body.map { try JSONSerialization.jsonObject(with:$0) as! [String:Any] } ?? [:]
        let at=ISO8601DateFormatter().string(from:Date())
        if path == "/api/personalization/profiles" {
            let profile=TravelProfile(id:UUID().uuidString,collectionEnabled:true,createdAt:at,updatedAt:at,facts:[],preferences:[],suppressedPreferenceKeys:[],learning:.init(state:"not_requested",source:"none",message:"Not requested",model:nil,requestId:nil,latencyMs:nil))
            profiles[scope]=profile
            return try JSONSerialization.data(withJSONObject:["capabilityToken":"tp_"+String(repeating:"x",count:43),"profile":try JSONSerialization.jsonObject(with:encoder.encode(profile))])
        }
        guard token.hasPrefix("tp_"),var profile=profiles[scope] else { throw V2APIError.rejected(status:401,message:"Profile access required") }
        if path == "/api/personalization/me",method == "DELETE" { if failDelete { throw URLError(.notConnectedToInternet) };profiles.removeValue(forKey:scope);return Data() }
        if path == "/api/personalization/me",method == "PATCH" {
            if failCollection { throw URLError(.notConnectedToInternet) }
            profile.collectionEnabled=object["collectionEnabled"] as! Bool
        }
        if path.hasSuffix("/facts") {
            if delayedFacts { try? await Task.sleep(for:.milliseconds(100)) }
            let facts=try decoder.decode([TravelFact].self,from:JSONSerialization.data(withJSONObject:object["facts"]!))
            let added=facts.filter { fact in !profile.facts.contains { $0.id==fact.id } }
            profile.facts += added;profiles[scope]=profile
            return try JSONSerialization.data(withJSONObject:["accepted":added.count,"duplicates":facts.count-added.count,"profile":try JSONSerialization.jsonObject(with:encoder.encode(profile))])
        }
        if path.hasSuffix("/learn") { profile.learning = .init(state:"ready",source:"openai",message:"Mock learned preferences",model:"mock-test",requestId:UUID().uuidString,latencyMs:1) }
        if path.contains("/preferences/") {
            let key=String(path.split(separator:"/").last!)
            profile.preferences.removeAll { $0.key==key }
            if method=="PUT" {
                let value=try decoder.decode(TravelPreferenceValue.self,from:JSONSerialization.data(withJSONObject:object["value"]!,options:.fragmentsAllowed))
                profile.preferences.append(.init(id:UUID().uuidString,key:key,value:value,label:key,confidence:"confirmed",source:"user",evidenceIds:[],locked:object["locked"] as? Bool ?? true,updatedAt:at))
            } else { profile.suppressedPreferenceKeys.append(key) }
        }
        if path.contains("/facts/") { let id=String(path.split(separator:"/").last!);profile.facts.removeAll{$0.id==id} }
        if path.hasSuffix("/history") { profile.facts=[];profile.preferences.removeAll{$0.source != "user"} }
        profiles[scope]=profile
        if path.hasSuffix("/export") { return try JSONSerialization.data(withJSONObject:["schemaVersion":1,"exportedAt":at,"profile":try JSONSerialization.jsonObject(with:encoder.encode(profile))]) }
        return try encoder.encode(profile)
    }
}
private struct ProfileMockClient: BookingV2Client {
    let server: ProfileMockServer;let scope:String;let token:String
    func request(path:String,method:String,body:Data?) async throws -> Data { try await server.request(scope:scope,token:token,path:path,method:method,body:body) }
}
@main struct TravelProfileModelDemo {
    @MainActor static func main() async throws {
        var checks:[String]=[]
        func check(_ value:@autoclosure()->Bool,_ label:String)throws { guard value() else {throw ProfileCheckFailure(description:label)};checks.append(label) }
        let analytics=Analytics(),oldURL=analytics.baseURL,oldToken=analytics.uploadToken
        defer { analytics.baseURL=oldURL;analytics.uploadToken=oldToken }
        let testID=UUID().uuidString.lowercased(),scope="http://profile-\(testID).example:3001"
        analytics.baseURL=scope;analytics.uploadToken="synthetic-bootstrap-token"
        let credentials=MemoryProfileCredentials(),server=ProfileMockServer()
        let factory:(String,String)->any BookingV2Client={ ProfileMockClient(server:server,scope:$0,token:$1) }
        let store=TravelProfileStore(analytics:analytics,credentials:credentials,clientFactory:factory)
        try check(TravelProfileStore.canonicalBackendURL(" HTTPS://EXAMPLE.com:443/ ")=="https://example.com","canonical backend scopes normalize only equivalent addresses")
        try check(TravelProfileStore.canonicalBackendURL("https://user@example.com")==nil && TravelProfileStore.canonicalBackendURL("https://example.com?key=bad")==nil,"credential-bearing backend addresses rejected")
        await store.load()
        var intent=V2SearchIntent();intent.originAirport="SAW";intent.destinationAirports=["BCN"];intent.outboundDate="2030-01-01";intent.childAges=[7];intent.checkedBags=0
        await store.record(intent:intent,kind:"confirmed_search",provenance:"live_search")
        let initial=await server.captured()
        try check(store.profile==nil && initial.isEmpty,"no profile creation or collection before explicit consent")
        await store.enableCollection()
        try check(store.profile?.collectionEnabled==true && credentials.values[scope] != nil,"explicit consent creates a private scoped capability")
        intent.dateWindow = .init(start:"2030-01-01",end:"2030-01-07")
        await store.record(intent:intent,kind:"confirmed_search",provenance:"live_search")
        try check(store.profile?.facts.isEmpty==true,"flexible search with retained exact date is not recorded as an exact trip")
        intent.dateWindow = nil
        await store.record(intent:intent,kind:"confirmed_search",provenance:"live_search")
        let first=store.profile!.facts[0]
        try check(first.provenance=="live_search" && first.baggagePreference==nil,"live provenance retained and zero checked bags implies no cabin preference")
        await store.record(intent:intent,kind:"confirmed_search",provenance:"live_search")
        try check(store.profile?.facts.count==1,"identical confirmed search replay is idempotent")
        var selection=V2Selection();selection.seats=[.init(passengerId:"adult-1",segmentId:"test",seatId:"10A")]
        intent.outboundDate="2030-02-01"
        await store.record(intent:intent,kind:"confirmed_trip",selection:selection,provenance:"demo_booking")
        try check(store.profile?.facts.last?.seatPreference==nil && store.profile?.facts.last?.provenance=="demo_booking","party seat choices do not infer the user's seat and demo is not a ticket")
        try await Task.sleep(for:.milliseconds(2200))
        let learns=await server.count("/learn")
        try check(learns==1 && store.profile?.learning.source=="openai","new consented facts schedule one bounded AI learning request")
        let captured=await server.captured()
        try check(captured.filter{$0.1=="/api/personalization/profiles"}.allSatisfy{$0.2=="synthetic-bootstrap-token"} && captured.filter{$0.1 != "/api/personalization/profiles"}.allSatisfy{$0.2.hasPrefix("tp_")},"bootstrap app token is never sent to profile-scoped endpoints")
        let factBodies=try captured.filter{$0.1.hasSuffix("/facts")}.compactMap{$0.3}.map { try JSONSerialization.jsonObject(with:$0) as! [String:Any] }
        let allowed:Set<String>=["id","kind","provenance","occurredAt","origin","destination","departureDate","returnDate","maximumStops","seatPreference","baggagePreference"]
        try check(factBodies.flatMap{$0["facts"] as! [[String:Any]]}.allSatisfy{Set($0.keys).isSubset(of:allowed)},"fact payload excludes names, children, prompts, photos and prices")
        await store.updatePreference(key:"baggagePreference",value:.string("personal_item"))
        try check(store.profile?.preferences.first?.value.rawText=="personal_item" && TravelPreferenceValue.string("personal_item").displayText=="personal item","picker raw values stay distinct from display labels")
        await store.updatePreference(key:"baggagePreference",value:.string("personal_item"),locked:false)
        try check(store.profile?.preferences.first?.locked==false,"explicit unlock is encoded and returned")
        await store.exportProfile()
        let export=store.exportURL!,exportText=try String(contentsOf:export,encoding:.utf8)
        try check(!exportText.contains("tp_") && !exportText.contains("synthetic-bootstrap-token"),"export excludes private capabilities and app tokens")
        await store.forgetPreference(key:"baggagePreference")
        try check(store.exportURL==nil && !FileManager.default.fileExists(atPath:export.path) && store.profile?.suppressedPreferenceKeys.contains("baggagePreference")==true,"forgetting removes stale export and suppresses learned preference")
        await server.setFailCollection(true);await store.setCollection(false)
        let before=await server.count("/facts")
        intent.outboundDate="2030-03-01";await store.record(intent:intent,kind:"confirmed_search",provenance:"sample_search")
        let after=await server.count("/facts")
        try check(store.profile?.collectionEnabled==false && before==after,"failed network opt-out still stops collection immediately on device")
        let resumed=TravelProfileStore(analytics:analytics,credentials:credentials,clientFactory:factory);await resumed.load()
        try check(resumed.profile?.collectionEnabled==false,"local opt-out survives relaunch while server is unreachable for mutation")
        await server.setFailCollection(false);await resumed.setCollection(true)
        await server.delayFacts(true)
        let pending=Task { await resumed.record(intent:intent,kind:"confirmed_search",provenance:"sample_search") }
        try await Task.sleep(for:.milliseconds(10));await resumed.load();await pending.value
        try check(resumed.profile?.facts.count==3,"opening profile does not cancel an in-flight confirmed fact")
        await server.delayFacts(false);await resumed.clearHistory()
        try check(resumed.profile?.facts.isEmpty==true,"clear history removes facts")
        let otherScope="http://second-\(testID).example:3001";analytics.baseURL=otherScope;await resumed.load()
        try check(resumed.profile==nil && credentials.values[scope] != nil,"changing backend never sends the prior profile capability")
        await resumed.enableCollection();analytics.baseURL=scope;await resumed.load();await resumed.deleteProfile()
        try check(resumed.profile==nil && credentials.values[scope]==nil && credentials.values[otherScope] != nil,"delete removes only the current backend profile and capability")
        analytics.baseURL=otherScope;await resumed.load();await resumed.deleteProfile()
        let atomicScope="http://atomic-\(testID).example:3001";analytics.baseURL=atomicScope
        let brokenCredentials=MemoryProfileCredentials(),atomicServer=ProfileMockServer()
        let atomic=TravelProfileStore(analytics:analytics,credentials:brokenCredentials,clientFactory:{ProfileMockClient(server:atomicServer,scope:$0,token:$1)})
        brokenCredentials.failAllWrites=true
        await atomic.enableCollection();await atomic.enableCollection()
        let preflightCreates=await atomicServer.count("/profiles")
        try check(preflightCreates==0 && atomic.profile==nil && brokenCredentials.values.isEmpty,"missing Keychain entitlement fails before any server profile is created")
        brokenCredentials.failAllWrites=false;brokenCredentials.failCapabilityWrite=true
        await atomic.enableCollection()
        let cleanedProfiles=await atomicServer.profileCount()
        try check(cleanedProfiles==0 && atomic.profile==nil && brokenCredentials.values.isEmpty,"final capability storage failure deletes the just-created empty profile")
        await atomicServer.setFailDelete(true);await atomic.enableCollection()
        let blockedCreates=await atomicServer.count("/profiles")
        await atomic.enableCollection();await atomic.enableCollection()
        let retriedCreates=await atomicServer.count("/profiles"),pendingProfiles=await atomicServer.profileCount()
        try check(blockedCreates==retriedCreates && pendingProfiles==1 && atomic.profile==nil && brokenCredentials.values.isEmpty,"failed cleanup retains only an in-memory capability and prevents a profile storm")
        await atomic.record(intent:intent,kind:"confirmed_search",provenance:"sample_search")
        let atomicFacts=await atomicServer.count("/facts")
        try check(atomicFacts==0,"no facts collected while capability storage or cleanup is unresolved")
        await atomicServer.setFailDelete(false);brokenCredentials.failCapabilityWrite=false
        await atomic.enableCollection()
        let recoveredProfiles=await atomicServer.profileCount()
        try check(recoveredProfiles==1 && atomic.profile?.collectionEnabled==true && brokenCredentials.values.count==1,"retry cleans the pending profile before enabling one securely stored profile")
        await atomic.deleteProfile()
        var report:[String:Any]=["mode":"headless Swift profile privacy checks; no real keychain writes","checks":checks,"count":checks.count]
        if let i=CommandLine.arguments.firstIndex(of:"--online"),CommandLine.arguments.count>i+1 { report["http"]=try await online(CommandLine.arguments[i+1],analytics:analytics) }
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
    }
    @MainActor static func online(_ baseURL:String,analytics:Analytics) async throws -> [String:Any] {
        func require(_ value:@autoclosure()->Bool,_ label:String)throws { if !value(){throw ProfileCheckFailure(description:"Profile HTTP: "+label)} }
        analytics.baseURL=baseURL;analytics.uploadToken=""
        let credentials=MemoryProfileCredentials(),store=TravelProfileStore(analytics:analytics,credentials:credentials)
        await store.enableCollection();try require(store.profile != nil,"create \(store.error ?? "")")
        var intent=V2SearchIntent();intent.originAirport="SAW";intent.destinationAirports=["BCN"];intent.outboundDate="2026-10-24";intent.checkedBags=1
        await store.record(intent:intent,kind:"confirmed_search",provenance:"sample_search")
        intent.destinationAirports=["AYT"];intent.outboundDate="2026-11-02"
        await store.record(intent:intent,kind:"confirmed_search",provenance:"sample_search")
        await store.learn();try require(store.profile?.learning.source=="openai" && store.profile?.facts.count==2,"actual AI learning \(store.error ?? store.profile?.learning.message ?? "")")
        let model=store.profile?.learning.model ?? "",preferenceCount=store.profile!.preferences.count
        await store.updatePreference(key:"baggagePreference",value:.string("cabin"));try require(store.profile?.preferences.contains{$0.key=="baggagePreference" && $0.locked && $0.source=="user"}==true,"user correction")
        await store.setCollection(false);try require(store.profile?.collectionEnabled==false,"opt-out")
        await store.exportProfile();try require(store.exportURL != nil,"export")
        await store.deleteProfile();try require(store.profile==nil && credentials.values.isEmpty && store.exportURL==nil,"delete and cleanup")
        return ["baseURL":baseURL,"learningSource":"openai","model":model,"structuredFacts":2,"learnedPreferences":preferenceCount,"userCorrection":true,"optOut":true,"export":true,"profileDeleted":true,"capabilityPersisted":false]
    }
}
