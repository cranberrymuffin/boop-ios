//
//  NotificationIntent.swift
//  boop-ios
//

import Foundation
import SwiftData

enum NotificationTypeIdentifier: String, Codable {
    case contactReminder
    case weeklyPlanning
}

@Model
final class NotificationIntent {
    var id: UUID
    var typeIdentifier: NotificationTypeIdentifier
    var entityUUID: UUID?
    var title: String
    var body: String

    // Trigger config (stored as primitives for SwiftData)
    var triggerKind: NotificationTriggerKind
    var triggerInterval: CadenceInterval?
    var triggerWeekday: Int?        // 1=Sunday ... 7=Saturday
    var triggerHour: Int?
    var triggerMinute: Int?

    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Deterministic notification identifier used for OS scheduling.
    var notificationIdentifier: String {
        "\(typeIdentifier.rawValue).\(entityUUID?.uuidString ?? "global")"
    }

    init(
        id: UUID = UUID(),
        typeIdentifier: NotificationTypeIdentifier,
        entityUUID: UUID? = nil,
        title: String,
        body: String,
        triggerKind: NotificationTriggerKind,
        triggerInterval: CadenceInterval? = nil,
        triggerWeekday: Int? = nil,
        triggerHour: Int? = nil,
        triggerMinute: Int? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.typeIdentifier = typeIdentifier
        self.entityUUID = entityUUID
        self.title = title
        self.body = body
        self.triggerKind = triggerKind
        self.triggerInterval = triggerInterval
        self.triggerWeekday = triggerWeekday
        self.triggerHour = triggerHour
        self.triggerMinute = triggerMinute
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
