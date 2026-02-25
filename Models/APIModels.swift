import Foundation

// MARK: - Command

struct CommandRequest: Codable, Sendable {
    let transcript: String
    let timezone: String
    let locale: String
    let linkedProviders: [String]

    enum CodingKeys: String, CodingKey {
        case transcript, timezone, locale
        case linkedProviders = "linked_providers"
    }
}

struct CommandResponse: Codable, Sendable {
    let spokenResponse: String
    let actionPlan: ActionPlan?
    let deviceActions: [DeviceAction]
    let requiresConfirmation: Bool
    let confirmationPrompt: String?
    let planId: String?

    enum CodingKeys: String, CodingKey {
        case spokenResponse = "spoken_response"
        case actionPlan = "action_plan"
        case deviceActions = "device_actions"
        case requiresConfirmation = "requires_confirmation"
        case confirmationPrompt = "confirmation_prompt"
        case planId = "plan_id"
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

struct DeviceAction: Codable, Sendable {
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
}
