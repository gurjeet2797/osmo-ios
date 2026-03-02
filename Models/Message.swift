import Foundation

struct Message: Identifiable, Sendable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    var categories: Categories?
    var tags: [String]?
    var planId: String?
    var requiresConfirmation: Bool
    var deviceActions: [DeviceAction]
    var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        content: String,
        isUser: Bool,
        timestamp: Date = Date(),
        categories: Categories? = nil,
        tags: [String]? = nil,
        planId: String? = nil,
        requiresConfirmation: Bool = false,
        deviceActions: [DeviceAction] = [],
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.categories = categories
        self.tags = tags
        self.planId = planId
        self.requiresConfirmation = requiresConfirmation
        self.deviceActions = deviceActions
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id, content, isUser, timestamp, categories, tags, planId
        case requiresConfirmation, deviceActions, attachments
    }
}

struct Conversation: Identifiable, Sendable, Codable {
    let id: UUID
    var messages: [Message]
    let createdAt: Date

    init(id: UUID = UUID(), messages: [Message] = [], createdAt: Date = Date()) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
    }
}

// MARK: - Category Models (customize these for your app)

struct Categories: Sendable, Codable {
    let category1: String
    let category2: String
    let category3: String
    let category4: String
}
