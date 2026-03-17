# Adding a Provider

This guide walks through adding a new AI coding assistant provider to Open Island. By the end, your provider will appear in the notch, emit real-time session events, and support permission interception.

## Architecture Overview

The provider system consists of these core types:

| Type | File | Purpose |
|------|------|---------|
| `ProviderAdapter` | `OpenIslandKit/Sources/OIProviders/ProviderAdapter.swift` | Protocol every provider conforms to |
| `ProviderRegistry` | `OpenIslandKit/Sources/OIProviders/ProviderRegistry.swift` | Central registry — starts, stops, and merges event streams |
| `ProviderID` | `OpenIslandKit/Sources/OICore/Provider/ProviderID.swift` | Enum identifying each supported provider |
| `ProviderMetadata` | `OpenIslandKit/Sources/OICore/Provider/ProviderMetadata.swift` | Static display and CLI configuration per provider |
| `ProviderTransportType` | `OpenIslandKit/Sources/OICore/Provider/ProviderTransportType.swift` | Communication pattern: `.hookSocket`, `.jsonRPC`, or `.httpSSE` |
| `ProviderEvent` | `OpenIslandKit/Sources/OICore/Events/ProviderEvent.swift` | Normalized event enum consumed by the UI layer |

The data flow is:

```
CLI Process → Transport Layer → Event Normalizer → ProviderEvent → ProviderRegistry → SessionStore → UI
```

Each provider adapter owns its transport client and event normalizer, emitting a stream of `ProviderEvent` values. The `ProviderRegistry` merges all provider streams and the `SessionStore` drives UI updates.

### Transport Types

Open Island supports three integration patterns, each suited to different CLI architectures:

| Transport | Enum Case | How It Works | Used By |
|-----------|-----------|--------------|---------|
| **Hook Socket** | `.hookSocket` | CLI runs hook scripts on lifecycle events; scripts send JSON over a Unix domain socket to Open Island | Claude Code, Gemini CLI |
| **JSON-RPC** | `.jsonRPC` | Open Island launches the CLI as a subprocess and communicates via bidirectional JSON-RPC 2.0 over stdio | Codex |
| **HTTP SSE** | `.httpSSE` | CLI runs an HTTP server; Open Island connects via Server-Sent Events for streaming and REST for commands | OpenCode |

Choose the transport that matches how your provider's CLI exposes events. If the CLI has a hook/plugin system, use `.hookSocket`. If it has an app-server or subprocess mode, use `.jsonRPC`. If it runs an HTTP API, use `.httpSSE`.

## Step 1: Add a Provider ID

Add a new case to the `ProviderID` enum in `OpenIslandKit/Sources/OICore/Provider/ProviderID.swift`:

```swift
package enum ProviderID: String, Sendable, Hashable, Codable {
    case claude
    case codex
    case geminiCLI
    case openCode
    case myProvider    // ← add your case
}
```

Then add it to the `allKnown` list in `OpenIslandKit/Sources/OICore/Settings/AppSettings.swift`:

```swift
package extension ProviderID {
    static let allKnown: [ProviderID] = [.claude, .codex, .geminiCLI, .openCode, .myProvider]
}
```

This ensures the provider appears in settings and is enabled by default.

## Step 2: Add Provider Metadata

Add a case to `ProviderMetadata.metadata(for:)` in `OpenIslandKit/Sources/OICore/Provider/ProviderMetadata.swift`:

```swift
case .myProvider:
    Self(
        displayName: "My Provider",
        iconName: "terminal",                    // SF Symbol name
        accentColorHex: "#FF6B35",               // hex color for UI theming
        cliBinaryNames: ["myprovider"],           // CLI binary name(s) on PATH
        transportType: .hookSocket,               // your chosen transport
        configFileFormat: .json,                  // .json or .toml
        sessionLogDirectoryPath: "~/.myprovider/sessions",
    )
```

The metadata fields:

