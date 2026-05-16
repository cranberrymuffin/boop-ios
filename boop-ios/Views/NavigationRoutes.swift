import SwiftData

struct ProfileHistoryRoute: Hashable {}

struct ContactHistoryRoute: Hashable {
    let contact: Contact

    static func == (lhs: ContactHistoryRoute, rhs: ContactHistoryRoute) -> Bool {
        lhs.contact.uuid == rhs.contact.uuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contact.uuid)
    }
}
