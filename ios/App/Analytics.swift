import Foundation
import Observation

enum EventValue: Codable, Sendable {
    case string(String), int(Int), bool(Bool)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else { self = .string(try c.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .int(let v): try c.encode(v); case .bool(let v): try c.encode(v) }
    }
}

struct AnalyticsEvent: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    var name: String
    var sessionId: String
    var flowId: String
    var screen: String
    var componentId: String
    var sequence: Int
    var clientTimestamp = ISO8601DateFormatter().string(from: Date())
    var appVersion = "1.0"
    var schemaVersion = 2
    var provenance = "demo"
    var properties: [String: EventValue]
    // v2 wire names; decode the previous persisted schema without losing queued IDs.
    private enum CodingKeys: String, CodingKey {
        case eventId, occurredAt, journeyId, step, dataSource
        case id, name, sessionId, flowId, screen, componentId, sequence, clientTimestamp, appVersion, schemaVersion, provenance, properties
    }
    init(name: String, sessionId: String, flowId: String, screen: String, componentId: String, sequence: Int, properties: [String: EventValue]) {
        self.name = name; self.sessionId = sessionId; self.flowId = flowId; self.screen = screen
        self.componentId = componentId; self.sequence = sequence; self.properties = properties
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .eventId) ?? c.decode(String.self, forKey: .id)
        clientTimestamp = try c.decodeIfPresent(String.self, forKey: .occurredAt) ?? c.decode(String.self, forKey: .clientTimestamp)
        flowId = try c.decodeIfPresent(String.self, forKey: .journeyId) ?? c.decode(String.self, forKey: .flowId)
        provenance = try c.decodeIfPresent(String.self, forKey: .dataSource) ?? c.decode(String.self, forKey: .provenance)
        name = try c.decode(String.self, forKey: .name); sessionId = try c.decode(String.self, forKey: .sessionId)
        screen = try c.decode(String.self, forKey: .screen); componentId = try c.decode(String.self, forKey: .componentId)
        sequence = try c.decode(Int.self, forKey: .sequence); appVersion = try c.decode(String.self, forKey: .appVersion)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); properties = try c.decode([String: EventValue].self, forKey: .properties)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .eventId); try c.encode(clientTimestamp, forKey: .occurredAt)
        try c.encode(flowId, forKey: .journeyId); try c.encode(provenance, forKey: .dataSource)
        try c.encode(name, forKey: .name); try c.encode(sessionId, forKey: .sessionId)
        try c.encode(screen, forKey: .screen); try c.encode(componentId, forKey: .componentId)
        try c.encode(sequence, forKey: .sequence); try c.encode(appVersion, forKey: .appVersion)
        try c.encode(2, forKey: .schemaVersion); try c.encode(properties, forKey: .properties)
        let step: String
        switch screen {
        case "search", "import": step = "search"
        case "itinerary", "comparison": step = "flight_selection"
        case "configuration", "baggage", "seats", "meals": step = "configuration"
        case "review": step = "review"
        case "checkout": step = "payment"
        case "confirmation": step = "confirmation"
        default: step = "other"
        }
        try c.encode(step, forKey: .step)
    }
}

private struct PersistedAnalytics: Codable {
    var sessionID: String
    var flowID: String
    var sequence: Int
    var queue: [AnalyticsEvent]
}