| Field | Type | Description |
|-------|------|-------------|
| `displayName` | `String` | Human-readable name shown in the UI |
| `iconName` | `String` | SF Symbol name for the provider icon |
| `accentColorHex` | `String` | Hex color string for UI accent theming |
| `cliBinaryNames` | `[String]` | CLI binary names to search for on `PATH` |
| `transportType` | `ProviderTransportType` | `.hookSocket`, `.jsonRPC`, or `.httpSSE` |
| `configFileFormat` | `ConfigFileFormat` | `.json` or `.toml` — format of the CLI's config file |
| `sessionLogDirectoryPath` | `String` | Path to session logs (tilde `~` for home directory) |

## Step 3: Implement the ProviderAdapter Protocol

Create a directory for your provider: `OpenIslandKit/Sources/OIProviders/MyProvider/`.

The `ProviderAdapter` protocol requires:

```swift
package protocol ProviderAdapter: Sendable {
    var providerID: ProviderID { get }
    var metadata: ProviderMetadata { get }
    var transportType: ProviderTransportType { get }

    func start() async throws(ProviderStartupError)
    func stop() async

    func events() -> AsyncStream<ProviderEvent>

    func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws

    func isSessionAlive(_ sessionID: String) -> Bool
}
```

### Adapter Skeleton

Create `MyProviderAdapter.swift`:

```swift
import Foundation
package import OICore
import Synchronization

// MARK: - AdapterState

private struct AdapterState: Sendable {
    var isRunning = false
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
}

// MARK: - MyProviderAdapter

package final class MyProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    package init() {
        self.state = Mutex(.init())
    }

    // MARK: Package

    package let providerID: ProviderID = .myProvider
    package let metadata: ProviderMetadata = .metadata(for: .myProvider)
    package let transportType: ProviderTransportType = .hookSocket  // your transport

    package func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // 1. Verify the CLI binary exists
        // 2. Set up your transport (socket server, subprocess, HTTP client)
        // 3. Create the event stream

        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        // 4. Start a detached task to process raw events from your transport
        //    and yield normalized ProviderEvents through the continuation.
        //    Use Task.detached to avoid inheriting the caller's isolation
        //    domain — this prevents deadlock when stop() is called from
        //    the same context.

        self.state.withLock { state in
            state.isRunning = true
            state.eventStream = stream
            state.eventContinuation = continuation
        }
    }

    package func stop() async {
        let continuation = self.state.withLock { state
            -> AsyncStream<ProviderEvent>.Continuation? in
            guard state.isRunning else { return nil }
            let cont = state.eventContinuation
            state.eventContinuation = nil
            state.eventStream = nil
            state.isRunning = false
            return cont
        }

        // Cancel any processing tasks, then finish the stream
        continuation?.finish()
    }

    package func events() -> AsyncStream<ProviderEvent> {
        if let stream = self.state.withLock({ $0.eventStream }) {
            return stream
        }
        // Return an immediately-finished empty stream if not started.
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        continuation.finish()
        return stream
    }

    package func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws {
        // Send the permission decision back to your CLI.
        // The mechanism depends on your transport:
        // - hookSocket: respond on the held-open socket connection
        // - jsonRPC: send a JSON-RPC response
        // - httpSSE: POST to a REST endpoint
    }

    package func isSessionAlive(_ sessionID: String) -> Bool {
        // Return whether the session is still active.
        // For process-based providers, check kill(pid, 0).
        self.state.withLock { $0.isRunning }
    }

    // MARK: Private

    private let state: Mutex<AdapterState>
}
```

### Key Implementation Patterns

**Mutable state**: All adapters protect mutable state with `Mutex<AdapterState>` from the `Synchronization` framework. The adapter class is `final class` conforming to `Sendable` — the `Mutex` makes this safe without `@unchecked`.

**Event stream lifecycle**: Use `AsyncStream.makeStream(bufferingPolicy: .bufferingOldest(128))` to create the stream. Start a `Task.detached` for event processing. In `stop()`, extract the continuation from the mutex *before* calling `finish()` — `finish()` triggers `onTermination` synchronously, which could cause re-entrant mutex access.

**`events()` when not started**: Return an immediately-finished empty stream so consumers don't block.

**Typed throws**: `start()` uses `throws(ProviderStartupError)` — a closed error domain. Choose the appropriate case:

