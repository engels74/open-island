/// Sound to play when a session needs user attention.
public enum NotificationSound: String, Sendable, Hashable, Codable, CaseIterable {
    case `default`
    case subtle
    case chime
    case none
}
