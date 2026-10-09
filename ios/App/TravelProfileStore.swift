import Foundation
import Observation
import Security
import CryptoKit

enum TravelPreferenceValue: Codable, Equatable, Sendable {
    case string(String), number(Int)
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if let n = try? c.decode(Int.self) { self = .number(n) } else { self = .string(try c.decode(String.self)) } }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .string(let s): try c.encode(s); case .number(let n): try c.encode(n) } }
    var rawText: String { switch self { case .string(let value): value; case .number(let value): String(value) } }
    var displayText: String { rawText.replacingOccurrences(of: "_", with: " ") }
}
struct TravelFact: Codable, Equatable, Identifiable, Sendable {
    var id: String; var kind: String; var provenance: String; var occurredAt: String
    var origin: String; var destination: String; var departureDate: String; var returnDate: String?
    var maximumStops: Int?; var seatPreference: String?; var baggagePreference: String?
}
struct TravelPreference: Codable, Equatable, Identifiable, Sendable {
    var id: String; var key: String; var value: TravelPreferenceValue; var label: String; var confidence: String; var source: String
    var evidenceIds: [String]; var locked: Bool; var updatedAt: String
}
struct TravelLearningStatus: Codable, Equatable, Sendable {
    var state: String; var source: String; var message: String; var model: String?; var requestId: String?; var latencyMs: Int?
}
struct TravelProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String; var collectionEnabled: Bool; var createdAt: String; var updatedAt: String
    var facts: [TravelFact]; var preferences: [TravelPreference]; var suppressedPreferenceKeys: [String]; var learning: TravelLearningStatus
}
private struct CreatedTravelProfile: Decodable { var capabilityToken: String; var profile: TravelProfile }
private struct AddedTravelFacts: Decodable { var accepted: Int; var duplicates: Int; var profile: TravelProfile }
private struct TravelCollectionBody: Encodable { var collectionEnabled: Bool }
private struct TravelFactsBody: Encodable { var facts: [TravelFact] }
private struct TravelPreferenceBody: Encodable { var value: TravelPreferenceValue; var locked = true }
private struct TravelExport: Codable { var schemaVersion: Int; var exportedAt: String; var profile: TravelProfile }

@MainActor protocol TravelProfileCredentialStore {
    func token(for scope: String) throws -> String?
    func save(_ token: String, for scope: String) throws
    func delete(for scope: String) throws
}
struct TravelProfileKeychainError: LocalizedError {
    var status: OSStatus
    var errorDescription: String? { "The private profile key could not be saved securely (Keychain \(status))." }
}
@MainActor final class KeychainTravelProfileCredentials: TravelProfileCredentialStore {
    private let service = "com.pegasus.tripfit.travel-profile"
    private func query(_ scope: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: scope] }
    func token(for scope: String) throws -> String? {
        var q = query(scope); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = result as? Data else { throw TravelProfileKeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }
    func save(_ token: String, for scope: String) throws {
        let q = query(scope), data = Data(token.utf8)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }; guard update == errSecItemNotFound else { throw TravelProfileKeychainError(status: update) }
        var add = q; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil); guard status == errSecSuccess else { throw TravelProfileKeychainError(status: status) }
    }
    func delete(for scope: String) throws { let status = SecItemDelete(query(scope) as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw TravelProfileKeychainError(status: status) } }
}

@MainActor @Observable final class TravelProfileStore {
    private(set) var profile: TravelProfile?
    private(set) var busy = false
    var error: String?
    private(set) var exportURL: URL?
    @ObservationIgnored private let analytics: Analytics
    @ObservationIgnored private let credentials: any TravelProfileCredentialStore
    @ObservationIgnored private let clientFactory: ((String, String) -> any BookingV2Client)?
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var capability: String?
    @ObservationIgnored private var collectionPaused = false
    @ObservationIgnored private var activeRequest: Task<Data, Error>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var automaticLearning: Task<Void, Never>?
    @ObservationIgnored private var enablingCollection = false
    @ObservationIgnored private var pendingBootstrapCleanup: [String: String] = [:]
    private let validKeys = Set(["originAirport", "destinationAirport", "maximumStops", "seatPreference", "baggagePreference"])