```swift
package enum ProviderStartupError: Error, Sendable {
    case binaryNotFound(String)
    case configNotFound(path: String)
    case configParseError(path: String, underlying: any Error)
    case socketCreationFailed(path: String)
    case alreadyRunning
    case jsonRPCHandshakeFailed(underlying: any Error)
    case httpServerUnreachable(host: String, port: Int)
}
```

## Step 4: Create an Event Normalizer

The event normalizer maps your provider's raw events to the normalized `ProviderEvent` enum. Create `MyProviderEventNormalizer.swift` as a namespace enum with static methods:

```swift
package import OICore

package enum MyProviderEventNormalizer {
    package static func normalize(_ rawEvent: MyRawEvent) throws(EventNormalizationError) -> [ProviderEvent] {
        switch rawEvent.type {
        case "session_start":
            let sessionID = rawEvent.sessionID
            let cwd = rawEvent.workingDirectory ?? ""
            return [.sessionStarted(sessionID, cwd: cwd, pid: nil)]

        case "session_end":
            return [.sessionEnded(rawEvent.sessionID)]

        case "prompt_submitted":
            return [.userPromptSubmitted(rawEvent.sessionID)]

        case "processing":
            return [.processingStarted(rawEvent.sessionID)]

        case "tool_start":
            let toolEvent = ToolEvent(
                id: rawEvent.toolID ?? UUID().uuidString,
                name: rawEvent.toolName ?? "unknown",
                input: rawEvent.toolInput,
                startedAt: Date(),
            )
            return [.toolStarted(rawEvent.sessionID, toolEvent)]

        case "tool_complete":
            let toolEvent = ToolEvent(
                id: rawEvent.toolID ?? UUID().uuidString,
                name: rawEvent.toolName ?? "unknown",
                input: rawEvent.toolInput,
                startedAt: Date(),
            )
            let result = ToolResult(
                output: rawEvent.output,
                isSuccess: rawEvent.success,
                errorMessage: rawEvent.errorMessage,
            )
            return [.toolCompleted(rawEvent.sessionID, toolEvent, result)]

        case "permission_request":
            let request = PermissionRequest(
                id: rawEvent.requestID ?? UUID().uuidString,
                toolName: rawEvent.toolName ?? "unknown",
                toolInput: rawEvent.toolInput,
                timestamp: Date(),
            )
            return [.permissionRequested(rawEvent.sessionID, request)]

        case "idle":
            return [.waitingForInput(rawEvent.sessionID)]

        default:
            return []  // silently ignore unknown events
        }
    }
}
```

### The ProviderEvent Enum

Your normalizer maps raw events to these normalized cases:

| Case | When to Emit |
|------|--------------|
| `.sessionStarted(SessionID, cwd:, pid:)` | CLI session begins |
| `.sessionEnded(SessionID)` | CLI session ends |
| `.userPromptSubmitted(SessionID)` | User sends a prompt |
| `.processingStarted(SessionID)` | Model starts generating |
| `.toolStarted(SessionID, ToolEvent)` | Tool invocation begins |
| `.toolCompleted(SessionID, ToolEvent, ToolResult?)` | Tool invocation finishes |
| `.permissionRequested(SessionID, PermissionRequest)` | CLI asks user to approve a tool action |
| `.waitingForInput(SessionID)` | Model finished, waiting for next prompt |
| `.compacting(SessionID)` | Context window compaction in progress |
| `.notification(SessionID, message:)` | Informational notification |
| `.chatUpdated(SessionID, [ChatHistoryItem])` | Chat history changed |
| `.subagentStarted(SessionID, taskID:, parentToolID:)` | Sub-agent spawned |
| `.subagentStopped(SessionID, taskID:)` | Sub-agent finished |
| `.configChanged(SessionID?)` | Provider configuration changed |
| `.diffUpdated(SessionID, unifiedDiff:)` | Accumulated diff changed |
| `.modelResponse(SessionID, textDelta:)` | Streaming text from model |
| `.tokenUsage(SessionID, promptTokens:, completionTokens:, totalTokens:)` | Token consumption update |
| `.interruptDetected(SessionID)` | User interrupted the model |

