import Foundation

enum QuoteExpiry {
    /// Node emits millisecond precision; also accept whole-second ISO 8601 provider timestamps.
    static func date(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timestamp)
    }
}

struct GuidanceCard: Codable, Identifiable {
    var id: String
    var type: String
    var passengerIds: [String]
    var segmentIds: [String]
    var productIds: [String]
    var explanation: String
    var clarificationChoices: [String]
    var requiresConfirmation: Bool
}
struct GuidanceResponse: Codable { var revision: Int; var source: String; var cards: [GuidanceCard] }
struct PackingItem: Codable, Identifiable, Sendable {
    var category: String
    var label: String
    var confidence: String
    var id: String { category }
}
typealias PackingDetectedItem = PackingItem
struct PackingResponse: Codable {
    var revision: Int; var source: String; var candidates: [String]
    var model: String? = nil
    var summary: String? = nil
    var items: [PackingItem]? = nil
    var questions: [String]? = nil
    var requiresConfirmation: Bool? = nil
    var notice: String? = nil
}

enum BackendError: LocalizedError {
    case unavailable, invalidResponse
    var errorDescription: String? { "The service is unavailable. Your offline booking is safe; please try again." }
}

struct BackendAPI: Sendable, AIPlanningClient {
    var baseURL: String
    var token: String = ""
    func aiConnection() async throws -> AIConnection {
        guard let url = URL(string: baseURL + "/api/ai/status") else { throw BackendError.unavailable }
        var request = URLRequest(url: url); request.timeoutInterval = 8
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw BackendError.unavailable }
        return try JSONDecoder().decode(AIConnection.self, from: data)
    }
    func tripPlan(_ request: AIPlanRequest) async throws -> AITripPlan {
        guard let url = URL(string: baseURL + "/api/ai/plan") else { throw BackendError.unavailable }
        var http = URLRequest(url: url); http.httpMethod = "POST"; http.timeoutInterval = 20
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { http.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        http.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: http)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw BackendError.unavailable }
        let plan = try JSONDecoder().decode(AITripPlan.self, from: data)
        guard AIPlanner.validate(plan) else { throw BackendError.invalidResponse }
        return plan
    }
    func post<T: Decodable>(_ path: String, body: [String: Any], as: T.Type) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw BackendError.unavailable }
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw BackendError.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
