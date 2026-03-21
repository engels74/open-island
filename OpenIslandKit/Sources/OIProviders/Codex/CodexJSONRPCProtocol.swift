package import Foundation
package import OICore

// MARK: - JSONRPCRequestID

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

package enum CodexServerRequest: String, Sendable {
    case commandExecutionRequestApproval = "item/commandExecution/requestApproval"
    case fileChangeRequestApproval = "item/fileChange/requestApproval"
}

// MARK: - CodexThreadItemType

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

/// Tagged union — the `type` field determines which optional fields are populated.
package struct CodexThreadItem: Sendable, Codable {
    // MARK: Package

    package let type: CodexThreadItemType
    package let itemID: String?

    package let text: String?
    package let summaryText: String?

    package let command: String?
    package let cwd: String?
    package let status: String?
    package let exitCode: Int?
    package let durationMs: Int?
    package let output: String?

    package let path: String?
    package let kind: String?
    package let diff: String?

    package let server: String?
    package let tool: String?
    package let arguments: JSONValue?
    package let result: JSONValue?

    package let taskID: String?
    package let parentToolID: String?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case type
        case itemID = "id"
        case text
        case summaryText
        case command
        case cwd
        case status
        case exitCode
        case durationMs
        case output
        case path
        case kind
        case diff
        case server
        case tool
        case arguments
        case result
        case taskID = "taskId"
        case parentToolID = "parentToolId"
    }
}

// MARK: - CodexTurnStatus

package enum CodexTurnStatus: String, Sendable, Codable {
    case completed
    case interrupted
    case failed
}

// MARK: - CodexTurnCompletedParams

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

package enum CodexApprovalDecision: String, Sendable, Codable {
    case accept
    case decline
}

// MARK: - CodexApprovalResponse

package struct CodexApprovalResponse: Sendable, Codable {
    // MARK: Lifecycle

    package init(decision: CodexApprovalDecision) {
        self.decision = decision
    }

    // MARK: Package

    package let decision: CodexApprovalDecision
}

// MARK: - CodexApprovalPolicy

package enum CodexApprovalPolicy: String, Sendable, Codable {
    case untrusted
    case onRequest = "on-request"
    case never
}

// MARK: - CodexSandboxMode

package enum CodexSandboxMode: String, Sendable, Codable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

// MARK: - CodexExecEventType

package enum CodexExecEventType: String, Sendable, Codable {
    case threadStarted = "thread.started"
    case turnStarted = "turn.started"
    case itemStarted = "item.started"
    case itemCompleted = "item.completed"
    case turnCompleted = "turn.completed"
}

// MARK: - CodexExecEvent

package struct CodexExecEvent: Sendable, Codable {
    package let type: CodexExecEventType
    package let data: JSONValue?
}