You don't need to emit all events — emit what your provider supports. The minimum for a functional integration is: `.sessionStarted`, `.sessionEnded`, `.processingStarted`, and `.waitingForInput`.

### Error Handling

Use `EventNormalizationError` for malformed data from the transport layer:

```swift
package enum EventNormalizationError: Error, Sendable {
    case unknownEventType(String)
    case malformedPayload(field: String)
    case missingRequiredField(String)
}
```

For unknown event types, prefer returning an empty array over throwing — this allows forward compatibility when the CLI adds new events.

## Step 5: Register the Adapter

Register your adapter with `ProviderRegistry`. This is typically done in the app startup path:

```swift
let registry = ProviderRegistry()
registry.register(ClaudeProviderAdapter())
registry.register(CodexProviderAdapter())
registry.register(GeminiCLIProviderAdapter())
registry.register(OpenCodeProviderAdapter())
registry.register(MyProviderAdapter())        // ← add yours
```

`ProviderRegistry` is an `actor` that provides:

- **`register(_:)`** — registers an adapter, keyed by its `providerID`
- **`adapter(for:)`** — looks up an adapter by `ProviderID`
- **`startAll()`** — starts all registered adapters concurrently via a task group
- **`stopAll()`** — stops all registered adapters concurrently
- **`mergedEvents()`** — returns a single `AsyncStream<ProviderEvent>` that merges all provider streams using `withThrowingDiscardingTaskGroup`

Deduplication is by `providerID` — registering a second adapter with the same ID overwrites the first.

## Step 6: Handle Permissions (If Applicable)

If your provider's CLI requests tool-use permissions, implement the permission flow:

1. **Detect the permission request** in your event normalizer and emit `.permissionRequested(sessionID, PermissionRequest)`.

2. **Implement `respondToPermission(_:decision:)`** in your adapter to send the user's decision back to the CLI.

The `PermissionRequest` type:

```swift
package struct PermissionRequest: Sendable {
    package let id: String
    package let toolName: String
    package let toolInput: JSONValue?
    package let timestamp: Date
    package let risk: PermissionRisk?   // .low, .medium, or .high
}
```

The `PermissionDecision` type:

```swift
package enum PermissionDecision: Sendable {
    case allow
    case deny(reason: String?)
}
```

How permission response works depends on your transport:

- **Hook socket** (Claude, Gemini): The hook script holds the socket connection open during a `BeforeTool`/`PermissionRequest` event. The adapter writes the decision back to that held-open connection, and the hook script exits with a status code that the CLI interprets.

- **JSON-RPC** (Codex): The CLI sends a JSON-RPC server-request to the adapter. The adapter responds with a JSON-RPC response containing the decision.

- **HTTP SSE** (OpenCode): The adapter POSTs the decision to a REST endpoint on the CLI's HTTP server.

## Transport-Specific Implementation Guides

### Hook Socket Transport (`.hookSocket`)

**Reference implementations:** `ClaudeProviderAdapter`, `GeminiCLIProviderAdapter`

**File structure:**

```
OpenIslandKit/Sources/OIProviders/MyProvider/
├── MyProviderAdapter.swift          # Top-level adapter
├── MyProviderEventNormalizer.swift   # Raw event → ProviderEvent mapping
├── MyProviderHookSocketServer.swift  # Unix socket server
└── MyProviderHookInstaller.swift     # Hook script installer (optional)
```

**How it works:**

1. Open Island starts a Unix domain socket server (e.g., `/tmp/open-island-myprovider.sock`).
2. The CLI is configured to run a hook script on lifecycle events.
3. The hook script connects to the socket and sends JSON event payloads.
4. For permission events, the hook script holds the connection open and waits for a response.

**Shared infrastructure:** The `OpenIslandKit/Sources/OIProviders/Shared/` directory contains `HookSocketBridge` and `HookSocketTypes` — reusable types for hook socket communication that both Claude and Gemini adapters use.

**Key adapter pattern:**

