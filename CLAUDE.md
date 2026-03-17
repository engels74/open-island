# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open Island is a provider-agnostic macOS notch overlay app for monitoring CLI/TUI coding agents (Claude Code, Codex, Gemini CLI, OpenCode). It sits in the MacBook notch area showing active sessions, permission requests, token usage, and chat history. Built with SwiftUI, targeting macOS 26.0+ with Xcode 17 and Swift 6.2+.

## Build & Development Commands

All development tasks use `just` (install via `brew install just`):

```bash
just build              # Debug build (ad-hoc signed)
just build-release      # Release build with stripping
just test               # Run all SPM package tests
just lint               # SwiftLint strict mode
just format             # Auto-format Swift files
just format-check       # Check formatting (CI-safe, no modification)
just quality            # Run all code quality checks (lint + format-check)
just clean              # Remove build artifacts
just check-tools        # Verify all required tools installed
just resolve            # Resolve SPM dependencies
```

Required tools: `just`, `swiftformat`, `swiftlint`, `prek` (all via Homebrew).

## Architecture

Six SPM library modules under `OpenIslandKit/`, prefixed with `OI`:

- **OICore** — Shared types, protocols, configuration. Event types (`ProviderEvent`, `SessionEvent`, `PermissionRequest`, `ToolEvent`), models (`SessionState`, `SessionPhase`, `TokenUsageSnapshot`), provider abstractions (`ProviderID`, `ProviderAdapter` protocol), settings, sound, terminal detection.
- **OIProviders** — Concrete provider adapters: Claude (hook socket), Codex (app-server JSONL), Gemini CLI (hook socket), OpenCode (SSE/REST). Each normalizes provider-specific events into unified `ProviderEvent`. Shared hook socket infrastructure in `Shared/`.
- **OIState** — State management. `SessionStore` (actor) is the single source of truth for all session state. `ToolTracker` and `ToolEventProcessor` handle tool lifecycle.
- **OIWindow** — Notch window system: `NotchWindowController`, `NotchGeometry`, `NotchShape`, `WindowManager`, `ScreenObserver`.
- **OIModules** — Pluggable UI feature modules (permissions, stats, closed-state). `ModuleRegistry` manages them, `ModuleLayoutEngine` handles dynamic layout.
- **OIUI** — SwiftUI views and view models: `NotchView`, `NotchViewModel`, `ChatView`, `ApprovalBarView`, `SessionMonitor`, `NotchActivityCoordinator`.

The app target `OpenIsland/` adds macOS app entry point and Sparkle auto-update integration.

### Event Flow

Provider adapters emit `ProviderEvent` → normalized to `SessionEvent` → `SessionStore.process(_:)` mutates state → broadcasts via `AsyncStream` → UI subscribes and updates.

### Access Level Convention

All library types use `package` access level (visible within SPM package only). The app target has `@MainActor` default isolation; all library targets use `nonisolated` default.

## Concurrency Model

Read `CONCURRENCY.md` for the full contract. Key rules:

- **App target**: `@MainActor` default isolation (SE-0466). Everything is main-actor-isolated unless explicitly opted out with `nonisolated`.
- **Library targets**: `nonisolated` default. All enable upcoming features: `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility`, `ExistentialAny`, `InternalImportsByDefault`.
- **`@concurrent`**: Only for CPU-heavy computation, blocking I/O, or work that genuinely benefits from parallelism. If unsure, don't use it.
- **`nonisolated(unsafe)` is BANNED** — enforced by SwiftLint custom rule (error severity). Use `Mutex<T>`, `actor`, or `@preconcurrency import` instead.
- **`Mutex<T>`** (from `Synchronization`) for protecting mutable state in `Sendable` classes. Preferred over `@unchecked Sendable` with manual locks.
- **Actors** (`SessionStore`, `ProviderRegistry`) for shared mutable state across isolation domains.
- **`@preconcurrency import`** for `Dispatch`, `AppKit`, `CoreGraphics` — must have per-file comment explaining which types cause the diagnostic.
- **Test targets** exclude `NonisolatedNonsendingByDefault` (incompatible with Swift Testing).

## Code Quality Rules

**SwiftLint** (66 opt-in rules + custom rules):

- `no_print_statements` — use `os.Logger` instead of `print`
- `no_observable_object` — use `@Observable` macro, not `ObservableObject`
- `no_combine_import` — use `AsyncStream`, not `Combine`
- `no_nonisolated_unsafe` — banned (error severity)
- Line length: 150 warning / 200 error
- Function body: 60 warning / 100 error
- Cyclomatic complexity: 15 warning / 25 error

**SwiftFormat**: 4-space indentation, max 150 chars, special acronyms preserved (ID, URL, UUID, HTTP, JSON, API, UI, MCP, PID, JSONL, CLI, OI).

## Testing

Uses **Swift Testing** framework (not XCTest): `@Test` functions, `@Suite` structs, `#expect`/`#require` assertions, `@Test(arguments:)` for parameterization. Six test targets mirror the library modules (`OICoreTests`, `OIProvidersTests`, `OIStateTests`, `OIWindowTests`, `OIModulesTests`, `OIUITests`). Custom test traits: `MockHTTPServerTrait`, `MockSocketTrait`, `TempDirectoryTrait`.

## CI

Two GitHub Actions workflows:

1. **code-quality.yml** — SwiftFormat check, SwiftLint, prek pre-commit checks
2. **ci.yml** (depends on code-quality) — SPM tests on macOS 26, release build + DMG, VirusTotal scan (main only)

Skip CI with `[skip ci]` in commit message.

## Dependency

Single external Swift package: `swiftlang/swift-markdown` (for chat view markdown rendering).
