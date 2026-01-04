import Foundation
import SwiftData

@Model
final class UserProfile {
    var appleUserID: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var createdAt: Date

    init(appleUserID: String, firstName: String, lastName: String, dateOfBirth: Date) {
        self.appleUserID = appleUserID
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.createdAt = Date()
    }

    var displayName: String {
        "\(firstName) \(lastName)"
    }

    var age: Int {
        let calendar = Calendar.current
        let birthComponents = calendar.dateComponents([.year], from: dateOfBirth)
        let todayComponents = calendar.dateComponents([.year], from: Date())
        return (todayComponents.year ?? 0) - (birthComponents.year ?? 0)
    }

    var isAdult: Bool {
        age >= 18
    }
}
