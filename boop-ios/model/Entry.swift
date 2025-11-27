//
//  Entry.swift
//  boop-ios
//
//  Created by Anu Lal on 11/26/25.
//

import Foundation
import SwiftData

@Model
final class Entry {
    var user: UUID
    var timestamp: Date
    
    init(user: UUID) {
        self.user = user
        self.timestamp = Date()
    }
}
