package import Foundation
package import OICore

// MARK: - JSONRPCRequestID

/// A JSON-RPC 2.0 request identifier. Can be a string or integer per the spec.
package enum JSONRPCRequestID: Sendable, Hashable, Codable {
    case string(String)
    case int(Int)

    // MARK: Lifecycle

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON-RPC ID must be a string or integer",
            )
        }
    }

    // MARK: Package

    package var stringRepresentation: String {
        switch self {
        case let .string(str): str
        case let .int(intVal): String(intVal)
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(str): try container.encode(str)
        case let .int(intVal): try container.encode(intVal)
        }
    }
}

// MARK: - JSONRPCError

/// A JSON-RPC 2.0 error object.
package struct JSONRPCError: Sendable, Codable {
    // MARK: Lifecycle

    package init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // MARK: Package

    package let code: Int
    package let message: String
    package let data: JSONValue?
}

// MARK: - JSONRPCErrorCode

package enum JSONRPCErrorCode {
    package static let parseError = -32700
    package static let invalidRequest = -32600
    package static let methodNotFound = -32601
    package static let invalidParams = -32602
    package static let internalError = -32603
}

// MARK: - JSONRPCRequest

/// A JSON-RPC 2.0 request message (client → server or server → client).
package struct JSONRPCRequest: Sendable, Codable {
    // MARK: Lifecycle

    package init(id: JSONRPCRequestID, method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    // MARK: Package

    package let jsonrpc: String
    package let id: JSONRPCRequestID
    package let method: String
    package let params: JSONValue?
}

// MARK: - JSONRPCResponse

/// A JSON-RPC 2.0 response message.
package struct JSONRPCResponse: Sendable, Codable {
    // MARK: Lifecycle

    package init(id: JSONRPCRequestID, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    package init(id: JSONRPCRequestID, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }

    // MARK: Package

    package let jsonrpc: String
    package let id: JSONRPCRequestID
    package let result: JSONValue?
    package let error: JSONRPCError?
}

// MARK: - JSONRPCNotification

/// A JSON-RPC 2.0 notification message (no `id` field, no response expected).
package struct JSONRPCNotification: Sendable, Codable {
    // MARK: Lifecycle

    package init(method: String, params: JSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }

    // MARK: Package

    package let jsonrpc: String
    package let method: String
    package let params: JSONValue?
}

// MARK: - JSONRPCMessage

/// A decoded JSON-RPC 2.0 message — one of request, response, or notification.
///
/// Discriminated by the presence of `id` and `method` fields:
/// - `method` + `id` → request
/// - `method`, no `id` → notification
/// - `id`, no `method` → response
package enum JSONRPCMessage: Sendable {
    case request(JSONRPCRequest)
    case response(JSONRPCResponse)
    case notification(JSONRPCNotification)
}

// MARK: Codable

extension JSONRPCMessage: Codable {
    private enum DiscriminatorKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
        case result
        case error
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let hasID = container.contains(.id)
        let hasMethod = container.contains(.method)

        if hasMethod, hasID {
            self = try .request(JSONRPCRequest(from: decoder))
        } else if hasMethod {
            self = try .notification(JSONRPCNotification(from: decoder))
        } else if hasID {
            self = try .response(JSONRPCResponse(from: decoder))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Cannot determine JSON-RPC message type: no 'id' or 'method' field",
                ),
            )
        }
    }

    package func encode(to encoder: any Encoder) throws {
        switch self {
        case let .request(req): try req.encode(to: encoder)
        case let .response(res): try res.encode(to: encoder)
        case let .notification(notif): try notif.encode(to: encoder)
        }
    }
}

// MARK: - CodexClientMethod

/// Methods the client can call on the Codex app-server.
package enum CodexClientMethod: String, Sendable {
    case initialize
    case threadStart = "thread/start"
    case threadResume = "thread/resume"
    case threadList = "thread/list"
    case turnStart = "turn/start"
    case turnInterrupt = "turn/interrupt"
    case configRead = "config/read"
    case modelList = "model/list"
}

// MARK: - CodexServerNotification

/// Notification methods sent by the Codex app-server to the client.
package enum CodexServerNotification: String, Sendable {
    // Turn lifecycle
    case turnStarted = "turn/started"
    case turnCompleted = "turn/completed"
    case turnDiffUpdated = "turn/diff/updated"
    case turnPlanUpdated = "turn/plan/updated"

    // Item lifecycle
    case itemStarted = "item/started"
    case itemCompleted = "item/completed"

    // Streaming deltas
    case agentMessageDelta = "item/agentMessage/delta"
    case reasoningSummaryTextDelta = "item/reasoning/summaryTextDelta"
    case commandExecutionOutputDelta = "item/commandExecution/outputDelta"
}

// MARK: - CodexServerRequest

/// Request methods sent by the Codex app-server to the client (approval interception).
package enum CodexServerRequest: String, Sendable {
    case commandExecutionRequestApproval = "item/commandExecution/requestApproval"
    case fileChangeRequestApproval = "item/fileChange/requestApproval"
}

