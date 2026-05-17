import Foundation

private let fullRelativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()

private let abbreviatedRelativeDateFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.dateTimeStyle = .named
    f.unitsStyle = .abbreviated
    return f
}()

extension Date {
    /// Returns a localized relative time string (e.g. "2 hours ago").
    /// Pass `abbreviated: true` for compact display (e.g. "2 hr. ago").
    func relativeString(abbreviated: Bool = false) -> String {
        let formatter = abbreviated ? abbreviatedRelativeDateFormatter : fullRelativeDateFormatter
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    /// Returns a time-group header string for timeline displays ("Last Hour", "Today", or a relative date).
    func relativeGroupHeader() -> String {
        let text = relativeString().capitalized
        let sanitized = text.trimmingCharacters(in: .whitespaces).lowercased()
        let words = sanitized.components(separatedBy: .whitespaces)
        if words.contains(where: { $0.contains("minute") }) { return "Last Hour" }
        if words.contains(where: { $0.contains("hour") }) { return "Today" }
        return text
    }
}
