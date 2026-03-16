import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - CodexEventNormalizerTurnTests

@Suite(.tags(.codex))
struct CodexEventNormalizerTurnTests {
    let sessionID: SessionID = "codex-test-session"

    @Test
    func `turnStarted normalizes to processingStarted`() throws {
        let notification = JSONRPCNotification(method: "turn/started")
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .processingStarted(sid) = events.first else {
            Issue.record("Expected .processingStarted, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
    }

    @Test
    func `turnCompleted normalizes to waitingForInput`() throws {
        let notification = JSONRPCNotification(method: "turn/completed")
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .waitingForInput(sid) = events.first else {
            Issue.record("Expected .waitingForInput, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
    }

    @Test
    func `turnCompleted with token usage emits tokenUsage then waitingForInput`() throws {
        let params: JSONValue = .object([
            "prompt_tokens": .int(100),
            "completion_tokens": .int(50),
            "total_tokens": .int(150),
        ])
        let notification = JSONRPCNotification(method: "turn/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 2)

        guard case let .tokenUsage(sid1, prompt, completion, total) = events[0] else {
            Issue.record("Expected .tokenUsage, got \(events[0])")
            return
        }
        #expect(sid1 == self.sessionID)
        #expect(prompt == 100)
        #expect(completion == 50)
        #expect(total == 150)

        guard case let .waitingForInput(sid2) = events[1] else {
            Issue.record("Expected .waitingForInput, got \(events[1])")
            return
        }
        #expect(sid2 == self.sessionID)
    }

    @Test
    func `turnDiffUpdated normalizes to diffUpdated`() throws {
        let params: JSONValue = .object(["diff": .string("--- a/file\n+++ b/file")])
        let notification = JSONRPCNotification(method: "turn/diff/updated", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .diffUpdated(sid, diff) = events.first else {
            Issue.record("Expected .diffUpdated, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
        #expect(diff == "--- a/file\n+++ b/file")
    }

    @Test
    func `agentMessageDelta normalizes to modelResponse`() throws {
        let params: JSONValue = .object(["delta": .string("Hello, world!")])
        let notification = JSONRPCNotification(method: "item/agentMessage/delta", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .modelResponse(sid, textDelta) = events.first else {
            Issue.record("Expected .modelResponse, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
        #expect(textDelta == "Hello, world!")
    }

    @Test
    func `agentMessageDelta without delta defaults to empty string`() throws {
        let notification = JSONRPCNotification(method: "item/agentMessage/delta")
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .modelResponse(_, textDelta) = events.first else {
            Issue.record("Expected .modelResponse")
            return
        }
        #expect(textDelta.isEmpty)
    }

    @Test
    func `turnPlanUpdated returns empty array`() throws {
        let notification = JSONRPCNotification(method: "turn/plan/updated")
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.isEmpty)
    }

    @Test
    func `reasoningSummaryTextDelta returns empty array`() throws {
        let notification = JSONRPCNotification(method: "item/reasoning/summaryTextDelta")
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.isEmpty)
    }

    @Test
    func `commandExecutionOutputDelta returns empty array`() throws {
        let notification = JSONRPCNotification(method: "item/commandExecution/outputDelta")
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.isEmpty)
    }

    @Test
    func `unknown method throws unknownEventType`() {
        let notification = JSONRPCNotification(method: "some/unknown/method")
        #expect(throws: EventNormalizationError.self) {
            _ = try CodexEventNormalizer.normalize(notification, sessionID: sessionID)
        }
    }
}

// MARK: - CodexEventNormalizerItemStartedTests

@Suite(.tags(.codex))
struct CodexEventNormalizerItemStartedTests {
    let sessionID: SessionID = "codex-test-session"

    @Test
    func `commandExecution started normalizes to toolStarted`() throws {
        let params: JSONValue = .object([
            "type": .string("commandExecution"),
            "itemId": .string("item-1"),
            "command": .string("ls -la"),
        ])
        let notification = JSONRPCNotification(method: "item/started", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .toolStarted(sid, toolEvent) = events.first else {
            Issue.record("Expected .toolStarted, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
        #expect(toolEvent.name == "commandExecution")
    }

    @Test
    func `fileChange started normalizes to toolStarted`() throws {
        let params: JSONValue = .object([
            "type": .string("fileChange"),
            "itemId": .string("item-2"),
            "path": .string("/tmp/file.txt"),
            "kind": .string("modify"),
        ])
        let notification = JSONRPCNotification(method: "item/started", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .toolStarted(sid, toolEvent) = events.first else {
            Issue.record("Expected .toolStarted")
            return
        }
        #expect(sid == self.sessionID)
        #expect(toolEvent.name == "fileChange")
    }

    @Test
    func `mcpToolCall started normalizes to toolStarted with server prefix`() throws {
        let params: JSONValue = .object([
            "type": .string("mcpToolCall"),
            "itemId": .string("item-3"),
            "tool": .string("readFile"),
            "server": .string("filesystem"),
        ])
        let notification = JSONRPCNotification(method: "item/started", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .toolStarted(_, toolEvent) = events.first else {
            Issue.record("Expected .toolStarted")
            return
        }
        #expect(toolEvent.name == "mcp(filesystem): readFile")
    }

    @Test
    func `mcpToolCall started without server uses tool name only`() throws {
        let params: JSONValue = .object([
            "type": .string("mcpToolCall"),
            "itemId": .string("item-4"),
            "tool": .string("readFile"),
        ])
        let notification = JSONRPCNotification(method: "item/started", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        guard case let .toolStarted(_, toolEvent) = events.first else {
            Issue.record("Expected .toolStarted")
            return
        }
        #expect(toolEvent.name == "readFile")
    }

    @Test
    func `collabToolCall started normalizes to subagentStarted`() throws {
        let params: JSONValue = .object([
            "type": .string("collabToolCall"),
            "taskId": .string("task-1"),
            "parentToolId": .string("parent-1"),
        ])
        let notification = JSONRPCNotification(method: "item/started", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .subagentStarted(sid, taskID, parentToolID) = events.first else {
            Issue.record("Expected .subagentStarted, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
        #expect(taskID == "task-1")
        #expect(parentToolID == "parent-1")
    }

    @Test
    func `userMessage started returns empty array`() throws {
        let params: JSONValue = .object(["type": .string("userMessage")])
        let notification = JSONRPCNotification(method: "item/started", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.isEmpty)
    }

    @Test
    func `missing type throws missingRequiredField`() {
        let notification = JSONRPCNotification(method: "item/started", params: .object([:]))
        #expect(throws: EventNormalizationError.self) {
            _ = try CodexEventNormalizer.normalize(notification, sessionID: sessionID)
        }
    }
}

// MARK: - CodexEventNormalizerItemCompletedTests

@Suite(.tags(.codex))
struct CodexEventNormalizerItemCompletedTests {
    let sessionID: SessionID = "codex-test-session"

    @Test
    func `commandExecution completed normalizes to toolCompleted with exitCode`() throws {
        let params: JSONValue = .object([
            "type": .string("commandExecution"),
            "itemId": .string("item-1"),
            "exitCode": .int(0),
            "durationMs": .int(1500),
        ])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.count == 1)
        guard case let .toolCompleted(sid, toolEvent, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(sid == self.sessionID)
        #expect(toolEvent.name == "commandExecution")
        #expect(toolResult?.isSuccess == true)
        #expect(toolResult?.duration == 1.5)
    }

    @Test
    func `commandExecution completed with non-zero exitCode is failure`() throws {
        let params: JSONValue = .object([
            "type": .string("commandExecution"),
            "itemId": .string("item-1"),
            "exitCode": .int(1),
        ])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        guard case let .toolCompleted(_, _, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(toolResult?.isSuccess == false)
        #expect(toolResult?.errorMessage == "Exit code: 1")
    }

    @Test
    func `fileChange completed normalizes to toolCompleted`() throws {
        let params: JSONValue = .object([
            "type": .string("fileChange"),
            "itemId": .string("item-2"),
            "diff": .string("+new line"),
        ])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        guard case let .toolCompleted(_, toolEvent, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(toolEvent.name == "fileChange")
        #expect(toolResult?.isSuccess == true)
    }

    @Test
    func `mcpToolCall completed normalizes to toolCompleted`() throws {
        let params: JSONValue = .object([
            "type": .string("mcpToolCall"),
            "tool": .string("readFile"),
            "server": .string("fs"),
            "result": .string("file content"),
        ])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        guard case let .toolCompleted(_, toolEvent, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(toolEvent.name == "mcp(fs): readFile")
        #expect(toolResult?.isSuccess == true)
    }

    @Test
    func `collabToolCall completed normalizes to subagentStopped`() throws {
        let params: JSONValue = .object([
            "type": .string("collabToolCall"),
            "taskId": .string("task-1"),
        ])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        guard case let .subagentStopped(sid, taskID) = events.first else {
            Issue.record("Expected .subagentStopped, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
        #expect(taskID == "task-1")
    }

    @Test
    func `compacted completed normalizes to compacting`() throws {
        let params: JSONValue = .object(["type": .string("compacted")])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        guard case let .compacting(sid) = events.first else {
            Issue.record("Expected .compacting, got \(String(describing: events.first))")
            return
        }
        #expect(sid == self.sessionID)
    }

    @Test
    func `agentMessage completed returns empty array`() throws {
        let params: JSONValue = .object(["type": .string("agentMessage")])
        let notification = JSONRPCNotification(method: "item/completed", params: params)
        let events = try CodexEventNormalizer.normalize(notification, sessionID: self.sessionID)
        #expect(events.isEmpty)
    }
}

// MARK: - CodexEventNormalizerServerRequestTests

@Suite(.tags(.codex))
struct CodexEventNormalizerServerRequestTests {
    let sessionID: SessionID = "codex-test-session"

    @Test
    func `commandExecution requestApproval normalizes to permissionRequested`() throws {
        let params: JSONValue = .object([
            "item_id": .string("cmd-1"),
            "risk": .string("high"),
            "parsed_cmd": .object(["command": .string("rm -rf /tmp")]),
        ])
        let request = ServerInitiatedRequest(
            id: .int(1),
            method: "item/commandExecution/requestApproval",
            params: params,
        )
        let event = try CodexEventNormalizer.normalizeServerRequest(request, sessionID: self.sessionID)
        guard case let .permissionRequested(sid, permRequest) = event else {
            Issue.record("Expected .permissionRequested, got \(event)")
            return
        }
        #expect(sid == self.sessionID)
        #expect(permRequest.toolName == "commandExecution")
        #expect(permRequest.id == "cmd-1")
        #expect(permRequest.risk == .high)
    }

    @Test
    func `fileChange requestApproval normalizes to permissionRequested`() throws {
        let params: JSONValue = .object([
            "item_id": .string("file-1"),
            "path": .string("/src/main.swift"),
            "kind": .string("create"),
        ])
        let request = ServerInitiatedRequest(
            id: .string("req-2"),
            method: "item/fileChange/requestApproval",
            params: params,
        )
        let event = try CodexEventNormalizer.normalizeServerRequest(request, sessionID: self.sessionID)
        guard case let .permissionRequested(sid, permRequest) = event else {
            Issue.record("Expected .permissionRequested, got \(event)")
            return
        }
        #expect(sid == self.sessionID)
        #expect(permRequest.toolName == "fileChange")
        #expect(permRequest.id == "file-1")
    }

    @Test
    func `unknown server request method throws unknownEventType`() {
        let request = ServerInitiatedRequest(
            id: .int(99),
            method: "unknown/method",
            params: nil,
        )
        #expect(throws: EventNormalizationError.self) {
            _ = try CodexEventNormalizer.normalizeServerRequest(request, sessionID: sessionID)
        }
    }

    @Test
    func `commandExecution requestApproval without item_id falls back to request ID`() throws {
        let request = ServerInitiatedRequest(
            id: .string("fallback-id"),
            method: "item/commandExecution/requestApproval",
            params: nil,
        )
        let event = try CodexEventNormalizer.normalizeServerRequest(request, sessionID: self.sessionID)
        guard case let .permissionRequested(_, permRequest) = event else {
            Issue.record("Expected .permissionRequested")
            return
        }
        #expect(permRequest.id == "fallback-id")
    }
}