    init(analytics: Analytics, credentials: (any TravelProfileCredentialStore)? = nil, clientFactory: ((String, String) -> any BookingV2Client)? = nil) {
        self.analytics = analytics; self.credentials = credentials ?? KeychainTravelProfileCredentials(); self.clientFactory = clientFactory
    }
    static func canonicalBackendURL(_ raw: String) -> String? {
        guard var c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = c.scheme?.lowercased(), ["https", "http"].contains(scheme), let host = c.host?.lowercased(), !host.isEmpty, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { return nil }
        c.scheme = scheme; c.host = host
        if (scheme == "http" && c.port == 80) || (scheme == "https" && c.port == 443) { c.port = nil }
        while c.path.hasSuffix("/") { c.path.removeLast() }
        return c.string
    }
    private func ensureScope() throws -> String {
        guard let current = Self.canonicalBackendURL(analytics.baseURL) else { throw V2APIError.invalidURL }
        if scope != current {
            generation = UUID(); activeRequest?.cancel(); automaticLearning?.cancel(); profile = nil; capability = nil; busy = false; clearExport(); scope = current
            capability = try credentials.token(for: current)
            collectionPaused = UserDefaults.standard.bool(forKey: pauseKey(current))
        }
        return current
    }
    func load() async {
        do {
            _ = try ensureScope(); guard !busy else { return }; guard capability != nil else { profile = nil; error = nil; return }
            let value: TravelProfile = try await request("/api/personalization/me", method: "GET"); apply(value); if collectionPaused { profile?.collectionEnabled = false }
        } catch { report(error) }
    }
    func enableCollection() async {
        guard !enablingCollection else { return }
        enablingCollection = true; defer { enablingCollection = false }
        do {
            let current = try ensureScope()
            if capability != nil { await setCollection(true); return }
            if let pending = pendingBootstrapCleanup[current] { try await cleanUpBootstrap(pending, scope: current) }
            try verifySecureStorage(scope: current)
            let created: CreatedTravelProfile = try await request("/api/personalization/profiles", body: TravelCollectionBody(collectionEnabled: true), bootstrap: true)
            guard created.capabilityToken.hasPrefix("tp_"), created.capabilityToken.count == 46 else { throw V2APIError.invalidResponse }
            do { try credentials.save(created.capabilityToken, for: current) }
            catch {
                let storageError = error
                pendingBootstrapCleanup[current] = created.capabilityToken
                // Nothing is collected until the capability is stored securely. If deletion
                // is temporarily unreachable, the capability stays only in this process so
                // another tap retries cleanup instead of creating another profile.
                do { try await cleanUpBootstrap(created.capabilityToken, scope: current) }
                catch { throw V2APIError.rejected(status: 503, message: "Secure profile storage failed. No travel facts were collected. Cleanup is waiting for a connection; retry before enabling memory.") }
                throw storageError
            }
            capability = created.capabilityToken; apply(created.profile); setPaused(false, scope: current)
        } catch { report(error) }
    }
    private func verifySecureStorage(scope: String) throws {
        let probeScope = scope + "#secure-storage-check", probe = UUID().uuidString
        defer { try? credentials.delete(for: probeScope) }
        try credentials.save(probe, for: probeScope)
        guard try credentials.token(for: probeScope) == probe else { throw TravelProfileKeychainError(status: errSecInternalComponent) }
        try credentials.delete(for: probeScope)
    }
    private func cleanUpBootstrap(_ token: String, scope: String) async throws {
        do { _ = try await requestData("/api/personalization/me", method: "DELETE", body: nil, capabilityOverride: token, expectedScope: scope) }
        catch V2APIError.rejected(let status, _) where status == 401 || status == 404 { /* The private profile is already absent. */ }
        pendingBootstrapCleanup.removeValue(forKey: scope)
    }
    func setCollection(_ enabled: Bool) async {
        automaticLearning?.cancel()
        do {
            let current = try ensureScope()
            if !enabled { setPaused(true, scope: current); profile?.collectionEnabled = false; clearExport() }
            if capability == nil { if enabled { await enableCollection() }; return }
            let value: TravelProfile = try await request("/api/personalization/me", method: "PATCH", body: TravelCollectionBody(collectionEnabled: enabled)); apply(value); setPaused(!enabled, scope: current)
        } catch { report(error) }
    }
    func learn() async {
        automaticLearning?.cancel(); automaticLearning = nil
        do {
            _ = try ensureScope(); guard profile?.collectionEnabled == true, !collectionPaused else { return }
            let value: TravelProfile = try await request("/api/personalization/me/learn", body: [String: String]()); apply(value)
        } catch { report(error) }
    }
    func record(intent: V2SearchIntent, kind: String, selection: V2Selection? = nil, provenance: String? = nil) async {
        do {
            _ = try ensureScope()
            if profile == nil, capability != nil { await load() }
            guard profile?.collectionEnabled == true, !collectionPaused, let origin = intent.originAirport, origin.count == 3, intent.destinationAirports.count == 1, let destination = intent.destinationAirports.first, destination.count == 3, let date = intent.outboundDate, intent.dateWindow == nil, ["confirmed_search", "confirmed_trip"].contains(kind) else { return }
            let source = provenance ?? (kind == "confirmed_trip" ? "demo_booking" : "")
            guard (kind == "confirmed_search" ? ["sample_search", "live_search"] : ["demo_booking", "live_booking"]).contains(source) else { return }
            var baggage: String?
            if selection?.bags.contains(where: { $0.productId.hasPrefix("checked") }) == true || (intent.checkedBags ?? 0) > 0 { baggage = "checked" }
            else if selection?.bags.contains(where: { $0.productId.hasPrefix("cabin") }) == true { baggage = "cabin" }
            var seat: String?
            if intent.adults == 1, intent.childAges.isEmpty, let seats = selection?.seats, !seats.isEmpty {
                let choices = Set(seats.map { item in ["A", "F"].contains(String(item.seatId.suffix(1))) ? "window" : (["C", "D"].contains(String(item.seatId.suffix(1))) ? "aisle" : "any") })
                if choices.count == 1 { seat = choices.first }
            }
            var fact = TravelFact(id: "", kind: kind, provenance: source, occurredAt: "", origin: origin, destination: destination, departureDate: date, returnDate: intent.tripType == "round_trip" ? intent.returnDate : nil, maximumStops: intent.maxConnections, seatPreference: seat, baggagePreference: baggage)
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            var bytes = Array(SHA256.hash(data: try encoder.encode(fact)).prefix(16)); bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
            fact.id = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])).uuidString
            guard profile?.facts.contains(where: { $0.id == fact.id }) != true else { return }
            fact.occurredAt = ISO8601DateFormatter().string(from: Date())
            let added: AddedTravelFacts = try await request("/api/personalization/me/facts", body: TravelFactsBody(facts: [fact])); apply(added.profile)
            if added.accepted > 0, added.profile.facts.count >= 2 {
                automaticLearning?.cancel()
                automaticLearning = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2)); guard !Task.isCancelled else { return }; self?.automaticLearning = nil; await self?.learn()
                }
            }
        } catch { report(error) }
    }
    func updatePreference(key: String, value: TravelPreferenceValue, locked: Bool = true) async {
        guard validKeys.contains(key) else { return }; automaticLearning?.cancel()
        do { let result: TravelProfile = try await request("/api/personalization/me/preferences/\(key)", method: "PUT", body: TravelPreferenceBody(value: value, locked: locked)); apply(result) } catch { report(error) }
    }
    func forgetPreference(key: String) async {
        guard validKeys.contains(key) else { return }; automaticLearning?.cancel()
        do { let result: TravelProfile = try await request("/api/personalization/me/preferences/\(key)", method: "DELETE"); apply(result) } catch { report(error) }
    }
    func deleteFact(id: String) async {
        guard UUID(uuidString: id) != nil else { return }; automaticLearning?.cancel()
        do { let result: TravelProfile = try await request("/api/personalization/me/facts/\(id)", method: "DELETE"); apply(result) } catch { report(error) }
    }
    func clearHistory() async {
        automaticLearning?.cancel()
        do { let result: TravelProfile = try await request("/api/personalization/me/history", method: "DELETE"); apply(result); clearExport() } catch { report(error) }
    }
    func exportProfile() async {
        automaticLearning?.cancel(); automaticLearning = nil
        do {
            let value: TravelExport = try await request("/api/personalization/me/export", method: "GET")
            guard value.schemaVersion == 1 else { throw V2APIError.invalidResponse }
            clearExport(); let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PegasusTravelProfile", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Travel-profile-\(UUID().uuidString).json")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); exportURL = url
        } catch { report(error) }
    }
    func deleteProfile() async {
        automaticLearning?.cancel()
        do {
            let current = try ensureScope(); guard capability != nil else { return }
            _ = try await requestData("/api/personalization/me", method: "DELETE", body: nil)
            try credentials.delete(for: current); capability = nil; profile = nil; setPaused(false, scope: current); clearExport()
        } catch { report(error) }
    }
    private func apply(_ value: TravelProfile) { if profile != value { clearExport() }; profile = value }
    private func pauseKey(_ scope: String) -> String { "travelProfilePaused." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func setPaused(_ value: Bool, scope: String) { collectionPaused = value; if value { UserDefaults.standard.set(true, forKey: pauseKey(scope)) } else { UserDefaults.standard.removeObject(forKey: pauseKey(scope)) } }
    private func clearExport() { if let exportURL { try? FileManager.default.removeItem(at: exportURL) }; exportURL = nil }
    private func request<T: Decodable>(_ path: String, method: String = "GET") async throws -> T { try JSONDecoder().decode(T.self, from: try await requestData(path, method: method, body: nil)) }
    private func request<B: Encodable, T: Decodable>(_ path: String, method: String = "POST", body: B, bootstrap: Bool = false) async throws -> T { try JSONDecoder().decode(T.self, from: try await requestData(path, method: method, body: JSONEncoder().encode(body), bootstrap: bootstrap)) }
    private func requestData(_ path: String, method: String, body: Data?, bootstrap: Bool = false, capabilityOverride: String? = nil, expectedScope: String? = nil) async throws -> Data {
        let current = try ensureScope()
        guard expectedScope == nil || expectedScope == current else { throw CancellationError() }
        guard bootstrap || capability != nil || capabilityOverride != nil else { throw V2APIError.rejected(status: 401, message: "Enable a private travel profile first.") }
        activeRequest?.cancel(); let id = UUID(); generation = id; busy = true; error = nil
        let token = bootstrap ? analytics.uploadToken : (capabilityOverride ?? capability!)
        let client = clientFactory?(current, token) ?? BookingV2HTTPClient(baseURL: current, token: token)
        let task = Task { try await client.request(path: path, method: method, body: body) }; activeRequest = task
        defer { if generation == id { busy = false; activeRequest = nil } }
        let result: Data
        do { result = try await task.value } catch { guard generation == id, !task.isCancelled else { throw CancellationError() }; throw error }
        guard generation == id, !task.isCancelled, scope == current, Self.canonicalBackendURL(analytics.baseURL) == current else { throw CancellationError() }
        return result
    }
    private func report(_ failure: Error) {
        guard !(failure is CancellationError), (failure as? URLError)?.code != .cancelled else { return }
        error = (failure as? LocalizedError)?.errorDescription ?? "Your private travel profile could not be updated. Retry when connected."
    }
}
