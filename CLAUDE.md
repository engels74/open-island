# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open Island is a provider-agnostic macOS notch overlay for monitoring CLI/TUI coding agents
(Claude Code, Codex CLI, Gemini CLI, OpenCode). It sits in the MacBook notch area showing
live session status, permission requests, token usage, and more.

- **Language:** Swift 6.2, macOS 16.0+, Xcode 17
- **License:** AGPL-3.0

## Build & Development Commands

All development tasks go through `just` (install: `brew install just swiftformat swiftlint`):

```sh
just build              # Debug build (xcodebuild)
just build-release      # Release build, exports to build/export/
just test               # Run all SPM package tests (swift test)
just lint               # SwiftLint strict mode
just format             # Auto-format with SwiftFormat
just quality            # format-check + lint (CI target)
just clean              # Remove build artifacts
just check-tools        # Verify toolchain is installed
just --list             # Show all recipes
```

SPM-only commands:

```sh
just build-package      # cd OpenIslandKit && swift build
just test-package       # cd OpenIslandKit && swift test
```

Run a single test (SPM):

```sh
cd OpenIslandKit && swift test --filter OIStateTests
cd OpenIslandKit && swift test --filter OICoreTests/SessionPhaseTests
```

Pre-commit hooks use `prek` (not `pre-commit`): `prek install --hook-type pre-commit`

## Architecture

### Two-target structure

- **`OpenIsland/`** — Xcode app target (menu-bar-only `.accessory` app). Default isolation: `@MainActor` (SE-0466). Entry point: `OpenIslandApp.swift` → `AppCoordinator.swift` (composition root).
- **`OpenIslandKit/`** — SPM package containing all library modules. Default isolation: `nonisolated`. Six modules, six corresponding test targets.

### Module dependency graph

```text
OIUI → OIState → OIProviders → OICore
OIUI → OIModules → OICore
OIUI → OIWindow → OICore
```

- **OICore** — Shared types, protocols, configuration (`ProviderID`, `ProviderEvent`, `SessionState`, `SessionPhase`, `AppSettings`)
- **OIProviders** — Provider adapters implementing `ProviderAdapter` protocol. Each provider has its own
  subdirectory. Transport types: `.hookSocket` (Claude, Gemini), `.jsonRPC` (Codex), `.httpSSE` (OpenCode).
  `ExampleProviderAdapter` exists for UI testing and as a template.
- **OIState** — `SessionStore` actor: single source of truth for session state. Processes `ProviderEvent`s
  through a state machine with phase transitions (`SessionPhase`). Multi-subscriber broadcast via `AsyncStream`.
- **OIModules** — Notch UI modules (`MascotModule`, `ActivitySpinnerModule`, `SessionDotsModule`,
  `PermissionIndicatorModule`, etc.) registered in `ModuleRegistry`. Each module has a side and display order.
- **OIUI** — SwiftUI views, `NotchViewModel`, `NotchView`. Depends on swift-markdown for rendering.
- **OIWindow** — `NotchPanel` (borderless `NSPanel` floating above menu bar), `WindowManager`, screen geometry.

### Event flow

```text
ProviderAdapter.events() → ProviderRegistry.mergedEvents()
  → AppCoordinator bridge task → SessionStore.process(.providerEvent(...))
  → phase transitions → publishState()
  → SessionMonitor → NotchActivityCoordinator → NotchViewModel → SwiftUI views
```

### Adding a new provider

1. Create subdirectory under `OpenIslandKit/Sources/OIProviders/`
2. Implement `ProviderAdapter` protocol (see `ExampleProviderAdapter` as template)
3. Add `ProviderID` case in OICore
4. Register adapter in `AppCoordinator.start()`

## Concurrency Rules

See `CONCURRENCY.md` for the full contract. Key points:

- App target: `@MainActor` default isolation. Library targets: `nonisolated` default.
- Use `@concurrent` only for CPU-heavy or blocking I/O work. Default (caller's actor) is correct for most functions.
- Use `Mutex<T>` (from `Synchronization`) for synchronous thread-safe state in `Sendable` classes. Use `actor` for async cross-isolation access.
- **`nonisolated(unsafe)` is banned.** Enforced by SwiftLint custom rule.
- **`ObservableObject`/`@Published`/Combine are banned.** Use `@Observable`/`@State`/`AsyncStream`.
- Use `@preconcurrency import` per-file for legacy frameworks (AppKit, Dispatch, CoreGraphics) with a comment explaining which types cause the diagnostic.
- Use `os.Logger` instead of `print()` (enforced by SwiftLint).

## Code Style

- SwiftFormat (`.swiftformat`) and SwiftLint (`.swiftlint.yml`) enforce style automatically
- 4-space indentation, 150 char line length (warning), 200 (error)
- `--self insert` — always use explicit `self`
- `--redundanttype inferred` — prefer type inference
- Access control: `package` for SPM-internal APIs, `public` for cross-module APIs
- SwiftFormat runs `organizeDeclarations` and `markTypes` (MARK comments are auto-generated)
- Tests use Swift Testing (`import Testing`, `@Test`, `@Suite`), not XCTest
