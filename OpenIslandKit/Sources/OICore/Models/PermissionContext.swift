package import Foundation

/// Context for a permission approval request from a provider.
package struct PermissionContext: Sendable {
    // MARK: Lifecycle

    package init(
        toolUseID: String,
        toolName: String,
        toolInput: JSONValue? = nil,
        timestamp: Date,
        risk: PermissionRisk? = nil,
    ) {
        self.toolUseID = toolUseID
        self.toolName = toolName
        self.toolInput = toolInput
        self.timestamp = timestamp
        self.risk = risk
    }

    // MARK: Package

    package let toolUseID: String
    package let toolName: String
    package let toolInput: JSONValue?
    package let timestamp: Date
    package let risk: PermissionRisk?

    /// Human-readable summary for display.
    ///
    /// Shows the tool name with a brief input summary when available.
    package var displaySummary: String {
        if let input = toolInput?["command"]?.stringValue {
            return "\(self.toolName): \(input)"
        }
        if let input = toolInput?["path"]?.stringValue {
            return "\(self.toolName): \(input)"
        }
        return self.toolName
    }
}
