import Foundation
import SwiftData
import SwiftUI

@Model
final class UserProfile {
    var name: String
    var createdAt: Date
    var birthday: Date?
    var bio: String?
    var gradientColorsData: [String] = []
    var avatarData: Data?

    init(name: String, birthday: Date? = nil, bio: String? = nil, gradientColors: [Color] = [], avatarData: Data? = nil) {
        self.name = name
        self.birthday = birthday
        self.bio = bio
        self.createdAt = Date()
        self.gradientColorsData = gradientColors.map { Self.colorToString($0) }
        self.avatarData = avatarData
    }
    
    var gradientColors: [Color] {
        gradientColorsData.compactMap { Self.stringToColor($0) }
    }
    
    private static func colorToString(_ color: Color) -> String {
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
    
    private static func stringToColor(_ colorString: String) -> Color? {
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