```swift
package func start() async throws(ProviderStartupError) {
    // 1. Install hooks (best-effort — don't fail if already installed)
    try? await MyProviderHookInstaller.install()

    // 2. Start socket server → returns AsyncStream<Data>
    let rawStream = try socketServer.start()

    // 3. Create ProviderEvent stream
    let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
        bufferingPolicy: .bufferingOldest(128),
    )

    // 4. Start detached event processing task
    let adapter = self
    let processingTask = Task.detached { [weak adapter] in
        for await rawData in rawStream {
            guard !Task.isCancelled else { break }
            adapter?.processRawEvent(rawData, continuation: continuation)
        }
        continuation.finish()
    }
}
```

### JSON-RPC Transport (`.jsonRPC`)

**Reference implementation:** `CodexProviderAdapter`

**File structure:**

```
OpenIslandKit/Sources/OIProviders/MyProvider/
├── MyProviderAdapter.swift          # Top-level adapter
├── MyProviderEventNormalizer.swift   # JSON-RPC notification → ProviderEvent
├── MyProviderAppServerClient.swift   # JSON-RPC client (stdio subprocess)
└── MyProviderJSONRPCProtocol.swift   # JSON-RPC type definitions
```

**How it works:**

1. Open Island launches the CLI binary as a subprocess with JSON-RPC over stdio.
2. The adapter sends an `initialize` JSON-RPC request as a handshake.
3. The CLI sends JSON-RPC notifications for events.
4. For permissions, the CLI sends a JSON-RPC server-request; the adapter responds.

**Key adapter pattern:**

```swift
package func start() async throws(ProviderStartupError) {
    // 1. Verify binary exists on PATH
    guard Self.binaryExists(binaryPath) else {
        throw .binaryNotFound(binaryPath)
    }

    // 2. Start app-server and perform JSON-RPC handshake
    do {
        try await client.start()
    } catch {
        throw .jsonRPCHandshakeFailed(underlying: error)
    }

    // 3. Create event stream
    let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
        bufferingPolicy: .bufferingOldest(128),
    )

    // 4. Merge notification and server-request streams
    //    and normalize into ProviderEvents
}
```

### HTTP SSE Transport (`.httpSSE`)

**Reference implementation:** `OpenCodeProviderAdapter`

**File structure:**

```
OpenIslandKit/Sources/OIProviders/MyProvider/
├── MyProviderAdapter.swift          # Top-level adapter
├── MyProviderEventNormalizer.swift   # SSE event → ProviderEvent
├── MyProviderSSEClient.swift         # SSE connection client
├── MyProviderRESTClient.swift        # REST API client
└── MyProviderServerDiscovery.swift   # Server location/port discovery
```

**How it works:**

1. The CLI runs an HTTP server independently.
2. Open Island discovers the server (via config file, well-known port, etc.).
3. Open Island connects to the SSE endpoint for streaming events.
4. Open Island uses REST endpoints for commands (e.g., permission responses).

**Key adapter pattern:**

```swift
package func start() async throws(ProviderStartupError) {
    // 1. Discover the server
    let server = await discovery.discover()

    // 2. Check reachability
    guard await discovery.checkReachability(server: server) else {
        throw .httpServerUnreachable(host: server.host, port: server.port)
    }

    // 3. Create REST and SSE clients
    let restClient = MyProviderRESTClient(baseURL: server.baseURL)
    let sseClient = MyProviderSSEClient(baseURL: server.baseURL)

    // 4. Connect SSE and create event stream
    let sseStream = await sseClient.connect(endpoint: .global)
    let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
        bufferingPolicy: .bufferingOldest(128),
    )

    // 5. Start SSE processing task
    let sseTask = Task.detached {
        for await sseEvent in sseStream {
            guard !Task.isCancelled else { break }
            let events = MyProviderEventNormalizer.normalize(sseEvent)
            for event in events {
                continuation.yield(event)
            }
        }
        continuation.finish()
    }
}
```

## Step 7: Write Tests

Add tests in `OpenIslandKit/Tests/OIProvidersTests/`. Use Swift Testing (`import Testing`), not XCTest.

### Event Normalizer Tests

These are the most important tests — they verify that raw CLI events map correctly to `ProviderEvent`:

