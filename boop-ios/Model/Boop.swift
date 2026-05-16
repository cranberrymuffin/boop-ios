//
//  Boop.swift
//  boop-ios
//
//  Created by Anu Lal on 11/26/25.
//

import Foundation
import SwiftUI

struct Boop: Equatable {
    let senderUUID: UUID
    let displayName: String
    let birthday: Date?
    let bio: String?
    let gradientColors: [Color]
}

struct BoopEvent: Equatable, Identifiable {
    let id = UUID()
    let boop: Boop
    let timestamp: Date

    init(boop: Boop) {
        self.boop = boop
        self.timestamp = Date()
    }
}
