public import Foundation

/// Context for a permission approval request from a provider.
public struct PermissionContext: Sendable {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public let toolUseID: String
    public let toolName: String
    public let toolInput: JSONValue?
    public let timestamp: Date
    public let risk: PermissionRisk?

    /// Human-readable summary for display.
    ///
    /// Shows the tool name with a brief input summary when available.
    public var displaySummary: String {
        if let input = toolInput?["command"]?.stringValue {
            return "\(self.toolName): \(input)"
        }
        if let input = toolInput?["path"]?.stringValue {
            return "\(self.toolName): \(input)"
        }
        return self.toolName
    }
}
