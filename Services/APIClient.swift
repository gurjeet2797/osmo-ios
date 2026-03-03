import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .unauthorized:
            "Session expired. Please sign in again."
        case .serverError(let code, let message):
            "Server error (\(code)): \(message)"
        case .networkError(let error):
            "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

final class APIClient: Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Auth

    func startGoogleAuth() async throws -> URL {
        let response: AuthURLResponse = try await post(path: "/auth/google", body: Empty?.none)
        guard let url = URL(string: response.authUrl) else {
            throw APIError.invalidURL
        }
        return url
    }

    // MARK: - Commands

    func sendCommand(transcript: String, timezone: String? = nil, locale: String? = nil, latitude: Double? = nil, longitude: Double? = nil, imageData: String? = nil) async throws -> CommandResponse {
        let request = CommandRequest(
            transcript: transcript,
            timezone: timezone ?? TimeZone.current.identifier,
            locale: locale ?? Locale.current.identifier,
            linkedProviders: ["google_calendar", "google_gmail"],
            latitude: latitude,
            longitude: longitude,
            imageData: imageData
        )
        return try await post(path: "/command", body: request)
    }

    func confirmPlan(planId: String) async throws -> CommandResponse {
        let request = ConfirmRequest(planId: planId)
        return try await post(path: "/command/confirm", body: request)
    }

    func reportDeviceResults(planId: String, results: [DeviceActionResult]) async throws -> [String: AnyCodable] {
        let request = DeviceResultRequest(planId: planId, results: results)
        return try await post(path: "/command/device-result", body: request)
    }

    // MARK: - Calendar

    func fetchUpcomingEvents(days: Int = 1) async throws -> [CalendarEvent] {
        let response: UpcomingEventsResponse = try await get(path: "/calendar/upcoming?days=\(days)")
        return response.events
    }

    // MARK: - Suggestions

    func fetchSuggestions() async throws -> [String] {
        let response: SuggestionsResponse = try await get(path: "/suggestions")
        return response.suggestions
    }

    // MARK: - Briefing

    func fetchBriefing() async throws -> BriefingResponse {
        return try await get(path: "/command/briefing")
    }

    // MARK: - Proactive Notifications

    func fetchPendingNotifications() async throws -> [PendingNotification] {
        return try await get(path: "/notifications/pending")
    }

    func markNotificationsDelivered(_ ids: [String]) async throws {
        let body = NotificationDeliveredRequest(ids: ids)
        let _: [String: AnyCodable] = try await post(path: "/notifications/delivered", body: body)
    }

    // MARK: - Preferences

    func fetchPreferences() async throws -> [String: String] {
        return try await get(path: "/preferences")
    }

    func savePreferences(_ prefs: [String: String]) async throws -> [String: String] {
        return try await put(path: "/preferences", body: prefs)
    }

    // MARK: - Subscription

    func fetchSubscriptionStatus() async throws -> SubscriptionStatusResponse {
        return try await get(path: "/subscription/status")
    }

    func verifyReceipt(transactionId: String) async throws -> [String: AnyCodable] {
        let body = VerifyReceiptRequest(transactionId: transactionId)
        return try await post(path: "/subscription/verify", body: body)
    }

    // MARK: - Widgets

    func fetchWidgetData(widgets: [String] = ["email", "commute"]) async throws -> WidgetDataResponse {
        let joined = widgets.joined(separator: ",")
        return try await get(path: "/widgets/data?widgets=\(joined)")
    }

    // MARK: - Session

    func clearSession() async throws {
        let _: [String: AnyCodable] = try await post(path: "/command/session/clear", body: Empty?.none)
    }

    // MARK: - Health

    func healthCheck() async throws -> Bool {
        let _: HealthResponse = try await get(path: "/health")
        return true
    }

    // MARK: - Private

    private func get<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)
        return try await perform(request)
    }

    private func put<T: Decodable, B: Encodable>(path: String, body: B?) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        return try await perform(request)
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B?) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let message: String
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                message = errorResponse.detail
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw APIError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func addAuthHeader(to request: inout URLRequest) {
        if let token = KeychainHelper.read(.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

// Helper for POST with no body
private struct Empty: Encodable {}
