import Foundation

// MARK: - Command

struct CommandRequest: Codable, Sendable {
    let transcript: String
    let timezone: String
    let locale: String
    let linkedProviders: [String]
    let latitude: Double?
    let longitude: Double?
    let imageData: String?

    enum CodingKeys: String, CodingKey {
        case transcript, timezone, locale, latitude, longitude
        case linkedProviders = "linked_providers"
        case imageData = "image_data"
    }
}

struct Attachment: Codable, Sendable, Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let url: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case id, filename, url, size
        case mimeType = "mime_type"
    }

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var isPDF: Bool {
        mimeType == "application/pdf"
    }

    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }
}

struct ClarificationResponse: Codable, Sendable {
    let spokenResponse: String
    let question: String
    let options: [String]

    enum CodingKeys: String, CodingKey {
        case spokenResponse = "spoken_response"
        case question, options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spokenResponse = try container.decode(String.self, forKey: .spokenResponse)
        question = try container.decode(String.self, forKey: .question)
        options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
    }
}

struct CommandResponse: Codable, Sendable {
    let spokenResponse: String
    let actionPlan: ActionPlan?
    let deviceActions: [DeviceAction]
    let requiresConfirmation: Bool
    let confirmationPrompt: String?
    let planId: String?
    let attachments: [Attachment]
    let updatedUserName: String?
    let remainingRequests: Int?
    let clarification: ClarificationResponse?

    enum CodingKeys: String, CodingKey {
        case spokenResponse = "spoken_response"
        case actionPlan = "action_plan"
        case deviceActions = "device_actions"
        case requiresConfirmation = "requires_confirmation"
        case confirmationPrompt = "confirmation_prompt"
        case planId = "plan_id"
        case attachments
        case updatedUserName = "updated_user_name"
        case remainingRequests = "remaining_requests"
        case clarification
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spokenResponse = try container.decode(String.self, forKey: .spokenResponse)
        actionPlan = try container.decodeIfPresent(ActionPlan.self, forKey: .actionPlan)
        deviceActions = try container.decodeIfPresent([DeviceAction].self, forKey: .deviceActions) ?? []
        requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? false
        confirmationPrompt = try container.decodeIfPresent(String.self, forKey: .confirmationPrompt)
        planId = try container.decodeIfPresent(String.self, forKey: .planId)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        updatedUserName = try container.decodeIfPresent(String.self, forKey: .updatedUserName)
        remainingRequests = try container.decodeIfPresent(Int.self, forKey: .remainingRequests)
        clarification = try container.decodeIfPresent(ClarificationResponse.self, forKey: .clarification)
    }
}

// MARK: - Action Plan

struct ActionPlan: Codable, Sendable {
    let planId: String
    let userIntent: String
    let steps: [ActionStep]

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case userIntent = "user_intent"
        case steps
    }
}

struct ActionStep: Codable, Sendable {
    let toolName: String
    let args: [String: AnyCodable]
    let riskLevel: String
    let requiresConfirmation: Bool
    let confirmationPhrase: String?
    let executionTarget: String

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case args
        case riskLevel = "risk_level"
        case requiresConfirmation = "requires_confirmation"
        case confirmationPhrase = "confirmation_phrase"
        case executionTarget = "execution_target"
    }
}

// MARK: - Device Actions

struct DeviceAction: Codable, Sendable, Identifiable {
    var id: String { actionId }
    let actionId: String
    let toolName: String
    let args: [String: AnyCodable]
    let idempotencyKey: String

    enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case toolName = "tool_name"
        case args
        case idempotencyKey = "idempotency_key"
    }
}

struct DeviceActionResult: Codable, Sendable {
    let actionId: String
    let idempotencyKey: String
    let success: Bool
    let result: [String: AnyCodable]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case idempotencyKey = "idempotency_key"
        case success, result, error
    }
}

struct DeviceResultRequest: Codable, Sendable {
    let planId: String
    let results: [DeviceActionResult]

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case results
    }
}

