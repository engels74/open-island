# Concurrency Contract — Open Island

> Agent-oriented cheat sheet. Terse by design — see
> `docs/oi-implementation-plan.md` §0.6 for rationale.

## 1. Target Isolation Configuration

| Target | Default Isolation | NonisolatedNonsending | InferIsolatedConformances | `@concurrent` Usage |
|---|---|---|---|---|
| `OpenIsland` (app) | `MainActor` | Yes | Yes | Sparingly — heavy computation only |
| `OICore` | `nonisolated` | Yes | Yes | On CPU-bound utilities |
| `OIProviders` | `nonisolated` | Yes | Yes | On file I/O, process spawning, SSE, JSON-RPC |
| `OIState` | `nonisolated` | Yes | Yes | Rarely — actors serialize already |
| `OIWindow` | `nonisolated` | Yes | Yes | Never — all UI work |
| `OIUI` | `nonisolated` | Yes | Yes | Never — all UI work |
| `OIModules` | `nonisolated` | Yes | Yes | Never — all UI work |

**Where configured:**

- App target: Xcode build settings →
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- SPM targets: `Package.swift` → `upcomingFeatures`
  array (all library targets), `testSettings` array
  (test targets, excludes
  `NonisolatedNonsendingByDefault`)

**Why MainActor for app target:** Safety and simplicity.
Every type/function in the app is `@MainActor`-isolated
unless opted out. Matches Xcode 17 default template
(SE-0466).

**Why nonisolated for library targets:** Reusability.
Libraries must not assume main-thread execution. The app
target decides isolation at the boundary.

## 2. `@concurrent` — When & How

**Rule:** Default (run on caller's actor) is correct for
most functions. Use `@concurrent` **only** for:

- CPU-heavy computation
- Blocking I/O that would freeze the main thread
- Work that genuinely benefits from parallelism

**If unsure, don't use it.** The default is safer and simpler.

### Canonical Examples

```swift
// Parsing large JSONL chunks — should not block the main actor
@concurrent func parseJSONLChunk(_ data: Data) async -> [ChatMessage]

// Spawns subprocesses — should not block UI
@concurrent func detectPythonRuntime() async -> PythonRuntime?

// Enumerates all PIDs — CPU-bound
@concurrent func buildProcessTree() async -> [Int32: Int32]

// Parsing Codex app-server JSONL — should not block the main actor
@concurrent func parseCodexJSONRPC(_ data: Data) async -> JSONRPCMessage

// Long-lived HTTP connection for OpenCode SSE — should not block any actor
@concurrent func connectSSEStream(_ url: URL) async throws -> AsyncStream<SSEEvent>
```

## 3. `actor` vs `Mutex<T>`

| Use | When |
|---|---|
| `actor` | Shared mutable state accessed from multiple isolation domains. Cross-actor access requires `await`. |
| `Mutex<T>` | Protecting state in `Sendable` classes or GCD-bridging code. Synchronous lock — no `await`. |

```swift
import Synchronization  // Required for Mutex<T> — compiler-level module, no OS dependency

final class ThreadSafeCache: Sendable {
    private let store = Mutex<[String: Data]>([:])
    func get(_ key: String) -> Data? { store.withLock { $0[key] } }
    func set(_ key: String, _ val: Data) { store.withLock { $0[key] = val } }
}
```

**Prefer `Mutex<T>` over `@unchecked Sendable`** with
manual locks. The compiler can verify `Mutex`-based
safety.

## 4. `nonisolated(unsafe)` — BANNED

**Never use `nonisolated(unsafe)` in this project.**

Alternatives: `Mutex<T>`, `actor`, or `@preconcurrency import`.

Enforced by SwiftLint custom rule `no_nonisolated_unsafe` (error severity).

## 5. `@preconcurrency import`

Use for legacy frameworks that predate Swift concurrency
and produce `Sendable` diagnostics in strict Swift 6
mode. See Phase 0.7 of the implementation plan for the
full list of affected frameworks.

```swift
@preconcurrency import AppKit   // suppress Sendable warnings from AppKit
```

**Rule:** Only use on framework imports where the project
cannot control the types. Do not use as a blanket
suppression tool.

## 6. Structured Concurrency

| Pattern | When |
|---|---|
| `async let` | Fixed number of parallel operations (known at compile time) |
| `withTaskGroup` | Dynamic number of parallel operations |
| `withDiscardingTaskGroup` | Long-running fire-and-forget workloads (servers, event loops) |

### `async let` Example — Phase 3.6

```swift
// Starting independent subsystems
async let hooks = installer.install()
async let socket = socketServer.start()
async let watcher = conversationParser.startWatching()
try await (hooks, socket, watcher)
```

**Default to structured concurrency** (`async let`, task
groups) — automatic cancellation propagation, priority
inheritance, guaranteed child completion.

Use `Task { }` only to bridge sync → async (e.g., SwiftUI
button handlers). Use `Task.detached` only when shedding
all inherited context is required.

## 7. `Task.init` `sending` Semantics

In Swift 6, `Task { }` closures use **`sending`**
semantics (not `@Sendable`). Captured values need only be
**disconnected** from their current isolation region —
not fully `Sendable`.

**Don't** reflexively add `Sendable` conformance just
because a type is captured in a `Task { }` closure. The
compiler checks region-based isolation (SE-0414) to prove
safety at transfer points.

## 8. `Span<T>` — Safe Contiguous Access

Prefer `Span<T>` (SE-0447) over `UnsafeBufferPointer` for
read-only contiguous access. `Span` is non-owning,
non-escapable, and bounds-checked.

**Current status:** Full adoption requires `@lifetime`
annotations (experimental in Swift 6.2). Adopt
incrementally as annotations stabilize.

```swift
let array = [1, 2, 3, 4, 5]
let s: Span<Int> = array.span  // safe, bounds-checked, lifetime-dependent
```

## 9. Forward-Scan Trailing Closures (SE-0286)

Swift 6 changed trailing closure matching from
**backward-scan to forward-scan**. This is
source-breaking from Swift 5.

**Rules:**

- First trailing closure label is dropped
- Use labeled trailing closures for all subsequent closure parameters
- Avoid trailing closure syntax in `guard` conditions

## 10. `InlineArray` (SE-0452) — Future Optimization

`InlineArray` may be a fit for **fixed-size buffers with
trivially-copyable elements** (e.g., small `ProviderID` →
color lookup tables).

**Not suitable** for collections of complex types like
`SessionEvent`. Note as a future optimization
opportunity only.
