package import Foundation

// MARK: - PermissionRequest

/// A request from a provider for the user to approve or deny a tool action.
package struct PermissionRequest: Sendable {
    // MARK: Lifecycle

    package init(
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

    // MARK: Package

    package let id: String
    package let toolName: String
    package let toolInput: JSONValue?
    package let timestamp: Date
    package let risk: PermissionRisk?

    /// A human-readable summary of this permission request.
    package var displaySummary: String {
        if let risk {
            return "\(self.toolName) (\(risk))"
        }
        return self.toolName
    }
}

// MARK: - PermissionDecision

/// The user's decision in response to a permission request.
package enum PermissionDecision: Sendable {
    case allow
    case deny(reason: String?)
}
