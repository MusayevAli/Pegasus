import Foundation

enum V2APIError: LocalizedError, Sendable {
    case invalidURL, invalidResponse, rejected(status: Int, message: String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid backend address in settings."
        case .invalidResponse: "The service returned an invalid response. Please retry."
        case .rejected(_, let message): message
        }
    }
}

protocol BookingV2Client: Sendable {
    func request(path: String, method: String, body: Data?) async throws -> Data
}

struct BookingV2HTTPClient: BookingV2Client {
    var baseURL: String
    var token: String = ""
    func request(path: String, method: String = "POST", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path), ["http", "https"].contains(url.scheme) else { throw V2APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.timeoutInterval = path.contains("/ai/") || path.contains("/search/alternatives") ? 50 : (path.contains("/flights/search") ? 35 : 20)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw V2APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = json?["error"] as? String ?? "Service unavailable"
            let message = json?["message"] as? String ?? code.replacingOccurrences(of: "_", with: " ")
            throw V2APIError.rejected(status: http.statusCode, message: message)
        }
        return data
    }
}

extension BookingV2Client {
    func get<Response: Decodable>(_ path: String, as: Response.Type = Response.self) async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await request(path: path, method: "GET", body: nil))
    }
    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, as: Response.Type = Response.self) async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await request(path: path, method: "POST", body: JSONEncoder().encode(body)))
    }
}
