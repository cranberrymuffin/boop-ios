//
//  Contact.swift
//  boop-ios
//
//  Created by Anu Lal on 11/26/25.
//


import Foundation
import SwiftData
import SwiftUI

@Model
final class Contact {
    var uuid: UUID
    var displayName: String
    var birthday: Date?
    var bio: String?
    var gradientColorsData: [String] = []

    // Relationship with cascade delete - when Contact is deleted, its interactions are too
    @Relationship(deleteRule: .cascade, inverse: \BoopInteraction.contact)
    var interactions: [BoopInteraction]

    init(uuid: UUID, displayName: String, birthday: Date? = nil, bio: String? = nil, gradientColors: [Color] = [], interactions: [BoopInteraction] = []) {
        self.uuid = uuid
        self.displayName = displayName
        self.birthday = birthday
        self.bio = bio
        self.gradientColorsData = gradientColors.map { Self.colorToString($0) }
        self.interactions = interactions
    }
    
    var gradientColors: [Color] {
        guard !gradientColorsData.isEmpty else {
            // Default gradient if none set
            return [.purple, .blue, .purple, .blue, .purple, .blue, .purple, .blue, .purple]
        }
        return gradientColorsData.compactMap { Self.stringToColor($0) }
    }
    
    static func colorToString(_ color: Color) -> String {
        if color == .red { return "red" }
        if color == .orange { return "orange" }
        if color == .yellow { return "yellow" }
        if color == .green { return "green" }
        if color == .cyan { return "cyan" }
        if color == .blue { return "blue" }
        if color == .indigo { return "indigo" }
        if color == .purple { return "purple" }
        if color == .pink { return "pink" }
        if color == .mint { return "mint" }
        if color == .teal { return "teal" }
        if color == .brown { return "brown" }
        if color == .white { return "white" }
        if color == .black { return "black" }
        if color == .gray { return "gray" }
        return "purple" // default
    }
    
    static func stringToColor(_ colorString: String) -> Color? {
        switch colorString {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "mint": return .mint
        case "teal": return .teal
        case "brown": return .brown
        case "white": return .white
        case "black": return .black
        case "gray": return .gray
        default: return nil
        }
    }
}
