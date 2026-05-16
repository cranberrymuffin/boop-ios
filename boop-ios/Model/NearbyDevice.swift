//
//  NearbyDevice.swift
//  boop-ios
//

import Foundation

struct NearbyDevice: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let distance: DevicePositionCategory
    let isSelected: Bool

    var distanceText: String {
        switch distance {
        case .ApproxTouching:
            return "Very close"
        case .InRange:
            return "Nearby"
        case .OutOfRange:
            return "Far"
        case .Unknown:
            return "Unknown"
        }
    }

    var distanceEmoji: String {
        switch distance {
        case .ApproxTouching:
            return "🤝"
        case .InRange:
            return "📡"
        case .OutOfRange:
            return "📍"
        case .Unknown:
            return "❓"
        }
    }
}