struct ConfirmRequest: Codable, Sendable {
    let planId: String

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
    }
}

// MARK: - Auth

struct AuthURLResponse: Codable, Sendable {
    let authUrl: String

    enum CodingKeys: String, CodingKey {
        case authUrl = "auth_url"
    }
}

// MARK: - Health

struct HealthResponse: Codable, Sendable {
    let status: String
}

// MARK: - Calendar

struct UpcomingEventsResponse: Codable, Sendable {
    let events: [CalendarEvent]
}

struct CalendarEvent: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let start: String
    let end: String
    let location: String?
    let allDay: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, location
        case allDay = "all_day"
    }

    var startDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: start) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: start) { return date }
        // All-day events: "2026-02-25"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        return dayFormatter.date(from: start)
    }

    var formattedTime: String {
        if allDay { return "All day" }
        guard let date = startDate else { return start }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Suggestions

struct SuggestionsResponse: Codable, Sendable {
    let suggestions: [String]
}

// MARK: - Briefing

struct BriefingResponse: Codable, Sendable {
    let briefing: String?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case briefing
        case generatedAt = "generated_at"
    }
}

// MARK: - Proactive Notifications

struct PendingNotification: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let suggestedActions: [String]
    let fireAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case suggestedActions = "suggested_actions"
        case fireAt = "fire_at"
    }
}

struct NotificationDeliveredRequest: Codable, Sendable {
    let ids: [String]
}

// MARK: - Subscription

struct SubscriptionStatusResponse: Codable, Sendable {
    let tier: String
    let remainingRequests: Int?

    enum CodingKeys: String, CodingKey {
        case tier
        case remainingRequests = "remaining_requests"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier = try container.decode(String.self, forKey: .tier)
        remainingRequests = try container.decodeIfPresent(Int.self, forKey: .remainingRequests)
    }
}

struct VerifyReceiptRequest: Codable, Sendable {
    let transactionId: String

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
    }
}

// MARK: - Home Widgets

enum HomeWidgetType: String, Codable, CaseIterable, Sendable {
    case calendar
    case email
    case commute
    case briefing
    case weather
}

// MARK: - Widget Data

struct WidgetDataResponse: Codable, Sendable {
    let email: EmailWidgetData?
    let commute: CommuteWidgetData?
}

struct EmailWidgetData: Codable, Sendable {
    let unreadCount: Int
    let topEmails: [EmailPreview]

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
        case topEmails = "top_emails"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        topEmails = try container.decodeIfPresent([EmailPreview].self, forKey: .topEmails) ?? []
    }
}

struct EmailPreview: Codable, Sendable, Identifiable {
    var id: String { "\(sender):\(subject)" }
    let sender: String
    let subject: String
    let snippet: String

    enum CodingKeys: String, CodingKey {
        case sender, subject, snippet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sender = try container.decodeIfPresent(String.self, forKey: .sender) ?? "Unknown"
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? "(no subject)"
        snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""
    }
}

struct CommuteWidgetData: Codable, Sendable {
    let duration: String?
    let durationSeconds: Int?
    let distance: String?
    let destination: String?
    let travelMode: String?

    enum CodingKeys: String, CodingKey {
        case duration, distance, destination
        case durationSeconds = "duration_seconds"
        case travelMode = "travel_mode"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        distance = try container.decodeIfPresent(String.self, forKey: .distance)
        destination = try container.decodeIfPresent(String.self, forKey: .destination)
        travelMode = try container.decodeIfPresent(String.self, forKey: .travelMode)
    }
}

// MARK: - API Error

struct APIErrorResponse: Codable, Sendable {
    let detail: String
}

// MARK: - AnyCodable (Sendable type-erased JSON value)

enum AnyCodable: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self = .object(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let v):
            try container.encode(v)
        case .int(let v):
            try container.encode(v)
        case .double(let v):
            try container.encode(v)
        case .string(let v):
            try container.encode(v)
        case .array(let v):
            try container.encode(v)
        case .object(let v):
            try container.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }
}