```swift
import Testing
@testable import OICore
@testable import OIProviders

struct MyProviderEventNormalizerTests {
    @Test
    func `session start produces sessionStarted event`() throws {
        let raw = MyRawEvent(type: "session_start", sessionID: "s1", workingDirectory: "/tmp")
        let events = try MyProviderEventNormalizer.normalize(raw)
        #expect(events.count == 1)
        guard case let .sessionStarted(sid, cwd: cwd, pid: _) = events[0] else {
            Issue.record("Expected .sessionStarted")
            return
        }
        #expect(sid == "s1")
        #expect(cwd == "/tmp")
    }

    @Test
    func `unknown event type returns empty array`() throws {
        let raw = MyRawEvent(type: "unknown_future_event", sessionID: "s1")
        let events = try MyProviderEventNormalizer.normalize(raw)
        #expect(events.isEmpty)
    }

    @Test
    func `tool complete includes result`() throws {
        let raw = MyRawEvent(
            type: "tool_complete",
            sessionID: "s1",
            toolName: "file_write",
            success: true,
        )
        let events = try MyProviderEventNormalizer.normalize(raw)
        guard case let .toolCompleted(_, _, result) = events[0] else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(result?.isSuccess == true)
    }
}
```

### Provider Conformance Tests

Add your provider to the existing parameterized conformance tests in `OpenIslandKit/Tests/OIProvidersTests/Shared/ProviderConformanceTests.swift`. These tests verify that metadata is consistent for every registered provider:

```swift
private let allProviderIDs: [ProviderID] = [.claude, .codex, .geminiCLI, .openCode, .myProvider]
```

### Mock Adapter for Testing

For testing code that consumes `ProviderAdapter`, use the existing `MockProviderAdapter` in `OpenIslandKit/Tests/OIStateTests/Helpers/MockProviderAdapter.swift`. It accepts a `ProviderID` and provides a controllable event stream.

## Existing Adapter Reference

These adapters demonstrate each transport pattern:

| Adapter | Transport | Key Files | Notes |
|---------|-----------|-----------|-------|
| **Claude Code** | `.hookSocket` | `Claude/ClaudeProviderAdapter.swift`, `ClaudeEventNormalizer.swift`, `ClaudeHookSocketServer.swift`, `ClaudeHookInstaller.swift` | Most complete hook-based implementation. Hook installer manages Python script deployment and `settings.json` registration. |
| **Gemini CLI** | `.hookSocket` | `GeminiCLI/GeminiCLIProviderAdapter.swift`, `GeminiEventNormalizer.swift`, `GeminiHookSocketServer.swift`, `GeminiHookInstaller.swift` | Same hook architecture as Claude. Includes `AfterModel` event throttling for token usage. |
| **Codex** | `.jsonRPC` | `Codex/CodexProviderAdapter.swift`, `CodexEventNormalizer.swift`, `CodexAppServerClient.swift`, `CodexJSONRPCProtocol.swift` | Subprocess-based. Merges notification and server-request streams. |
| **OpenCode** | `.httpSSE` | `OpenCode/OpenCodeProviderAdapter.swift`, `OpenCodeEventNormalizer.swift`, `OpenCodeSSEClient.swift`, `OpenCodeRESTClient.swift`, `OpenCodeServerDiscovery.swift` | HTTP-based. Tracks real session IDs and permission-to-session mappings for REST responses. |

## Checklist

Before submitting your provider:

- [ ] New case added to `ProviderID` enum
- [ ] Case added to `ProviderID.allKnown` in `AppSettings.swift`
- [ ] Metadata case added to `ProviderMetadata.metadata(for:)`
- [ ] Adapter class conforms to `ProviderAdapter` with all required methods
- [ ] Event normalizer maps raw events to `ProviderEvent` cases
- [ ] `start()` uses `throws(ProviderStartupError)` with appropriate error cases
- [ ] `stop()` extracts continuation from mutex before calling `finish()`
- [ ] `events()` returns an immediately-finished stream when not started
- [ ] `respondToPermission(_:decision:)` sends decisions back to the CLI
- [ ] Adapter registered in `ProviderRegistry` during app startup
- [ ] Event normalizer tests cover all mapped event types
- [ ] Provider added to `allProviderIDs` in `ProviderConformanceTests.swift`