/// Foreground visits are checkpointed as deltas, never cumulative durations.
/// No text fields or image/payment payloads enter this API.
@MainActor @Observable final class Analytics {
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "analyticsConsent")
            guard enabled != oldValue else { return }
            entered = false; checkpointAt = ProcessInfo.processInfo.systemUptime
            consentGeneration = UUID()
            if enabled {
                uploadSession = URLSession(configuration: .ephemeral)
                persist()
            } else {
                uploadSession.invalidateAndCancel()
                forgetIdentity()
            }
        }
    }
    var baseURL: String { didSet { UserDefaults.standard.set(baseURL, forKey: "backendURL") } }
    var uploadToken: String { didSet { UserDefaults.standard.set(uploadToken, forKey: "uploadToken") } }
    var status = "Offline demo · events stay on this device"
    var queue: [AnalyticsEvent] = []
    var sessionID = UUID().uuidString
    var flowID = UUID().uuidString
    var screen = "search"
    var inactivitySeconds: Double = 30
    private var sequence = 0
    private var visitID = UUID().uuidString
    private var foreground = true
    private var checkpointAt = ProcessInfo.processInfo.systemUptime
    private var lastInteraction = ProcessInfo.processInfo.systemUptime
    private var loadingDepth = 0
    private var uploading = false
    private var entered = false
    private var timer: Timer?
    private var consentGeneration = UUID()
    private var uploadSession = URLSession(configuration: .ephemeral)

    init() {
        enabled = UserDefaults.standard.bool(forKey: "analyticsConsent")
        baseURL = UserDefaults.standard.string(forKey: "backendURL") ?? "http://127.0.0.1:3001"
        uploadToken = UserDefaults.standard.string(forKey: "uploadToken") ?? ""
        if enabled {
            if let data = UserDefaults.standard.data(forKey: "analyticsState"), let state = try? JSONDecoder().decode(PersistedAnalytics.self, from: data), UUID(uuidString: state.sessionID) != nil, UUID(uuidString: state.flowID) != nil {
                sessionID = state.sessionID; flowID = state.flowID; queue = state.queue
                sequence = max(state.sequence, queue.filter { $0.sessionId == sessionID }.map(\.sequence).max() ?? 0)
            } else if let data = UserDefaults.standard.data(forKey: "analyticsQueue"), let previousQueue = try? JSONDecoder().decode([AnalyticsEvent].self, from: data) {
                // Upgrade previously queued installations without rewriting event IDs or losing their active flow.
                queue = previousQueue
                if let latest = queue.last { sessionID = latest.sessionId; flowID = latest.flowId }
                sequence = queue.filter { $0.sessionId == sessionID }.map(\.sequence).max() ?? 0
            }
            persist()
        } else { forgetIdentity() }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkpoint(); await self?.flush() }
        }
    }
    func startFlow() { checkpoint(); flowID = UUID().uuidString; entered = false; view("search") }
    func interact() { checkpoint(); lastInteraction = ProcessInfo.processInfo.systemUptime }
    /// Measures visible loading separately; concurrent requests count the union of wait time.
    func beginLoading() { checkpoint(); loadingDepth += 1 }
    func endLoading() { checkpoint(); loadingDepth = max(0, loadingDepth - 1) }
    func view(_ next: String) {
        guard next != screen || !entered else { return }
        checkpoint(); screen = next; visitID = UUID().uuidString; entered = true
        checkpointAt = ProcessInfo.processInfo.systemUptime; lastInteraction = checkpointAt
        emit("screen_viewed", "screen.\(next)", ["visitId": .string(visitID)])
    }
    func setForeground(_ active: Bool) {
        checkpoint(); foreground = active; checkpointAt = ProcessInfo.processInfo.systemUptime
        if active { lastInteraction = checkpointAt; Task { await flush() } }
    }
    func checkpoint() {
        let now = ProcessInfo.processInfo.systemUptime
        defer { checkpointAt = now }
        guard foreground, entered, enabled else { return }
        let foregroundMs = Int(max(0, now - checkpointAt) * 1000)
        let activeMs = min(foregroundMs, Int(max(0, min(now, lastInteraction + inactivitySeconds) - checkpointAt) * 1000))
        guard foregroundMs > 0 else { return }
        emit("screen_duration", "screen.\(screen)", ["visitId": .string(visitID), "foregroundMs": .int(foregroundMs), "activeMs": .int(activeMs)])
        if loadingDepth > 0 { emit("loading_duration", "loading.\(screen)", ["visitId": .string(visitID), "loadingMs": .int(foregroundMs)]) }
    }
    func emit(_ name: String, _ component: String, _ properties: [String: EventValue] = [:]) {
        guard enabled else { return }
        sequence += 1
        queue.append(AnalyticsEvent(name: name, sessionId: sessionID, flowId: flowID, screen: screen, componentId: component, sequence: sequence, properties: properties))
        // Bounded offline storage; booking never waits for upload.
        if queue.count > 10000 { queue.removeFirst(queue.count - 10000) }
        persist()
    }
    private func persist() {
        guard enabled else { return }
        // Store identity, sequence and pending events in one value so a relaunch cannot pair a
        // restored booking draft with a new flow or reuse a previously emitted sequence number.
        let state = PersistedAnalytics(sessionID: sessionID, flowID: flowID, sequence: sequence, queue: queue)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "analyticsState")
            UserDefaults.standard.removeObject(forKey: "analyticsQueue")
        }
    }
    private func forgetIdentity() {
        queue = []; sessionID = UUID().uuidString; flowID = UUID().uuidString; sequence = 0
        visitID = UUID().uuidString; entered = false
        UserDefaults.standard.removeObject(forKey: "analyticsState")
        UserDefaults.standard.removeObject(forKey: "analyticsQueue")
        status = "Product analytics off · local analytics cleared"
    }
    func flush() async {
        guard enabled, !uploading, !queue.isEmpty, let url = URL(string: baseURL + "/api/analytics/events"), ["http", "https"].contains(url.scheme ?? "") else { return }
        uploading = true; defer { uploading = false }
        let batch = Array(queue.prefix(100))
        let generation = consentGeneration
        do {
            var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !uploadToken.isEmpty { request.setValue("Bearer " + uploadToken, forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONEncoder().encode(["events": batch])
            let (_, response) = try await uploadSession.data(for: request)
            guard enabled, generation == consentGeneration else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let ids = Set(batch.map(\.id)); queue.removeAll { ids.contains($0.id) }; persist()
            status = "Connected · \(batch.count) events synced"
        } catch {
            guard enabled, generation == consentGeneration else { return }
            status = "Waiting for backend · \(queue.count) events queued"
        }
    }
}
