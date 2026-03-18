public import Foundation

// MARK: - PermissionRequest

/// A request from a provider for the user to approve or deny a tool action.
public struct PermissionRequest: Sendable {
    // MARK: Lifecycle

    public init(
        id: String,
        toolName: String,
        toolInput: JSONValue? = nil,
        timestamp: Date,
        risk: PermissionRisk? = nil,
    ) {
        self.id = id
        self.toolName = toolName
        self.toolInput = toolInput
        self.timestamp = timestamp
        self.risk = risk
    }

    // MARK: Public

    public let id: String
    public let toolName: String
    public let toolInput: JSONValue?
    public let timestamp: Date
    public let risk: PermissionRisk?

    /// A human-readable summary of this permission request.
    public var displaySummary: String {
        if let risk {
            return "\(self.toolName) (\(risk))"
        }
        return self.toolName
    }
}

// MARK: - PermissionDecision

/// The user's decision in response to a permission request.
public enum PermissionDecision: Sendable {
    case allow
    case deny(reason: String?)
}