// MARK: - CodexThreadItemType

/// The type tag for items within a Codex conversation thread.
///
/// Each item in the thread has a `type` field that identifies the content kind.
/// The app-server sends `item/started` and `item/completed` events for each.
package enum CodexThreadItemType: String, Sendable, Codable {
    case userMessage
    case agentMessage
    case reasoning
    case commandExecution
    case fileChange
    case mcpToolCall
    case webSearch
    case imageView
    case enteredReviewMode
    case compacted
    case collabToolCall
}

// MARK: - CodexThreadItem

/// A single item in a Codex conversation thread.
///
/// This is the tagged union — the `type` field determines which optional
/// fields are populated.
package struct CodexThreadItem: Sendable, Codable {
    /// The item type tag.
    package let type: CodexThreadItemType

    /// Server-assigned unique identifier for this item.
    package let itemID: String?

    // MARK: - userMessage / agentMessage fields

    /// Text content for userMessage or agentMessage items.
    package let text: String?

    // MARK: - reasoning fields

    /// Summary text for reasoning items.
    package let summaryText: String?

    // MARK: - commandExecution fields

    /// The shell command string.
    package let command: String?

    /// Working directory for the command.
    package let cwd: String?

    /// Execution status (e.g., "running", "completed", "failed").
    package let status: String?

    /// Process exit code.
    package let exitCode: Int?

    /// Execution duration in milliseconds.
    package let durationMs: Int?

    /// Stdout/stderr output from command execution.
    package let output: String?

    // MARK: - fileChange fields

    /// File path for fileChange items.
    package let path: String?

    /// Kind of change (e.g., "create", "modify", "delete").
    package let kind: String?

    /// Unified diff content for the file change.
    package let diff: String?

    // MARK: - mcpToolCall fields

    /// MCP server name.
    package let server: String?

    /// MCP tool name.
    package let tool: String?

    /// MCP tool arguments.
    package let arguments: JSONValue?

    /// MCP tool result.
    package let result: JSONValue?

    // MARK: - collabToolCall fields

    /// Task identifier for subagent/collab items.
    package let taskID: String?

    /// Parent tool use ID that spawned this collab call.
    package let parentToolID: String?
}

// MARK: - CodexTurnStatus

/// Status of a completed turn.
package enum CodexTurnStatus: String, Sendable, Codable {
    case completed
    case interrupted
    case failed
}

// MARK: - CodexTurnCompletedParams

/// Parameters for the `turn/completed` notification.
package struct CodexTurnCompletedParams: Sendable, Codable {
    // MARK: Package

    package let status: CodexTurnStatus
    package let promptTokens: Int?
    package let completionTokens: Int?
    package let totalTokens: Int?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case status
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - CodexCommandApprovalParams

/// Parameters for `item/commandExecution/requestApproval`.
package struct CodexCommandApprovalParams: Sendable, Codable {
    // MARK: Package

    package let itemID: String
    package let reason: String?
    package let risk: String?
    package let parsedCmd: JSONValue?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case reason
        case risk
        case parsedCmd = "parsed_cmd"
    }
}

// MARK: - CodexFileChangeApprovalParams

/// Parameters for `item/fileChange/requestApproval`.
package struct CodexFileChangeApprovalParams: Sendable, Codable {
    // MARK: Package

    package let itemID: String
    package let path: String?
    package let kind: String?
    package let grantRoot: String?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case path
        case kind
        case grantRoot = "grant_root"
    }
}

// MARK: - CodexApprovalDecision

/// Decision sent back to the server for an approval request.
package enum CodexApprovalDecision: String, Sendable, Codable {
    case accept
    case decline
}

// MARK: - CodexApprovalResponse

/// Response payload for approval requests.
package struct CodexApprovalResponse: Sendable, Codable {
    // MARK: Lifecycle

    package init(decision: CodexApprovalDecision) {
        self.decision = decision
    }

    // MARK: Package

    package let decision: CodexApprovalDecision
}

// MARK: - CodexApprovalPolicy

/// The approval policy controlling when the server requests approval.
package enum CodexApprovalPolicy: String, Sendable, Codable {
    /// Ask for approval on every action.
    case untrusted
    /// Ask only for risky actions.
    case onRequest = "on-request"
    /// Never ask — auto-approve everything.
    case never
}

// MARK: - CodexSandboxMode

/// macOS Seatbelt sandbox configuration for Codex.
package enum CodexSandboxMode: String, Sendable, Codable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

// MARK: - CodexExecEventType

/// Event types emitted by `codex exec --json` on stdout.
package enum CodexExecEventType: String, Sendable, Codable {
    case threadStarted = "thread.started"
    case turnStarted = "turn.started"
    case itemStarted = "item.started"
    case itemCompleted = "item.completed"
    case turnCompleted = "turn.completed"
}

// MARK: - CodexExecEvent

/// A single event from `codex exec --json` JSONL output.
package struct CodexExecEvent: Sendable, Codable {
    package let type: CodexExecEventType
    package let data: JSONValue?
}
