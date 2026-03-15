# open-island — Implementation Plan

> A provider-agnostic macOS notch overlay for monitoring CLI/TUI coding agents.
> Supports Claude Code, Codex, Gemini CLI, OpenCode — and any future provider.

---

## Phase 0 — Project Scaffolding & Tooling

### 0.1 Xcode Project Setup

- [x] Create a new macOS app target in Xcode 17 (Swift 6.2, minimum deployment macOS 16.0)
  - [x] **Deployment target rationale**: macOS 16.0 (Tahoe, shipped Fall 2025) is Xcode 17's default new-project template target. All Swift 6.2 compile-time features back-deploy freely (swift-dev-pro.md Section 12). The primary runtime-dependent feature used by this project is `@Observable` (macOS 14+). `#Predicate` (requires macOS 14+) and `#Expression` (requires macOS 15+) are both available at our macOS 16.0 deployment target if needed for session filtering or dynamic module logic. Targeting macOS 16.0 gives access to any Tahoe-specific AppKit improvements (NSPanel behaviors, window management) and matches the expected audience — developers running CLI coding agents are overwhelmingly on the latest macOS.
- [x] Set activation policy to `.accessory` (no dock icon)
- [x] Configure build settings:
  - [x] `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466)
  - [x] `SWIFT_APPROACHABLE_CONCURRENCY = YES`
  - [x] Swift Language Mode: Swift 6
  - [x] Note: Swift 6 language mode subsumes strict concurrency checking — `SWIFT_STRICT_CONCURRENCY` is not needed. Do not add `SWIFT_STRICT_CONCURRENCY = complete`; it is a Swift 5 migration setting and is a no-op under Swift 6 language mode.
  - [x] Note: `SWIFT_APPROACHABLE_CONCURRENCY = YES` is an **Xcode-only build setting** that applies exclusively to the Xcode-managed app target (`open-island.app`). It is the Xcode equivalent of enabling `NonisolatedNonsendingByDefault` + `InferIsolatedConformances` together. SPM library targets (`OIKit`, `OIProviders`, etc.) do not inherit Xcode build settings and instead receive these features via the `.enableUpcomingFeature()` calls in Phase 0.2's Package.swift. These cover different targets and are not redundant.
- [x] Add a `Settings { EmptyView() }` scene as the only SwiftUI scene (all UI via custom NSPanel)
- [x] Set bundle identifier, app icon placeholder, and Info.plist entries (LSUIElement = YES for accessory)

### 0.2 SPM / Package.swift for Internal Modules

- [x] Create a local Swift package (`OpenIslandKit`) with these initial library targets:
  - [x] `OICore` — shared models, protocols, utilities
  - [x] `OIProviders` — provider adapter protocol + concrete implementations
  - [x] `OIWindow` — notch window system, geometry, shape
  - [x] `OIModules` — closed-state module system
  - [x] `OIUI` — SwiftUI views
  - [x] `OIState` — SessionStore, state machine, event processing
- [x] Configure `swift-tools-version: 6.2` (Swift 6 language mode is enabled by default for all targets with `swift-tools-version: 6.0+` — do not add `.swiftLanguageMode(.v6)` on targets, as it is redundant. Note: swift-dev-pro.md Section 1 example includes `.swiftLanguageMode(.v6)` explicitly for clarity, but it is a no-op with `swift-tools-version: 6.2`.)
- [x] Enable upcoming feature flags per target:

  ```swift
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  ```

- [x] Use `package` access level for intra-package APIs instead of `public` where possible
- [x] `.defaultIsolation(MainActor.self)` is intentionally absent from Package.swift — the SPM package contains only library targets, which keep `nonisolated` default per project guidelines. The app target receives MainActor default isolation via Xcode build setting (Phase 0.1).
- [x] Since `OpenIslandKit` is an internal package (no library evolution mode), `@inlinable`, `@usableFromInline`, and `@frozen` are unnecessary. Don't add unless benchmarks show measurable improvement.
- [x] With `InternalImportsByDefault` enabled, all `import` statements default to `internal` visibility. Use `public import Foundation` (or `public import AppKit`, etc.) **only** in modules that deliberately re-export those symbols to downstream targets. This prevents transitive dependency leakage across module boundaries.
- [x] **Per-target warning control** (SE-0480, Swift 6.2): use `.swiftSettings([.warningLevel(.error, for: .deprecation)])` on production targets to promote deprecation warnings to errors. Keep default warning levels on test targets where mock/fixture code may use deprecated APIs intentionally. Evaluate need during Phase 12.5 performance audit; add only if specific warning categories prove problematic.

> **Note on `ExistentialAny`**: Deferred to Swift 7 as a mandatory language change (not required in Swift 6), but enabled here as an upcoming feature flag to enforce `any Protocol` discipline at compile time in a greenfield project. This aligns with the project checklist requirement that `any Protocol` is required for all existential types (SE-0335).

> **Note on `InternalImportsByDefault`**: Also targeting Swift 7 (SE-0409), but enabled here to enforce minimal transitive dependency exposure from day one. Combined with `package` access level, this ensures each module's public surface is deliberate.

### 0.3 Pre-commit & Code Quality Pipeline (`prek`)

Set up the full `prek` (pre-commit) pipeline before writing any application code. This gates every commit.

#### 0.3.1 `.pre-commit-config.yaml`

Adapt the claude-island config with these changes:

- [x] **`exclude` regex**: update project-specific paths — replace `ClaudeIsland` references with `OpenIsland` and `OpenIslandKit` module paths. Add `OpenIslandKit/\.build/.*` for the SPM package build directory.
- [x] **SwiftFormat hook**: keep `types: [swift]`, ensure `entry: swiftformat` uses the system-installed binary (same as claude-island)
- [x] **SwiftLint hook**: keep `entry: swiftlint lint --strict`, `types: [swift]`
- [x] **Ruff hooks** (`ruff-check`, `ruff-format`): update `files:` pattern from `^ClaudeIsland/Resources/.*\.py$` to `^OpenIsland/Resources/Hooks/.*\.py$` — this covers the provider hook scripts (Claude's Python hook, Gemini CLI's hook scripts, and any future Python-based hooks)
- [x] **Shellcheck**: update `files:` to `^scripts/.*\.sh$` (same pattern, verify `scripts/` directory exists)
- [x] **Markdownlint**: keep as-is, update `exclude` if needed for new directory names
- [x] **Standard hooks**: keep all (`trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-json`, `check-merge-conflict`, `detect-private-key`, `no-commit-to-branch`, `check-added-large-files`)
- [x] **Bump versions**: check for latest revs of all repos (pre-commit-hooks, SwiftFormat, SwiftLint, shellcheck-py, ruff-pre-commit, markdownlint-cli) at project creation time
- [x] Keep `ci: skip: [swiftformat, swiftlint]` since CI runners may not have these installed system-wide

Full config:

```yaml
# Pre-commit configuration for open-island
# Hook revisions — update with: just update-hooks (runs prek autoupdate)
# SwiftFormat and SwiftLint use language: system — the rev pins the hook
# definition only; the actual binary version is whatever is installed.
#
# Install: prek install --hook-type pre-commit --hook-type pre-push
# Run all: prek run --all-files

default_language_version:
  python: python3

exclude: |
  (?x)^(
    .*\.xcodeproj/.*|
    .*\.xcworkspace/.*|
    build/.*|
    DerivedData/.*|
    \.build/.*|
    releases/.*|
    Pods/.*|
    \.sparkle-keys/.*|
    .*\.xcuserstate|
    xcuserdata/.*|
    OpenIslandKit/\.build/.*
  )$

repos:
  # Standard pre-commit hooks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
        args: [--markdown-linebreak-ext=md]
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: detect-private-key
      - id: no-commit-to-branch
        args: [--branch, main]
      - id: check-added-large-files
        args: [--maxkb=1024]

  # SwiftFormat - Auto-format Swift files
  - repo: https://github.com/nicklockwood/SwiftFormat
    rev: 0.55.3
    hooks:
      - id: swiftformat
        name: swiftformat
        entry: swiftformat
        language: system
        types: [swift]

  # SwiftLint - Lint Swift files
  - repo: https://github.com/realm/SwiftLint
    rev: 0.57.1
    hooks:
      - id: swiftlint
        name: swiftlint
        entry: swiftlint lint --strict
        language: system
        types: [swift]

  # Shellcheck - Validate shell scripts
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
        files: ^scripts/.*\.sh$

  # Ruff - Python linting and formatting for provider hook scripts
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.11
    hooks:
      - id: ruff-check
        args: [--fix]
        files: ^OpenIsland/Resources/Hooks/.*\.py$
      - id: ruff-format
        files: ^OpenIsland/Resources/Hooks/.*\.py$

  # Markdownlint - Markdown consistency
  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.43.0
    hooks:
      - id: markdownlint
        args: [--fix]
        files: \.(md|markdown)$
        exclude: ^(\.augment/|LICENSE\.md)

# Pre-push hooks
default_stages: [pre-commit]

ci:
  skip: [swiftformat, swiftlint]
```

#### 0.3.2 `.swiftformat`

Adapt the claude-island config:

- [x] `--swiftversion 6.2` (already correct)
- [x] **`--exclude`**: update to `build,DerivedData,.build,Pods,releases,*.xcodeproj,*.xcworkspace,xcuserdata,.sparkle-keys,OpenIslandKit/.build` — remove the claude-island-specific `HookSocketServer.swift` exclusion (start fresh; if the new socket server triggers the same `organizeDeclarations` timeout, exclude it then)
- [x] **`--acronyms`**: keep all existing (`ID,URL,UUID,HTTP,HTTPS,JSON,API,UI,MCP,PID,JSONL,SSH,TCP,IP,DNS,HTML,XML,CSS,JS,SDK,CLI,TLS,SSL`) — add `OI` (project prefix) for type names, add `SSE` (Server-Sent Events, used by OpenCode provider), add `RPC` (JSON-RPC, used by Codex provider), add `OTLP` (OpenTelemetry Protocol, used across providers)
- [x] **All enabled rules**: keep `acronyms`, `blankLinesBetweenImports`, `blockComments`, `docComments`, `isEmpty`, `markTypes`, `organizeDeclarations`, `sortDeclarations`, `wrapEnumCases`, `wrapSwitchCases`
- [x] **All disabled rules**: keep `andOperator`, `redundantSendable`, `wrapMultilineStatementBraces`
- [x] **`redundantSendable` rationale**: Swift 6.2's region-based isolation (SE-0414) means many explicit `Sendable` conformances that look redundant are actually intentional public API contracts — do not auto-remove them
- [x] **Gotcha from claude-island**: `organizeDeclarations` can strip explicit `nonisolated` on synthesizable conformances (e.g., `Equatable`). Document this in a `CONTRIBUTING.md` note and use `// swiftformat:disable all` / `// swiftformat:enable all` guards around affected declarations

Full config:

```
# SwiftFormat configuration for open-island
# Adapted from claude-island — updated for Swift 6.2 / Xcode 17

# Swift version
--swiftversion 6.2

# Indentation
--indent 4
--tabwidth 4
--smarttabs enabled
--indentcase false
--ifdef indent

# Line length
--maxwidth 150
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
--wrapreturntype preserve
--wrapconditions after-first
--closingparen balanced

# Spacing
--operatorfunc spaced
--ranges spaced
--typeattributes prev-line
--funcattributes prev-line
--varattributes same-line
--storedvarattrs same-line
--computedvarattrs same-line

# Braces
--allman false
--elseposition same-line
--guardelse next-line

# Imports
--importgrouping alpha

# Stripping
--stripunusedargs closure-only
--trimwhitespace always

# Semicolons
--semicolons inline

# Redundant
--redundanttype inferred
--self insert

# Other
--commas always
--decimalgrouping 3,6
--binarygrouping 4,8
--octalgrouping 4,8
--hexgrouping 4,8
--hexliteralcase uppercase
--exponentcase lowercase
--exponentgrouping disabled
--fractiongrouping disabled
--fragment false
--conflictmarkers reject
--shortoptionals always
--modifierorder

# Acronyms to preserve
# Added OI (project prefix), SSE (OpenCode), RPC (Codex), OTLP (telemetry)
--acronyms ID,URL,UUID,HTTP,HTTPS,JSON,API,UI,MCP,PID,JSONL,SSH,TCP,IP,DNS,HTML,XML,CSS,JS,SDK,CLI,TLS,SSL,OI,SSE,RPC,OTLP

# Exclude directories and files
# Note: No file-specific exclusions yet — start fresh. If organizeDeclarations
# causes timeouts on large files (e.g., HookSocketServer.swift), exclude then
# and document in CONTRIBUTING.md.
--exclude build,DerivedData,.build,Pods,releases,*.xcodeproj,*.xcworkspace,xcuserdata,.sparkle-keys,OpenIslandKit/.build

# Rules to enable
--enable acronyms
--enable blankLinesBetweenImports
--enable blockComments
--enable docComments
--enable isEmpty
--enable markTypes
--enable organizeDeclarations
--enable sortDeclarations
--enable wrapEnumCases
--enable wrapSwitchCases

# Rules to disable
# - andOperator: project prefers && over comma separation in conditions
# - redundantSendable: Swift 6.2 region-based isolation (SE-0414) means many
#   explicit Sendable conformances that look redundant are actually intentional
#   public API contracts — do not auto-remove them
# - wrapMultilineStatementBraces: conflicts with project style
--disable andOperator
--disable redundantSendable
--disable wrapMultilineStatementBraces
```

#### 0.3.3 `.swiftlint.yml`

Adapt the claude-island config:

- [x] **`included:`**: update from `[ClaudeIsland]` to `[OpenIsland, OpenIslandKit]` (main app + SPM package sources)
- [x] **`excluded:`**: keep `build`, `DerivedData`, `.build`, `Pods`, `releases`, `*.xcodeproj`, `*.xcworkspace`, `xcuserdata`
- [x] **Opt-in rules**: keep the full list from claude-island with the following changes:
  - [x] **Remove** `single_test_class` — move to `disabled_rules`. This rule is incompatible with Swift Testing: Swift Testing uses `@Suite` structs (not `XCTestCase` subclasses), multiple `@Suite` structs per file is valid, and global `@Test` functions have no enclosing type at all.
  - [x] **Add** `private_over_fileprivate` — for clean module boundaries in a greenfield project
- [x] **Rule configs**: keep all thresholds (line_length 150/200, function_body_length 60/100, file_length 500/1000, type_body_length 300/500, cyclomatic_complexity 15/25, nesting 3/5 type + 5/8 function)
- [x] **Identifier exclusions**: keep `id, ok, to, x, y, i, j, n` — add `fd` for file descriptors used in `~Copyable` resource types (e.g., `FileHandle` with `fd: Int32`)
- [x] **Custom `no_print_statements` rule**: keep — use `os.Logger` throughout the project instead of `print()`
- [x] **Add custom `no_observable_object` rule**: warn on `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` — enforces the project's `@Observable`-only convention at lint time instead of relying on developer memory
- [x] **Add custom `no_combine_import` rule**: warn on `import Combine` — enforces the project's `AsyncStream`-only convention

> **Note on `no_observable_object` `match_kinds`**: SwiftLint's `match_kinds` restricts matches to specific syntax token types. Use `[identifier, attribute.builtin]` to target code tokens and attributes. Test the rule against files containing these terms in comments (e.g., `// We migrated from ObservableObject`) and strings to verify no false positives in documentation. If false positives occur, restrict to `[attribute.builtin]` only and add a separate regex for the protocol name matching `[identifier]` with a negative lookbehind for `//`.

Full config:

```yaml
# SwiftLint configuration for open-island
# Adapted from claude-island — updated for Swift 6.2 / Swift Testing

# Lint both the main app target and the SPM package sources
included:
  - OpenIsland
  - OpenIslandKit

# Exclude build artifacts and generated files
excluded:
  - build
  - DerivedData
  - .build
  - Pods
  - releases
  - "*.xcodeproj"
  - "*.xcworkspace"
  - xcuserdata

# Opt-in rules for Swift best practices
opt_in_rules:
  - array_init
  - attributes
  - closure_end_indentation
  - closure_spacing
  - collection_alignment
  - contains_over_filter_count
  - contains_over_filter_is_empty
  - contains_over_first_not_nil
  - contains_over_range_nil_comparison
  - discouraged_object_literal
  - empty_collection_literal
  - empty_count
  - empty_string
  - enum_case_associated_values_count
  - explicit_init
  - extension_access_modifier
  - fallthrough
  - fatal_error_message
  - file_name_no_space
  - first_where
  - flatmap_over_map_reduce
  - force_unwrapping
  - identical_operands
  - implicitly_unwrapped_optional
  - joined_default_parameter
  - last_where
  - legacy_multiple
  - literal_expression_end_indentation
  - lower_acl_than_parent
  - modifier_order
  - multiline_function_chains
  - multiline_literal_brackets
  - multiline_parameters
  - operator_usage_whitespace
  - optional_enum_case_matching
  - overridden_super_call
  - prefer_self_in_static_references
  - prefer_self_type_over_type_of_self
  - prefer_zero_over_explicit_init
  - private_action
  - private_outlet
  - private_over_fileprivate
  - prohibited_super_call
  - reduce_into
  - redundant_nil_coalescing
  - redundant_type_annotation
  - sorted_first_last
  - sorted_imports
  - static_operator
  - toggle_bool
  - trailing_closure
  - unavailable_function
  - unneeded_parentheses_in_closure_argument
  - unowned_variable_capture
  - untyped_error_in_catch
  - vertical_parameter_alignment_on_call
  - vertical_whitespace_closing_braces
  - vertical_whitespace_opening_braces
  - yoda_condition

# Disable rules that are too strict or noisy
disabled_rules:
  - todo
  - trailing_comma
  # single_test_class: incompatible with Swift Testing — Swift Testing uses
  # @Suite structs (not XCTestCase subclasses), multiple @Suite structs per
  # file is valid, and global @Test functions have no enclosing type at all.
  - single_test_class

# Rule configurations
line_length:
  warning: 150
  error: 200
  ignores_comments: true
  ignores_urls: true
  ignores_function_declarations: false
  ignores_interpolated_strings: true

function_body_length:
  warning: 60
  error: 100

file_length:
  warning: 500
  error: 1000
  ignore_comment_only_lines: true

type_body_length:
  warning: 300
  error: 500

cyclomatic_complexity:
  warning: 15
  error: 25

nesting:
  type_level:
    warning: 3
    error: 5
  function_level:
    warning: 5
    error: 8

identifier_name:
  min_length:
    warning: 2
    error: 1
  max_length:
    warning: 50
    error: 60
  excluded:
    - id
    - ok
    - to
    - x
    - y
    - i
    - j
    - n
    # Common in ~Copyable / ownership code
    - fd

large_tuple:
  warning: 4
  error: 5

force_cast: warning
force_try: warning
force_unwrapping: warning

# Custom rules
custom_rules:
  no_print_statements:
    name: "No Print Statements"
    regex: "\\bprint\\s*\\("
    message: "Use os.Logger instead of print() for logging"
    severity: warning
    match_kinds:
      - identifier

  no_observable_object:
    name: "No ObservableObject"
    regex: "\\b(ObservableObject|@Published|@StateObject|@ObservedObject|@EnvironmentObject)\\b"
    message: "Use @Observable / @Bindable / @State / @Environment instead (Swift 6.2 Observation)"
    severity: error
    match_kinds:
      - identifier
      - attribute.builtin

  no_combine_import:
    name: "No Combine Import"
    regex: "^import Combine$"
    message: "Use AsyncStream instead of Combine (project convention)"
    severity: error

  no_nonisolated_unsafe:
    name: "No nonisolated(unsafe)"
    regex: "\\bnonisolated\\s*\\(\\s*unsafe\\s*\\)"
    message: "Use Mutex<T> or actor instead of nonisolated(unsafe)"
    severity: error
```

#### 0.3.4 `justfile`

Create a `justfile` with recipes for the development workflow. See Phase 0.8.1 for the full recipe table.

Key recipes: `just format`, `just lint`, `just test`, `just build`, `just build-release`, `just pre-commit`, `just clean`, `just install-hooks`.

- [x] **Optional**: Consider adding SwiftLint and SwiftFormat as SwiftPM command plugins (SE-0332) for IDE-integrated linting via `swift package plugin swiftlint`. This complements the pre-commit hooks by enabling linting from any context without hook installation. Evaluate if team workflow benefits from this during Phase 13.

#### 0.3.5 Verify Pipeline End-to-End

- [x] Run `just install-hooks`
- [x] Create a test Swift file with intentional formatting issues
- [x] Commit → verify SwiftFormat auto-fixes, SwiftLint catches violations
- [x] Create a test Python file in `Resources/Hooks/` → verify Ruff catches issues
- [x] Confirm `just pre-commit` passes cleanly on the empty project skeleton
- [x] Verify the `no_observable_object` custom rule fires on `@Published var test = ""` in a test file, and does **not** fire on `// We migrated from ObservableObject` in a comment
- [x] Verify the `no_combine_import` custom rule fires on `import Combine` in a test file
- [x] Clean up test files after verification

### 0.4 Testing Infrastructure

- [x] Add a `OICoreTests` target using Swift Testing (`import Testing`)
- [x] Add a `OIStateTests` target for state machine and SessionStore tests
- [x] Add a `OIProvidersTests` target for provider adapter tests
- [x] Configure all test suites as `@Suite` structs (not classes)
- [x] Establish parameterized test patterns for multi-provider scenarios
- [x] Note: `single_test_class` SwiftLint rule is disabled — multiple `@Suite` structs per file and global `@Test` functions are valid Swift Testing patterns
- [x] Define project-wide test tags: `extension Tag { @Tag static var claude: Self; @Tag static var codex: Self; @Tag static var gemini: Self; @Tag static var opencode: Self; @Tag static var socket: Self; @Tag static var ui: Self }`. Use `.serialized` on suites with shared file system resources. Use `.timeLimit(.minutes(1))` on socket tests. Use `.disabled("reason")` over commenting out tests. Use `.enabled(if:)` for provider-specific tests conditional on binary availability. Use `.bug(id:)` to link tests to bug tracker.
- [x] Implement custom test traits for common setup/teardown: `MockSocketTrait` (creates/destroys temp socket), `TempDirectoryTrait` (creates/cleans temp directory), `MockHTTPServerTrait` (starts/stops a local HTTP server for OpenCode SSE testing). Uses `TestTrait` + `TestScoping` (Swift 6.1+).
- [x] XCTest remains required for UI testing (XCUITest) and performance benchmarking (`measure {}`). Create separate XCTest-based targets if needed. Do not mix XCTest and Swift Testing assertions in the same file.
- [x] Name test files as `<TypeUnderTest>Tests.swift`: `SessionPhaseTests.swift`, `JSONValueTests.swift`, `ClaudeEventNormalizerTests.swift`, `CodexJSONRPCClientTests.swift`, `GeminiEventNormalizerTests.swift`, `OpenCodeSSEClientTests.swift`.

> **CI test execution**: See Phase 0.8.8 for CI-specific test execution details (result bundles, parallel testing, no-retry policy, release workflow gates).

### 0.5 Git & CI Foundations

- [x] Initialize repo with `.gitignore` (Xcode, SPM, DerivedData, build artifacts)
- [x] Set up branch protection on `main`
- [x] Add a basic GitHub Actions workflow: build + test on macOS runner
- [x] Install pre-commit hooks

### 0.6 Approachable Concurrency Strategy (Swift 6.2)

This is a **deliberate architectural decision**, not just build flags. Swift 6.2's Approachable Concurrency has three pillars — all three must be configured consistently across the project.

#### 0.6.1 Pillar 1 — MainActor by Default ("single-threaded by default")

- [x] **App target** (`OpenIsland`): enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466). This means every type, function, and property in the app target is `@MainActor`-isolated unless explicitly opted out.
- [x] **SPM library targets** (`OICore`, `OIProviders`, etc.): keep `nonisolated` as the default. Libraries should not assume main-thread execution — they are consumed by the app target, which decides isolation.
- [x] **Implication**: all model types, utility functions, and protocol definitions in SPM targets must be explicitly `nonisolated` (which they are by default in those targets). When used from the app target, the compiler handles the isolation boundary correctly.
- [x] In `Package.swift`, only the app-facing target gets `.defaultIsolation(MainActor.self)`. In Xcode, set the build setting on the app target only.

#### 0.6.2 Pillar 2 — Nonisolated Nonsending by Default ("intuitive async functions")

- [x] Enable `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` (SE-0461) on **all targets**.
- [x] **What this changes**: nonisolated `async` functions no longer hop to the global concurrent executor. They run in the caller's execution context. This means calling an `async` function from the main actor keeps you on the main actor — no implicit thread hop.
- [x] **Practical impact**: most `async` functions in the app "just work" without data-race issues. You can write `async` methods on classes without needing `@Sendable` closures or actor isolation annotations everywhere.
- [x] **Where this matters most**: `ConversationParser`, `ClaudeAPIService`, and other actors already serialize access. But helper `async` functions that don't need their own isolation domain (e.g., file reading utilities, JSON parsing) will stay on the caller's actor instead of bouncing to a background thread.

#### 0.6.3 Pillar 3 — Infer Isolated Conformances ("less boilerplate")

- [x] Enable `.enableUpcomingFeature("InferIsolatedConformances")` (SE-0470) on **all targets**.
- [x] **What this changes**: when a type is isolated to an actor (e.g., MainActor-isolated in the app target), its protocol conformances are automatically inferred as isolated too. Without this flag, conforming to a protocol like `Hashable` from a MainActor-isolated type requires explicitly marking `hash(into:)` as `nonisolated` or `@MainActor`.
- [x] **Practical impact**: `@Observable` view models in the app target can conform to protocols without boilerplate isolation annotations. Model types in library targets (which default to `nonisolated`) are unaffected.
- [x] **Example**: With this flag enabled, a MainActor-isolated type conforming to `Equatable` gets its `==` method inferred as MainActor-isolated automatically, instead of requiring explicit annotation.

#### 0.6.4 `@concurrent` Usage Guidelines ("opting into concurrency")

- [x] `@concurrent` is a usage pattern within SE-0461 (Pillar 2), not a separate pillar. It is the explicit opt-in for off-actor execution when the default (run on caller's actor) is not appropriate.
- [x] Use `@concurrent` **only** on functions that genuinely need to run off the calling actor — CPU-heavy computation, blocking I/O that shouldn't freeze the main thread, or work that benefits from parallelism.
- [x] Examples in `open-island`:
  - [x] `@concurrent func parseJSONLChunk(_ data: Data) async -> [ChatMessage]` — parsing large JSONL chunks should not block the main actor
  - [x] `@concurrent func detectPythonRuntime() async -> PythonRuntime?` — spawns subprocesses, should not block UI
  - [x] `@concurrent func buildProcessTree() async -> [Int32: Int32]` — enumerates all PIDs, CPU-bound
  - [x] `@concurrent func parseCodexJSONRPC(_ data: Data) async -> JSONRPCMessage` — parsing Codex app-server JSONL should not block the main actor
  - [x] `@concurrent func connectSSEStream(_ url: URL) async throws -> AsyncStream<SSEEvent>` — long-lived HTTP connection for OpenCode SSE should not block any actor
- [x] **Rule**: if a function doesn't need to run in parallel, don't mark it `@concurrent`. The default (run on caller's actor) is safer and simpler.

#### 0.6.5 Configuration Summary

| Target | Default Isolation | NonisolatedNonsending | InferIsolatedConformances | `@concurrent` Usage |
|---|---|---|---|---|
| `OpenIsland` (app) | `MainActor` | Yes (upcoming feature) | Yes (upcoming feature) | Sparingly — heavy computation only |
| `OICore` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | On CPU-bound utilities |
| `OIProviders` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | On file I/O, process spawning, SSE connections, JSON-RPC parsing |
| `OIState` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Rarely — actors serialize already |
| `OIWindow` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Never — all UI work |
| `OIUI` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Never — all UI work |
| `OIModules` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Never — all UI work |

#### 0.6.6 Document the Concurrency Contract

Create `CONCURRENCY.md` in the repo root explaining:

- [x] Why `MainActor` is the default for the app target (safety, simplicity, matches Xcode 17's default template)
- [x] Why library targets stay `nonisolated` (reusability, no main-thread assumption)
- [x] When to use `@concurrent` (include the 5 examples above as canonical patterns)
- [x] When to use `actor` (shared mutable state accessed from multiple isolation domains)
- [x] When to use `Mutex<T>` (protecting state in `Sendable` classes, GCD-bridging code). **`Mutex<T>` requires `import Synchronization`** (Swift 6.0+) — add this import wherever `Mutex` is used. The `Synchronization` framework is a compiler-level module with no OS runtime dependency (back-deploys freely).
- [x] When **not** to mark functions `@concurrent` (most of the time — the default is correct)
- [x] When `InlineArray` (SE-0452) may be a fit for fixed-size buffers with trivially-copyable elements (e.g., small `ProviderID` → color lookup tables) — note as a future optimization opportunity, but **not** suitable for collections of complex types like `SessionEvent` (see Phase 2.1 note)
- [x] When to use `@preconcurrency import` for legacy frameworks (see Phase 0.7)
- [x] **`nonisolated(unsafe)` — never use in this project.** Prefer `Mutex<T>`, `actor`, or `@preconcurrency import`. A SwiftLint custom rule (`no_nonisolated_unsafe`) enforces this at compile time (Phase 0.3.3).
- [x] **`async let` for structured concurrency**: use `async let` for fixed-count parallel operations; task groups for dynamic counts. Example:

  ```swift
  // Phase 3.6 — starting independent subsystems
  async let hooks = installer.install()
  async let socket = socketServer.start()
  async let watcher = conversationParser.startWatching()
  try await (hooks, socket, watcher)
  ```

- [x] **`Task.init` closures use `sending` semantics (not `@Sendable`)**: In Swift 6, `Task { }` closures use `sending` semantics. Captured values need only be disconnected from their current isolation region, not fully `Sendable`. Don't reflexively add `Sendable` conformance just because a type is captured in a `Task { }` closure.
- [x] **`Span<T>` for safe contiguous access**: Prefer `Span<T>` (SE-0447) over `UnsafeBufferPointer` for read-only contiguous access. Full adoption requires `@lifetime` annotations (experimental in 6.2). Adopt incrementally as annotations stabilize.
- [x] **Forward-scan trailing closures** (SE-0286): Swift 6 changed trailing closure matching from backward-scan to forward-scan. When designing APIs with multiple closure parameters, the first trailing closure label is dropped. Use labeled trailing closures for all subsequent closure parameters. Avoid trailing closure syntax in `guard` conditions.

### 0.7 Legacy Framework Import Strategy

Several system frameworks predate Swift concurrency and may produce Sendable diagnostics in strict Swift 6 mode. Use `@preconcurrency import` to suppress warnings from frameworks the project cannot control:

- [x] **`@preconcurrency import Dispatch`** — required in `ClaudeHookSocketServer.swift` (Phase 3.1) and anywhere using `DispatchSource`, `DispatchQueue`, or GCD primitives
- [x] **`@preconcurrency import AppKit`** — may be needed in `NotchPanel.swift`, `WindowManager.swift`, and other AppKit-bridging code where `NSWindow`, `NSEvent`, or `NSScreen` types cross isolation boundaries
- [x] **`@preconcurrency import CoreGraphics`** — if `CGWindowListCopyWindowInfo` results trigger Sendable warnings in `TerminalVisibilityDetector.swift`

**Preferred approach — `OIAppKitBridge` module**: rather than scattering `@preconcurrency import AppKit` across multiple files, consider creating a thin `OIAppKitBridge` internal module that encapsulates all AppKit interactions behind `@MainActor`-isolated `Sendable` wrappers. This confines `@preconcurrency` to one module's source files and gives the rest of the codebase clean, compiler-verified types to work with. Evaluate feasibility in Phase 4; if the bridging surface is small enough, a single module is cleaner than per-file annotations.

**Rule**: if the `OIAppKitBridge` approach is not feasible, use `@preconcurrency import` only on the specific files that need it, not as a blanket project-wide practice. Each usage should include a comment explaining which types cause the diagnostic. Treat these as temporary — remove them when Apple ships Sendable-annotated framework headers.

Document these in `CONCURRENCY.md` under a "Legacy Framework Imports" section.

# Phase 0.8 — Build Scripts, CI/CD & Release Infrastructure

> Insert after Phase 0.7 (Legacy Framework Import Strategy) and before Phase 1.

This phase establishes the complete build, test, and release pipeline. All CI workflows
use the `justfile` as their single entry point — scripts are never called directly from
workflow YAML. This ensures local development and CI always run the same commands.

---

## 0.8.1 Task Runner (`justfile`)

- [x] Install `just`: `brew install just`
- [x] Create `justfile` in the repo root with these recipes:

| Recipe | Purpose | Used by CI |
|---|---|---|
| `build` | Debug build (ad-hoc signed) | — |
| `build-release` | Release build, export .app to `build/export/` | `ci.yml`, `release.yml` |
| `build-package` | Build SPM package independently via `swift build` | `ci.yml` |
| `resolve` | Resolve SPM dependencies explicitly | `ci.yml` |
| `test` | Run all tests (SPM package tests) | — |
| `test-ci` | Run tests with CI settings | `ci.yml`, `release.yml` |
| `test-package` | Run SPM package tests via `swift test` | — |
| `format` | SwiftFormat auto-fix | — |
| `format-check` | SwiftFormat lint (no modification, CI-safe) | `code-quality.yml` |
| `lint` | SwiftLint strict mode | `code-quality.yml` |
| `lint-fix` | SwiftLint auto-correct + verify | — |
| `quality` | `format-check` + `lint` combined | `code-quality.yml` |
| `install-hooks` | `prek install` for pre-commit + pre-push | — |
| `update-hooks` | `prek autoupdate` (update all hook revs) | — |
| `pre-commit` | `prek run --all-files` (manual full check) | — |
| `dmg` | `build-release` then `create-release.sh --skip-notarization` | — |
| `release` | Full local release pipeline | — |
| `generate-keys` | Sparkle EdDSA key generation | — |
| `version` | Show current version from Xcode project | — |
| `set-version <ver>` | Set marketing version (`just set-version 1.2.3`) | — |
| `bump-build` | Increment build number (timestamp) | — |
| `clean` | Remove build artifacts | — |
| `nuke` | Deep clean including releases and Xcode caches | — |
| `check-tools` | Verify all required dev tools are installed | — |

#### Why `just` over `make`

`just` is a modern command runner purpose-built for project task automation:

- **Clean syntax**: no tab-sensitivity, no `.PHONY` boilerplate, built-in argument handling
- **Built-in `--list`**: `just --list` shows all recipes with descriptions — no grep hacks
- **Native arguments**: `just set-version 1.2.3` instead of `make set-version V=1.2.3`
- **Path helpers**: `justfile_directory()` for reliable relative paths
- **Single binary**: `brew install just` — trivial for the target audience (macOS developers using Homebrew)

The project does not use any of Make's actual build-system features (dependency graphs, incremental file-based rebuilds) — every target would be `.PHONY`. `just` is the right tool for a task-runner role.

- [x] The justfile defines shared configuration variables (`scheme`, `package_dir`, `build_dir`, etc.) used by all recipes — these are the canonical source for project naming
- [x] `test-ci` differs from `test` in: combined stdout/stderr for log capture (both use `swift test` as the sole test runner)

---

## 0.8.2 Build Script (`scripts/build.sh`)

- [x] Port from claude-island with these changes:
  - [x] All references: `ClaudeIsland` → `OpenIsland`, `Claude Island` → `Open Island`
  - [x] Scheme name: `OpenIsland`
  - [x] DerivedData path: `build/DerivedData` (consistent with justfile)

- [x] **Version sync check**: uses `agvtool what-marketing-version -terse1` to read the current `MARKETING_VERSION` from `project.pbxproj`. This works correctly with the modern Xcode pattern where `Info.plist` references `$(MARKETING_VERSION)` — `agvtool` reads the build setting, not the plist. Warns if local version differs from latest git tag.

- [x] **Explicit SPM resolution**: calls `xcodebuild -resolvePackageDependencies` before building. This surfaces dependency failures early and separately from build failures. Particularly important with the `OpenIslandKit` local package — resolution verifies the package graph is valid before compilation begins.

- [x] **Post-build validation**: verifies the `.app` bundle exists at the expected path before declaring success. The app bundle path is `$DERIVED_DATA/Build/Products/Release/Open Island.app`.

- [x] Script outputs match justfile expectations — `build/export/Open Island.app` is the canonical export location used by both `create-release.sh` and the CI workflows.

---

## 0.8.3 Release Script (`scripts/create-release.sh`)

- [x] Port from claude-island with these changes:
  - [x] GitHub repo: `engels74/open-island`
  - [x] App name: `OpenIsland` (identifier), `Open Island` (display name)
  - [x] Keychain profile: `OpenIsland`
  - [x] Website env var: `OPEN_ISLAND_WEBSITE` (defaults to `../open-island-website`)
  - [x] Sparkle tool search paths updated for `OpenIsland-*` DerivedData

- [x] **Version reading strategy**: reads version from the **built app's Info.plist** via `PlistBuddy`, not from `project.pbxproj` or `agvtool`. Rationale: the built plist is the canonical artifact — it reflects exactly what `xcodebuild` compiled. This avoids discrepancies between project settings and the actual binary.

- [x] **Six-step pipeline** (each skippable via `--skip-*` flag):
  1. Notarize the `.app` bundle
  2. Create DMG (via `create-dmg` if available, `hdiutil` fallback)
  3. Notarize the DMG
  4. Sign DMG for Sparkle + generate `appcast.xml`
  5. Create GitHub Release + upload DMG
  6. Update website appcast + deploy

- [x] **`--help` flag** added for discoverability

---

## 0.8.4 Sparkle Key Generation (`scripts/generate-keys.sh`)

- [x] Port from claude-island — minimal changes beyond naming
- [x] Search paths updated for `OpenIsland-*` DerivedData
- [x] Reminds user to add private key as `SPARKLE_PRIVATE_KEY` GitHub secret

---

## 0.8.5 Version Management Strategy

**Decision: `agvtool` as primary, `sed` as fallback.**

`agvtool` is Apple's official tool for managing Xcode project versions. It modifies `project.pbxproj` directly and correctly handles:

- Multiple build configurations (Debug, Release)
- Multiple targets in the project
- The modern `$(MARKETING_VERSION)` variable-reference pattern in Info.plist

The `sed`-based approach from claude-island's release workflow (`sed -i '' "s/MARKETING_VERSION = .*;/..."`) is fragile because:

- It does a global replacement across the entire pbxproj
- It can match in unexpected places if there are multiple targets or configurations
- It doesn't understand the pbxproj structure

**Approach in CI** (release.yml):

1. Use `agvtool new-marketing-version $VERSION` to set the version
2. Use `agvtool new-version -all $BUILD_NUMBER` to set the build number
3. Verify with `agvtool what-marketing-version -terse1`
4. If verification fails, fall back to `sed` with a `::error::` annotation

**Approach locally**:

- `just set-version 1.2.3` wraps `agvtool new-marketing-version`
- `just bump-build` wraps `agvtool new-version -all` with timestamp
- `just version` shows current version

**Version commit in CI**: The release workflow commits the version bump to `main`. If the push fails (concurrent update), the release continues — the DMG already has the correct version baked in. This is non-fatal because the version bump is a convenience (keeping the repo in sync), not a prerequisite for the release artifact.

---

## 0.8.6 CI Workflows

### Architecture

```
push/PR to main ──→ [Code Quality] ──success──→ [CI]
                         │                        │
                    lint, format              test, build,
                    pre-commit checks        DMG artifact,
                                             VirusTotal scan

push tag v*.*.* ──→ [Release]
                      │
                  test → build → sign → publish → VT scan → website update
```

All workflows use `concurrency` groups to cancel in-progress runs for the same ref, except releases which never cancel.

### Runner Strategy

- [x] **Target**: `macos-16` runners (macOS 16 Tahoe with Xcode 17 / Swift 6.2)
- [x] **Swift version gate**: every workflow verifies `swift --version` outputs 6.2+ and fails fast with a clear error if not. This catches runner misconfigurations early.
- [ ] **Fallback plan**: if GitHub-hosted `macos-16` runners are unavailable at project start, temporarily use `macos-15` with `xcode-version: latest-stable` and set deployment target to macOS 15 in the Xcode project. The Phase 0.1 deployment target (macOS 16.0) can be enforced once `macos-16` runners are available. Document this in `CONTRIBUTING.md` under "CI Runners".
- [ ] **Self-hosted option**: if neither GitHub-hosted option provides Swift 6.2, document how to set up a self-hosted macOS runner. This is a last resort — GitHub-hosted runners are preferred for reproducibility.

### `just` Installation in CI

All workflow jobs that call justfile recipes install `just` as their first tool step:

```yaml
- name: Install just
  run: brew install just
```

This is fast (single binary, no dependencies) and ensures the same task runner is available in every job. Combined with `brew install swiftformat swiftlint` (no version pinning), CI always uses the latest tooling.

### Workflow: Code Quality (`code-quality.yml`)

- [x] Triggers: push to `main`, PRs targeting `main`
- [x] Skips on `[skip ci]` commit messages
- [x] Steps:
  1. Checkout
  2. Setup Xcode (latest-stable)
  3. Verify Swift 6.2+
  4. Install `just`, SwiftFormat, SwiftLint via `brew install` (always latest, no version pinning)
  5. `just format-check` — verify formatting without modification
  6. `just lint` — SwiftLint strict mode
  7. Pre-commit checks via `pre-commit-action` — runs remaining hooks (shellcheck, ruff, markdownlint, standard hooks). SwiftFormat/SwiftLint are `SKIP`'d here since they're covered by explicit justfile steps above (with version-controlled output).

**Why separate `just format-check` + `just lint` from pre-commit?**
Pre-commit runs SwiftFormat/SwiftLint via `language: system` which uses whatever binary is on PATH. The explicit justfile steps ensure CI uses the freshly-installed latest versions and produces clear, attributable error output. Pre-commit covers everything else (shellcheck, ruff, yaml/json checks, etc.).

### Workflow: CI (`ci.yml`)

- [x] Triggers: after `Code Quality` workflow completes successfully on `main`
- [x] Jobs:
  1. **Test** — `just resolve` → `just build-package` → `just test-ci`. Uploads `.xcresult` bundle as artifact (always, even on failure — for debugging).
  2. **Build** (needs test) — `just build-release` → create DMG → upload artifact. Gets version from built app's Info.plist.
  3. **VirusTotal Scan** (needs build, conditional on `HAS_VT_KEY` repository variable) — downloads DMG artifact, scans, creates summary.

- [x] **SPM package build as separate step**: `just build-package` runs `swift build` on the `OpenIslandKit` package independently of Xcode. This catches issues that Xcode's integrated build might mask (e.g., missing `public import` declarations, target dependency gaps, platform-conditional compilation issues).

### Workflow: Release (`release.yml`)

- [x] Triggers: push tag matching `v[0-9]+.[0-9]+.[0-9]+`, or manual dispatch with version input
- [x] **Concurrency**: `group: release`, `cancel-in-progress: false` — never cancel a release in progress
- [x] Jobs:
  1. **Test** — full test suite via `just test-ci` (same as CI, but runs independently for release isolation)
  2. **Build & Sign** (needs test) — version management → build → DMG → Sparkle sign → GitHub Release
  3. **VirusTotal Scan** (needs build) — scan + append results to release notes
  4. **Update Website** (needs build, conditional on Sparkle signature) — repository dispatch to `engels74/open-island-web`

- [x] **Version management in release**: see Phase 0.8.5 — uses `agvtool` with `sed` fallback, commits version bump to `main`, non-fatal push failure.

- [x] **DMG filename normalization**: `create-release.sh` names the DMG from the built app's Info.plist version. The workflow renames to match the tag version for consistent download URLs. This handles the edge case where agvtool failed and the built version differs from the tag.

---

## 0.8.7 Pre-commit Hook Versioning (Amendment to Phase 0.3.1)

The `.pre-commit-config.yaml` in Phase 0.3.1 pins specific `rev` values for all hook repositories. Pre-commit **requires** pinned revs — there is no "latest" option. However, since SwiftFormat and SwiftLint hooks use `language: system`, the `rev` only determines the hook definition script version, not the tool binary version. The actual binary version is whatever is installed on the system.

**Strategy for keeping hooks current**:

- [x] **`just update-hooks`** recipe: runs `prek autoupdate`, which bumps all `rev` values in `.pre-commit-config.yaml` to the latest release of each repository. Run periodically (e.g., monthly or before major releases) and commit the changes.

- [x] **CI installs latest**: `code-quality.yml` runs `brew install swiftformat swiftlint` without version pinning, ensuring CI always uses the latest release. The `ci: skip: [swiftformat, swiftlint]` in `.pre-commit-config.yaml` prevents pre-commit from running its own (potentially stale-rev) copies of these tools in CI — the explicit `just format-check` and `just lint` steps use the freshly-installed latest versions instead.

- [x] **Local development**: developers run `brew upgrade swiftformat swiftlint` periodically. The pre-commit hooks use `language: system` so they automatically pick up the system-installed version.

- [x] **No version-pinning comments**: remove any version-specific comments from `.pre-commit-config.yaml` that might discourage updates. Add a header comment:

  ```yaml
  # Hook revisions — update with: just update-hooks (runs prek autoupdate)
  # SwiftFormat and SwiftLint use language: system — the rev pins the hook
  # definition only; the actual binary version is whatever is installed.
  ```

---

## 0.8.8 Test Execution in CI (Amendment to Phase 0.4)

Phase 0.4 establishes the testing infrastructure. This section specifies how tests run in CI:

- [x] **SPM package tests in CI**: all test targets (`OICoreTests`, `OIStateTests`, `OIProvidersTests`) run via `swift test` in the `OpenIslandKit` directory. `xcodebuild test` cannot discover SPM test targets from local packages via CLI, so `swift test` is the sole test runner for both CI and local development. The scheme's TestAction includes these targets for Xcode GUI use only.

- [x] **Test result artifacts**: `swift test` does not produce `.xcresult` bundles. The CI workflow's "Upload test results" step will be a no-op until Xcode-native test targets (e.g., UI tests) are added. Test output is captured in CI logs directly.

- [x] **No test retries in CI**: `swift test` has no retry mechanism. Flaky tests must be fixed, not retried.

- [x] **Parallel testing**: `swift test` runs test targets in parallel by default. Suites using `.serialized` trait (Phase 0.4) will still run serially as configured.

- [x] **Test execution in release workflow**: the release workflow runs the full test suite (`just test-ci`) as a prerequisite before building. A release cannot be published if tests fail. This is a deliberate gate — even if the same commit passed CI earlier, the release runs tests independently for isolation.

---

## 0.8.9 Script Permissions & Repository Setup

- [x] Make all scripts executable: `chmod +x scripts/*.sh`
- [x] Verify `.gitignore` includes:

  ```
  build/
  DerivedData/
  .build/
  releases/
  .sparkle-keys/
  *.xcuserstate
  xcuserdata/
  ```

- [x] Verify `scripts/` directory is tracked in git (not ignored)
- [ ] Run `just check-tools` to verify development environment
- [ ] Run `just install-hooks` to set up pre-commit hooks
- [ ] Run `just pre-commit` to verify all hooks pass on the initial skeleton

---

## 0.8.10 Secrets & Repository Configuration

Configure these in GitHub repository settings (`Settings → Secrets and variables → Actions`):

**Secrets** (required for full pipeline):

- [ ] `a` — EdDSA private key from `just generate-keys` (required for Sparkle auto-update signing)
- [x] `VT_API_KEY` — VirusTotal API key (required for malware scanning)
- [x] `WEBSITE_PAT` — GitHub Personal Access Token with repo scope on `engels74/open-island-web` (required for website appcast updates)

**Variables**:

- [x] `HAS_VT_KEY` — set to `true` if `VT_API_KEY` is configured (controls conditional VirusTotal scan job in `ci.yml`)

**Branch protection** on `main`:

- [ ] Require `Code Quality / Lint & Format` to pass before merge
- [ ] Require PR reviews (optional but recommended)
- [ ] Allow `github-actions[bot]` to push version bump commits (bypass branch protection for bot)

---

## 0.8.11 Cross-references to Other Phases

This phase connects to several existing plan sections. When implementing, update these references:

- [x] **Phase 0.3.1** (`.pre-commit-config.yaml`): add header comment referencing `just update-hooks`. The plan uses `prek` directly (or via `just pre-commit`).
- [x] **Phase 0.3.4**: replace `Makefile / justfile` with just `justfile`. Remove the Makefile target list — it's superseded by the recipe table in Phase 0.8.1. Update the `install-hooks` reference to `just install-hooks`.
- [x] **Phase 0.3.5**: update verification commands: `prek install` → `just install-hooks`, `prek run --all-files` → `just pre-commit`.
- [x] **Phase 0.4** (Testing Infrastructure): add cross-reference to Phase 0.8.8 for CI-specific test execution details.
- [x] **Phase 11.2** (Release Pipeline): reference Phase 0.8.6's release workflow instead of duplicating the CI/CD description.
- [x] **Dependency Summary** table: add `just` (task runner, `brew install just`).

---

## Phase 1 — Core Models & Provider Protocol

### 1.1 Define `ProviderID` and `ProviderMetadata`

```
OICore/Provider/ProviderID.swift
OICore/Provider/ProviderMetadata.swift
```

- [x] `ProviderID` — a `RawRepresentable<String>`, `Sendable`, `Hashable` enum with cases: `.claude`, `.codex`, `.geminiCLI`, `.openCode`
- [x] `ProviderMetadata` — struct holding display name, icon name (SF Symbol or bundled), accent color, CLI binary name(s), event transport type (`.hookSocket`, `.jsonRPC`, `.hookSocket`, `.httpSSE`), config file format (`.json`, `.toml`, `.json`, `.json`), session log directory path
- [x] Both must be `Sendable` value types
- [x] **Note**: `ProviderID` has `String` raw values. `String` is a reference-counted, heap-allocated type and is **not** `BitwiseCopyable`. Do not mark `ProviderID` as `BitwiseCopyable` — the compiler would reject this conformance. `BitwiseCopyable` (SE-0426) is reserved for types whose stored properties are all trivially copyable via `memcpy` (e.g., enums with `Int` raw values and no associated values containing reference types).

### 1.2 Define Universal Event Types

```
OICore/Events/ProviderEvent.swift
OICore/Events/SessionEvent.swift
```

- [x] `ProviderEvent` — the normalized event enum that all providers emit:
  - [x] `.sessionStarted(SessionID, cwd: String, pid: Int32?)` — maps from: Claude `SessionStart`, Codex `thread/started`, Gemini `SessionStart`, OpenCode `session.created`
  - [x] `.sessionEnded(SessionID)` — maps from: Claude `SessionEnd`, Codex `turn/completed` with status `completed`, Gemini `SessionEnd`, OpenCode `session.deleted`
  - [x] `.userPromptSubmitted(SessionID)` — maps from: Claude `UserPromptSubmit`, Codex `turn/started` (user-initiated), Gemini `BeforeAgent`, OpenCode `message.updated` (role: user)
  - [x] `.processingStarted(SessionID)` — maps from: Claude `UserPromptSubmit` (implicit), Codex `turn/started`, Gemini `BeforeModel`, OpenCode `session.status` (status: processing)
  - [x] `.toolStarted(SessionID, ToolEvent)` — maps from: Claude `PreToolUse`, Codex `item/started` (commandExecution/mcpToolCall/fileChange), Gemini `BeforeTool`, OpenCode `tool.execute.before`
  - [x] `.toolCompleted(SessionID, ToolEvent, ToolResult?)` — maps from: Claude `PostToolUse`/`PostToolUseFailure`, Codex `item/completed`, Gemini `AfterTool`, OpenCode `tool.execute.after`
  - [x] `.permissionRequested(SessionID, PermissionRequest)` — maps from: Claude `PermissionRequest` hook, Codex `item/commandExecution/requestApproval` or `item/fileChange/requestApproval`, Gemini `Notification` (notification_type: ToolPermission) + `BeforeTool`, OpenCode `permission.asked`
  - [x] `.waitingForInput(SessionID)` — maps from: Claude `Stop`, Codex `turn/completed`, Gemini `AfterAgent`, OpenCode `session.idle`
  - [x] `.compacting(SessionID)` — maps from: Claude `PreCompact`, Codex `item/completed` (compacted item type), Gemini `PreCompress`, OpenCode `session.compacted`
  - [x] `.notification(SessionID, message: String)` — maps from: Claude `Notification`, Codex notify hook, Gemini `Notification`, OpenCode (via plugin events)
  - [x] `.chatUpdated(SessionID, [ChatHistoryItem])` — maps from: JSONL transcript parsing (Claude), session rollout files (Codex), session JSON (Gemini), message REST API (OpenCode)
  - [x] `.subagentStarted(SessionID, taskID: String, parentToolID: String?)` — maps from: Claude `SubagentStart`, Codex `item/started` (collabToolCall), Gemini (via MCP tool calls with `mcp_context`), OpenCode (nested tool calls)
  - [x] `.subagentStopped(SessionID, taskID: String)` — maps from: Claude `SubagentStop`, Codex `item/completed` (collabToolCall), Gemini (MCP tool result), OpenCode (nested tool result)
  - [x] `.configChanged(SessionID?)` — maps from: Claude `ConfigChange`, Codex `config/read` (polled), Gemini (settings.json watch), OpenCode `GET /config` (polled)
  - [x] `.diffUpdated(SessionID, unifiedDiff: String)` — maps from: Codex `turn/diff/updated`, OpenCode `session.diff`; Claude and Gemini emit this via file change tool results
  - [x] `.modelResponse(SessionID, textDelta: String)` — maps from: Codex `item/agentMessage/delta`, Gemini `AfterModel` (streaming chunks), OpenCode `message.part.updated` (delta); Claude emits full messages via JSONL transcript
  - [x] `.tokenUsage(SessionID, promptTokens: Int?, completionTokens: Int?, totalTokens: Int?)` — maps from: Codex `turn/completed` (token usage), Gemini `AfterModel` (usageMetadata.totalTokenCount), OpenCode (via provider-specific fields); Claude requires API-level integration
- [x] `SessionEvent` — internal event for the `SessionStore` (superset of ProviderEvent + UI events like `.permissionApproved`, `.archiveSession`, etc.)
- [x] All payloads are `Sendable` structs/enums — explicitly marked `Sendable` since they are `package`-visible and cross module boundaries

### 1.3 Define Session Models

```
OICore/Models/SessionState.swift
OICore/Models/SessionPhase.swift
OICore/Models/PermissionContext.swift
OICore/Models/ToolCallItem.swift
OICore/Models/ChatHistoryItem.swift
```

- [x] `SessionPhase` — state machine enum: `.idle`, `.processing`, `.waitingForInput`, `.waitingForApproval(PermissionContext)`, `.compacting`, `.ended`
  - [x] Include `canTransition(to:) -> Bool` with the validated transition table from claude-island
  - [x] Validated transitions, invalid ones logged and ignored
  - [x] Explicitly marked `Sendable` — the `.waitingForApproval(PermissionContext)` associated value requires `PermissionContext` to also be `Sendable`
  - [x] Use `guard let` shorthand (SE-0345) in transition validation methods:

    ```swift
    func validate(event: SessionEvent) -> SessionPhase? {
        guard let targetPhase = event.targetPhase else { return nil }
        guard canTransition(to: targetPhase) else { return nil }
        return targetPhase
    }
    ```

- [x] `SessionState` — complete snapshot struct:
  - [x] `id: String` (session ID)
  - [x] `providerID: ProviderID`
  - [x] `phase: SessionPhase`
  - [x] `projectName: String`
  - [x] `cwd: String`
  - [x] `pid: Int32?`
  - [x] `chatItems: [ChatHistoryItem]`
  - [x] `toolTracker: ToolTracker`
  - [x] `createdAt: Date`
  - [x] `lastActivityAt: Date`
  - [x] `tokenUsage: TokenUsageSnapshot?` — optional, populated by providers that report token counts (Codex, Gemini, OpenCode)
  - [x] Explicitly marked `Sendable` — all stored properties must be `Sendable`
- [x] `PermissionContext` — tool use ID, name, input, timestamp, `displaySummary` computed property, `risk: PermissionRisk?` (Codex provides risk levels with approval requests). Explicitly `Sendable`.
- [x] `PermissionRisk` — enum: `.low`, `.medium`, `.high` — maps from Codex's `risk` field in `requestApproval` events. Other providers default to `nil`.
- [x] `ChatHistoryItem` — ID, timestamp, type enum (`.user`, `.assistant`, `.toolCall`, `.thinking`, `.interrupted`, `.reasoning`). The `.reasoning` case maps from Codex's explicit `reasoning` item type. Explicitly `Sendable`.
- [x] `ToolCallItem` — name, input, status (`.running`, `.success`, `.error`, `.interrupted`), result, nested subagent tools, `providerSpecific: JSONValue?` (captures provider-specific metadata like Codex's `exitCode`, `durationMs`; OpenCode's LSP diagnostics). Explicitly `Sendable`.
- [x] `TokenUsageSnapshot` — struct: `promptTokens: Int?`, `completionTokens: Int?`, `totalTokens: Int?`, `timestamp: Date`. Explicitly `Sendable`.
- [x] Simple leaf enums with no reference types (`PermissionDecision`, `ModuleSide`, `ToolStatus`, `PermissionRisk`) should be marked `BitwiseCopyable` (SE-0426) — these contain only trivial cases (no `String` associated values, no reference-type payloads) and explicit conformance on `package`-visible types enables more efficient generic code paths.
- [x] Note: `BitwiseCopyable` is auto-inferred for `internal` types but must be declared explicitly when promoting to `package` or `public`. Audit for missing conformance when elevating access levels.

### 1.4 Define `JSONValue` Type

```
OICore/Models/JSONValue.swift
```

- [x] Recursive enum: `.string`, `.int`, `.double`, `.bool`, `.null`, `.array([JSONValue])`, `.object([String: JSONValue])`
- [x] `Sendable`, `Equatable`, `Codable`
- [x] Replaces `AnyCodable` / `@unchecked Sendable` dictionary patterns
- [x] Include subscript accessors for ergonomic nested access
- [x] Used extensively for provider-specific payloads: Claude hook stdin JSON, Codex JSON-RPC messages, Gemini hook stdin JSON, OpenCode SSE event data

### 1.5 Provider Adapter Protocol

```
OIProviders/ProviderAdapter.swift
```

- [x] Protocol definition:

  ```swift
  package protocol ProviderAdapter: Sendable {
      var providerID: ProviderID { get }
      var metadata: ProviderMetadata { get }

      /// Transport type determines the integration pattern:
      /// - `.hookSocket`: Claude Code, Gemini CLI — hook scripts forward JSON over Unix socket
      /// - `.jsonRPC`: Codex CLI — bidirectional JSON-RPC 2.0 over stdio
      /// - `.httpSSE`: OpenCode — HTTP server with SSE event streams
      var transportType: ProviderTransportType { get }

      func start() async throws(ProviderStartupError)
      func stop() async

      /// Stream of normalized events from this provider
      func events() -> some AsyncSequence<ProviderEvent, Never>

      /// Respond to a permission request.
      /// Uses plain `throws` intentionally — failure modes are provider-specific
      /// and not a closed domain (network errors, timeout, provider-specific
      /// protocol failures, etc.).
      ///
      /// Permission response mechanisms differ by provider:
      /// - Claude Code: write JSON response to held-open Unix socket connection
      /// - Codex CLI: send JSON-RPC response to server-initiated request
      /// - Gemini CLI: BeforeTool hook returns deny/allow via stdout JSON
      /// - OpenCode: POST /session/{id}/permissions/{permId} via REST API
      func respondToPermission(
          _ request: PermissionRequest,
          decision: PermissionDecision
      ) async throws

      /// Check if a session is still alive
      func isSessionAlive(_ sessionID: String) -> Bool
  }
  ```

- [x] `ProviderTransportType` — enum: `.hookSocket`, `.jsonRPC`, `.httpSSE`
- [x] `PermissionDecision` — enum: `.allow`, `.deny(reason: String?)`
- [x] Each provider implementation is a concrete actor conforming to this protocol

#### Typed throws candidates

Use `throws(ErrorType)` (SE-0413) in these closed error domains:

- [x] **`ProviderAdapter.start()`** → `throws(ProviderStartupError)`:

  ```swift
  package enum ProviderStartupError: Error, Sendable {
      case binaryNotFound(String)
      case hookInstallationFailed(String)
      case socketBindFailed(path: String, errno: Int32)
      case permissionDenied(String)
      case httpServerUnreachable(host: String, port: Int)  // OpenCode
      case jsonRPCHandshakeFailed(String)  // Codex
  }
  ```

  This is a closed domain — all startup failure modes are known. Callers can exhaustively match without a generic `catch`.

- [x] **`ClaudeEventNormalizer.normalize()`** → `throws(EventNormalizationError)`:

  ```swift
  package enum EventNormalizationError: Error, Sendable {
      case unknownEventType(String)
      case malformedPayload(field: String)
      case missingRequiredField(String)
  }
  ```

- [x] **`ClaudeHookInstaller.install()`** → `throws(HookInstallError)`:

  ```swift
  package enum HookInstallError: Error, Sendable {
      case pythonNotFound
      case settingsFileCorrupted(path: String)
      case writePermissionDenied(path: String)
      case hookAlreadyInstalled
  }
  ```

**Rule**: default to plain `throws` for most functions. Use typed throws only where the error domain is closed and exhaustive `catch` handling adds real value — primarily at module boundaries and in provider startup/installation flows.

**Typed throws completeness note**: `throws(Never)` is equivalent to non-throwing. When using generic typed throws (`throws(E)`) in higher-order functions, passing a non-throwing closure infers `E = Never`, making the outer function non-throwing. This subsumes `rethrows` — prefer `throws(E)` generics over `rethrows` for new higher-order functions.

### 1.6 Provider Registry

```
OIProviders/ProviderRegistry.swift
```

- [x] `ProviderRegistry` — actor that:
  - [x] Holds registered `[ProviderID: any ProviderAdapter]` — `any` is correct here for runtime heterogeneity across provider types
  - [x] Starts/stops all adapters
  - [x] Merges all provider event streams into a single `AsyncStream<ProviderEvent>`
  - [x] Provides lookup by ID
- [x] Use `withTaskGroup` to start all adapters concurrently
- [x] Use **`withThrowingDiscardingTaskGroup`** (SE-0381) to merge event streams — this is a long-running event loop that runs for the app's lifetime and doesn't collect results. `withDiscardingTaskGroup` prevents memory leaks from accumulated child task results:

  ```swift
  func mergedEvents() -> AsyncStream<ProviderEvent> {
      // .bufferingOldest: provider events are ordered (session start precedes tool events, etc.)
      // — dropping oldest events silently causes incorrect state reconstruction (see Phase 3.1)
      let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
          bufferingPolicy: .bufferingOldest(128)
      )
      let task = Task {
          try await withThrowingDiscardingTaskGroup { group in
              for adapter in adapters.values {
                  group.addTask {
                      for await event in adapter.events() {
                          continuation.yield(event)
                      }
                  }
              }
          }
          continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
      return stream
  }
  ```

- [x] Always set `onTermination` on the merged stream's continuation to cancel child tasks on consumer disconnect

**`any` vs `some` guidance for provider references**: The registry stores `any ProviderAdapter` because it holds a heterogeneous collection of different concrete adapter types. However, within provider-specific code (e.g., inside `ClaudeProviderAdapter`), always use concrete types or `some ProviderAdapter` — reserve `any` for the registry's heterogeneous collection. Start concrete → move to `some` → resort to `any` only when necessary.

### 1.7 Write Core Model Tests

- [x] Test `SessionPhase` transitions: valid, invalid, terminal state, same-state no-op
- [x] Test `JSONValue` encoding/decoding round-trips
- [x] Test `PermissionContext.displaySummary` for various tool inputs
- [x] Test `ChatHistoryItem` construction and deduplication
- [x] Test `TokenUsageSnapshot` aggregation
- [x] Use parameterized tests (`@Test(arguments:)`) for transition matrix

---

## Phase 2 — State Management Layer

### 2.1 SessionStore Actor

```
OIState/SessionStore.swift
```

- [x] Swift `actor` — the single source of truth for all session state
- [x] Single entry point: `func process(_ event: sending SessionEvent) async` — the `sending` annotation (SE-0430) documents at the type level that the event's ownership is transferred into the actor's isolation domain. This is the canonical boundary where events cross from provider actors into the `SessionStore` actor. Even though `SessionEvent` is currently `Sendable`, `sending` makes the ownership transfer explicit and future-proofs for potential non-Sendable provider extension payloads.
- [x] Internal state: `private var sessions: [String: SessionState]`
- [x] Event audit trail: circular buffer array of last 100 events for debugging, using a simple index-wrapping array implementation. **Do not use `InlineArray<100, SessionEvent>`** — `InlineArray` (SE-0452) requires its element type to be stack-allocatable for real benefit, and `SessionEvent` carries `String`s, `Array`s, and nested structs that are heap-allocated. Reserve `InlineArray` for genuinely fixed-size, trivially-copyable element buffers (e.g., small `ProviderID` lookup tables).
- [x] On each state change, call `publishState()` to broadcast to all subscribers
- [x] Session state snapshots use standard CoW types. Broadcasting to multiple subscribers creates shared references without copying storage until mutation — efficient by design.

### 2.2 Multi-Subscriber Broadcast

```
OIState/SessionStore+Streaming.swift
```

- [x] UUID-keyed `AsyncStream` continuations pattern (from claude-island):

  ```swift
  private var continuations: [UUID: AsyncStream<[SessionState]>.Continuation]
  ```

- [x] `func sessionsStream() -> AsyncStream<[SessionState]>` — registers a new subscriber, immediately yields current state
- [x] `.bufferingNewest(1)` policy — correct for "latest snapshot" semantics where consumers only need the most recent state
- [x] `onTermination` set synchronously before the registration Task to avoid race conditions — **always set `onTermination`** on all `AsyncStream` continuations to clean up the UUID entry from the `continuations` dictionary, preventing memory leaks from accumulated dead continuations
- [x] `publishState()` iterates all continuations, yields sorted sessions

### 2.3 Session Phase Validation & Transitions

```
OIState/SessionStore+Transitions.swift
```

- [x] Map `ProviderEvent` to `SessionPhase` transitions
- [x] Validate via `canTransition(to:)` before applying
- [x] Log invalid transitions with the audit trail
- [x] Handle edge cases: permission during processing, compacting during any state, ended from any state

### 2.4 Tool Tracking

```
OIState/ToolTracker.swift
OIState/ToolEventProcessor.swift
```

- [x] `ToolTracker` struct: `inProgress: [String: ToolInProgress]`, `seenIDs: Set<String>`
- [x] `ToolEventProcessor` — static methods processing tool start/complete events
- [x] Track tool durations, statuses, nested subagent tools
- [x] Subagent state machine: active tasks stack, attribute nested tools to parent Task
- [ ] Handle provider-specific tool type names: Claude uses `Bash`, `Write`, `Edit`, `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`, `Task`, and MCP tools; Codex uses `commandExecution`, `fileChange`, `mcpToolCall`, `webSearch`, `collabToolCall`; Gemini uses standard tool names prefixed with server alias for MCP (`mcp_<serverAlias>_<toolName>`); OpenCode uses its own tool identifiers

### 2.5 Periodic Health Check

```
OIState/SessionStore+HealthCheck.swift
```

- [x] Every 3 seconds, iterate sessions and call provider adapter's `isSessionAlive()`
- [x] Transition zombie sessions to `.ended`
- [x] Use a **regular `Task`** (not `Task.detached`) launched from within the `SessionStore` actor — it inherits the actor's isolation, which is exactly what we want for iterating sessions:

  ```swift
  func startHealthCheck() {
      healthCheckTask = Task {
          while !Task.isCancelled {
              try? await Task.sleep(for: .seconds(3))
              guard !Task.isCancelled else { break }
              await checkZombieSessions()
          }
      }
  }
  ```

  Per the guidelines: "Use `Task.detached` only when you must shed all inherited context." The health check needs actor isolation to read sessions — `Task.detached` would be incorrect.
- [x] Store the `Task` handle for cancellation support on `stop()`

### 2.6 SessionStore Tests

- [x] Test event processing for each `SessionEvent` case
- [x] Test multi-subscriber broadcast: 2+ consumers see same state
- [x] Test zombie session cleanup
- [x] Test audit trail ring buffer behavior
- [x] Test concurrent event processing (use `withTaskGroup` to fire events simultaneously)
- [x] Use `confirmation` from Swift Testing for async event verification

---

## Phase 3 — Claude Code Provider Adapter

> Build the first concrete provider to validate the architecture end-to-end.

### 3.0 Claude Code Integration Architecture

Claude Code's monitoring architecture centers on **shell/Python hook scripts** registered in `settings.json` that receive JSON on stdin and return JSON on stdout. The system supports **17 registered hook event types** organized across four categories (PreToolUse is excluded from registration due to [upstream bug #15897](https://github.com/anthropics/claude-code/issues/15897) but still handled by the normalizer for backward compatibility):

**Session lifecycle events**: `Setup` (fires on `claude --init`), `SessionStart` (startup, resume, clear, compact), `SessionEnd` (exit, logout, prompt exit)

**Agentic loop events**: `UserPromptSubmit`, ~~`PreToolUse`~~ *(not registered — bug #15897)*, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest` (v2.0.45+), `Stop`, `Notification`

**Team/subagent events**: `SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCompleted`

**Maintenance events**: `PreCompact`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`

Four handler types are available: `command` (shell scripts), `http` (POST to endpoints), `prompt` (single-turn LLM evaluation), and `agent` (multi-turn subagent with tool access). Lifecycle and maintenance events support only `command`; agentic loop events support all four. This project uses `command` handlers exclusively — they are the most reliable and lowest-latency for the notch overlay use case.

**Configuration priority** (highest to lowest): `.claude/settings.local.json` (project-level, gitignored), `.claude/settings.json` (project-level, committable), `~/.claude/settings.json` (user-level).

**Conversation logs** are stored as JSONL at `~/.claude/projects/<project-name>/<session-uuid>.jsonl`, with a sessions index at `sessions-index.json` containing summaries, message counts, git branches, and timestamps. Transcripts persist for approximately **30 days**.

**Key environment variables** available to hooks: `$CLAUDE_PROJECT_DIR`, `$CLAUDE_TRANSCRIPT_PATH`, `$CLAUDE_TOOL_INPUT_FILE_PATH`, `$CLAUDE_ENV_FILE` (for persisting vars during SessionStart).

**Hook execution constraints**: hooks are **snapshot-loaded at session start** — edits during a session take effect only after restart. Default command hook timeout is **600 seconds** (increased from 60s in v2.1.3), while SessionEnd hooks are capped at **1.5 seconds**. Exit code semantics: **exit 0** means success (stdout parsed as JSON), **exit 2** means blocking error (blocks tool execution), other codes are non-blocking warnings.

**Reference implementation**: Claude Island (github.com/farouqaldori/claude-island, 914 stars, Swift 95.7%) demonstrates the proven pattern: hook scripts installed in `~/.claude/hooks/` read JSON from stdin, forward events over a Unix domain socket, and for `PermissionRequest` hooks, wait for an approve/deny response from the Swift app before outputting the decision to stdout.

### 3.1 Hook Socket Server

```
OIProviders/Claude/ClaudeHookSocketServer.swift
```

- [x] Port `HookSocketServer` from claude-island
- [x] GCD-based Unix domain socket server at `/tmp/open-island-claude.sock`
- [x] Non-blocking accept via `DispatchSource.makeReadSource`
- [x] **`@preconcurrency import Dispatch`** at the top of this file — GCD types predate Swift concurrency and will trigger Sendable diagnostics in strict mode. Add a comment: `// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations`
- [x] `Mutex<PermissionsState>` for permission tracking (Sendable-safe)
- [x] Permission socket lifecycle: keep client socket open for `PermissionRequest`, 5-minute timeout
- [x] Emit raw `ClaudeHookEvent` structs to a callback
- [x] **Always set `onTermination`** on any `AsyncStream` continuations used to bridge GCD callbacks → async streams, to ensure socket cleanup on consumer disconnect
- [x] **Buffering policy**: use `.bufferingOldest(128)` for the event stream from the socket — events are sequential and order-matters, so dropping the oldest events silently would cause incorrect state reconstruction. `.bufferingOldest` with a generous capacity preserves event ordering under load while bounded memory. Log a warning if the buffer fills (indicates consumer is too slow).

#### `~Copyable` socket file descriptor wrapper

The Unix domain socket file descriptor (`Int32`) held by the socket server is a unique resource that must be closed exactly once. Wrap it in a `~Copyable` struct to make double-close or use-after-close a **compile-time error**:

```swift
struct SocketFD: ~Copyable {
    private let fd: Int32

    init(_ fd: Int32) { self.fd = fd }

    borrowing func read(into buffer: UnsafeMutableRawBufferPointer) -> Int {
        Darwin.read(fd, buffer.baseAddress!, buffer.count)
    }

    borrowing func write(_ data: UnsafeRawBufferPointer) -> Int {
        Darwin.write(fd, data.baseAddress!, data.count)
    }

    consuming func close() {
        Darwin.close(fd)
        discard self  // suppress deinit — cleanup done explicitly
    }

    deinit {
        Darwin.close(fd)
    }
}
```

Use `consuming` methods for operations that terminate the socket (e.g., responding to a permission request and closing the held-open connection). Use `borrowing` for read/write operations that don't transfer ownership. This validates the project's `~Copyable` toolchain and lint pipeline early, before the architecture solidifies.

**Pointer lifetime safety**: All `UnsafeBufferPointer` / `UnsafeMutableRawBufferPointer` usage must follow pointer lifetime rules: valid only within `withUnsafe*` closure scope. Never store, return, or escape. Document at each call site.

**Forward reference — `~Escapable` and `Span<T>`**: `~Escapable` types (SE-0446) and `@lifetime` annotations are experimental in Swift 6.2. Evaluate `Span<T>` as replacement for `UnsafeBufferPointer` in `SocketFD`'s read/write paths once `@lifetime` stabilizes. Do not adopt in initial implementation.

Similarly, the permission socket's held-open client connection (5-minute timeout lifecycle) should be wrapped in a `~Copyable` type — transferring ownership via `consuming` enforces that the connection can't be used after the response is sent.

### 3.2 Claude Hook Event Parsing

```
OIProviders/Claude/ClaudeHookEvent.swift
OIProviders/Claude/ClaudeEventNormalizer.swift
```

- [x] `ClaudeHookEvent` — raw struct matching the hook script's JSON payload:
  - [x] Common fields (all events): `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`
  - [x] `PreToolUse` fields: `tool_name`, `tool_input` (with tool-specific schemas for Bash, Write, Edit, Read, Glob, Grep, WebFetch, WebSearch, Task, and MCP tools), `tool_use_id`
  - [x] `PermissionRequest` fields: same as `PreToolUse` plus decision response schema
  - [x] `PostToolUse`/`PostToolUseFailure` fields: tool result, error info
  - [x] `SessionStart` fields: session type (startup, resume, clear, compact)
  - [x] `SubagentStart`/`SubagentStop` fields: task ID, parent context
  - [x] `PreCompact` fields: compaction reason, message count
  - [x] `Notification` fields: notification type, message content
- [x] `ClaudeEventNormalizer` — maps `ClaudeHookEvent` → `ProviderEvent`
  - [x] Uses `throws(EventNormalizationError)` for closed error domain (see Phase 1.5)
  - [x] Maps all 18 hook event types (including unregistered PreToolUse) to the appropriate `ProviderEvent` cases
  - [x] Handles `PreToolUse` tool input schema variations per tool type
  - [x] Extracts permission context from `PermissionRequest` events
- [x] Handle all Claude-specific event types: `Setup`, `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse` *(not registered but handled for backward compat)*, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`, `Notification`, `SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCompleted`, `PreCompact`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`

### 3.3 Python Hook Script

```
Resources/Hooks/Claude/open-island-claude-hook.py
```

- [x] Port `claude-island-state.py` with updated socket path (`/tmp/open-island-claude.sock`)
- [x] Keep the same protocol: JSON over Unix socket, blocking for permission responses
- [x] Update the hook event names to match `open-island` naming
- [x] Output `{}` (empty JSON) to stdout on all non-permission exit paths — prevents parallel hook interference when Claude Code merges stdout from multiple hooks (e.g., RTK's `rtk-rewrite.sh`)
- [x] Handle `PermissionRequest` hooks specially: read JSON from stdin, forward to socket, **block waiting** for approve/deny response from the Swift app, then output the decision JSON to stdout:
  - [x] Allow response: `{"decision": {"behavior": "allow"}}`
  - [x] Deny response: `{"decision": {"behavior": "deny", "message": "reason", "interrupt": true}}`
- [x] `PreToolUse` hooks can optionally set `permissionDecision` to `"allow"`, `"deny"`, or `"ask"` in `hookSpecificOutput` for policy-based auto-approval — **Note**: PreToolUse is not currently registered due to [upstream bug #15897](https://github.com/anthropics/claude-code/issues/15897); re-enable when the bug is fixed

### 3.4 Hook Installer

```
OIProviders/Claude/ClaudeHookInstaller.swift
```

- [x] Port `HookInstaller` logic:
  - [x] Copy bundled Python script to `~/.claude/hooks/`
  - [x] Detect Python runtime via `PythonRuntimeDetector`
  - [x] Update `~/.claude/settings.json` with hook config for all 17 registered event types (PreToolUse excluded — bug #15897)
  - [x] Register hooks for all four categories: session lifecycle (`SessionStart`, `SessionEnd`), agentic loop (`UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`, `Notification`), team (`SubagentStart`, `SubagentStop`, `TeammateIdle`, `TaskCompleted`), maintenance (`PreCompact`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove`)
  - [x] Clean up stale PreToolUse entries from previous installations during `install()`
  - [x] Use `command` handler type for all events (the only type that supports lifecycle/maintenance events, and the most appropriate for the notch overlay use case)
- [x] Handle deduplication, legacy format migration, uninstallation
- [x] Make this async with cancellation support
- [x] Uses `throws(HookInstallError)` for closed error domain (see Phase 1.5)
- [x] Note: hooks are snapshot-loaded at Claude Code session start — installing hooks while a Claude session is running requires the user to restart their session. Display a notification if hooks are installed/updated while active Claude sessions are detected.

### 3.5 Claude Conversation Parser

```
OIProviders/Claude/ClaudeConversationParser.swift
```

- [x] Actor that reads Claude Code's JSONL conversation files incrementally
- [x] **Session log location**: `~/.claude/projects/<project-name>/<session-uuid>.jsonl`
- [x] **Sessions index**: `~/.claude/projects/<project-name>/sessions-index.json` — contains summaries, message counts, git branches, timestamps; useful for populating session list on app launch
- [x] Track `lastFileOffset` per session, detect file truncation
- [x] Parse user messages, assistant messages (text, tool_use, thinking blocks), tool results
- [x] Handle `/clear` detection (resets session state)
- [x] Emit parsed `[ChatHistoryItem]` via `ProviderEvent.chatUpdated`
- [x] Large file handling: tail-based parsing for files > 10MB
- [x] The `transcript_path` field from every hook event provides the absolute path to the active session's JSONL file — use this for direct file tailing rather than directory scanning
- [x] The file handle used for incremental reading is another candidate for a `~Copyable` wrapper (see Phase 3.1 pattern) — evaluate whether the ownership model adds value here or if the actor's isolation is sufficient

### 3.6 Claude Provider Adapter (Composition)

```
OIProviders/Claude/ClaudeProviderAdapter.swift
```

- [x] Actor conforming to `ProviderAdapter`
- [x] `transportType: .hookSocket`
- [x] Composes: `ClaudeHookSocketServer` + `ClaudeHookInstaller` + `ClaudeConversationParser`
- [x] `start()`: install hooks, start socket server, begin file watching. Uses `throws(ProviderStartupError)`.
- [x] `stop()`: stop socket server, cancel file watchers
- [x] `events()`: merge socket events + file change events into single `AsyncStream<ProviderEvent>` — **always set `onTermination`** on the merged stream's continuation to cancel internal tasks and close the socket listener when consumers disconnect. Use `.bufferingOldest(128)` to preserve event ordering (same rationale as Phase 3.1).
- [x] `respondToPermission()`: delegate to socket server's held-open connection. The connection is kept alive for up to 5 minutes waiting for the user's decision. Write the approval/denial JSON and close the connection.
- [x] `isSessionAlive()`: check PID via `kill(pid, 0)`

### 3.7 Integration Test: Claude Adapter End-to-End

- [x] Mock socket client sending Claude hook events (all 18 event types)
- [x] Verify `ProviderEvent` stream emits correct normalized events
- [x] Test permission flow: request → response → socket write
- [x] Test conversation parsing with sample JSONL fixtures from `~/.claude/projects/` format
- [x] Test hook installer: verify settings.json is correctly updated with all event hooks
- [x] Test session lifecycle: start → process → tool use → permission → approval → stop → end

---

## Phase 4 — Window System & Notch Geometry

### 4.1 NotchPanel (NSPanel Subclass)

```
OIUI/Window/NotchPanel.swift
```

- [x] Borderless, non-activating, transparent floating panel
- [x] Configuration: `.nonactivatingPanel`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`
- [x] `canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`
- [x] Level set above menu bar
- [x] `becomesKeyOnlyIfNeeded = true`
- [x] If the `OIAppKitBridge` module from Phase 0.7 is feasible, this class lives there with `@preconcurrency import AppKit` confined to that module. Otherwise, use **`@preconcurrency import AppKit`** on this file with a comment: `// @preconcurrency: NSPanel, NSWindow predate Sendable annotations`
- [x] **Click-through re-posting**: override `sendEvent(_:)` on `NotchPanel` to detect clicks that fall outside the content area (content view's hit test returns `nil`). When detected:
  - [x] Temporarily set `ignoresMouseEvents = true`
  - [x] Re-post the click as a `CGEvent` at the correct screen coordinates
  - [x] Convert from AppKit's bottom-up coordinate system to CoreGraphics' top-down system
  - [x] Without this mechanism, clicks on the menu bar or another app's window while the notch is expanded are silently swallowed

### 4.2 PassThroughHostingView

```
OIUI/Window/PassThroughHostingView.swift
```

- [x] `NSHostingView` subclass overriding `hitTest(_:)`
- [x] Closed state: returns `nil` for all points (pass-through to menu bar)
- [x] Opened state: delegates to `NSHostingView` hit testing; `NotchPanel.sendEvent` handles pass-through for points with no SwiftUI content
- [x] Dynamic hit rect computed from `NotchViewModel.status` *(depends on Phase 5)*

### 4.3 NotchWindowController

```
OIUI/Window/NotchWindowController.swift
```

- [x] `NSWindowController` managing panel lifecycle
- [x] Subscribe to `NotchViewModel.makeStatusStream()` to toggle `ignoresMouseEvents` *(depends on Phase 5)*
- [x] **Conditional focus activation per open reason**: the window controller must differentiate between user-initiated opens (`.click`, `.hover`) and programmatic opens (`.notification`, `.boot`):
  - [x] **User-initiated** (click, hover): activate the app (`NSApp.activate`), make the panel key — the user intends to interact
  - [x] **Programmatic** (notification, boot): skip activation, leave user's focus undisturbed — the notch appears as an unobtrusive overlay
  - [x] Add test coverage for both paths: verify `NSApp.isActive` state and panel key status after each open reason
- [x] **Boot animation**: orchestrate a brief open-then-close sequence on first launch (0.3s delay to open, hold 1.0s, then close). This teaches the user where the notch is. Trigger via `notchOpen(reason: .boot)` / `notchClose()` on the view model — the controller owns the timing, the view layer handles the animation.

### 4.4 NotchGeometry

```
OIWindow/NotchGeometry.swift
```

- [x] Pure `Sendable` struct with geometry calculations (pure value type with no mutable state):
  - [x] `deviceNotchRect` — hardware notch rect in window coordinates
  - [x] `screenRect`, `windowHeight` (fixed 750px)
  - [x] `isPointInNotch(_:)` with ±10px/±5px padding
  - [x] `isPointInsidePanel(_:, size:)` for hit-test acceptance in the opened state
  - [x] `isPointOutsidePanel(_:, size:)` for click-outside dismiss
  - [x] `notchRectInScreenCoordinates` and `panelRectInScreenCoordinates(size:)` for global mouse-position hit testing — must account for screen origin differences between built-in and external monitors
- [x] `NSScreen` extensions: `notchSize`, `hasPhysicalNotch`, `isBuiltinDisplay`, `builtin`

### 4.5 NotchShape (Custom SwiftUI Shape)

```
OIWindow/NotchShape.swift
```

- [x] Quadratic Bézier curve path drawing the notch outline
- [x] Animatable `topCornerRadius` and `bottomCornerRadius` via `AnimatablePair`
- [x] Closed radii: top 6, bottom 14
- [x] Opened radii: top 19, bottom 24

### 4.6 WindowManager & ScreenObserver

```
OIUI/Window/WindowManager.swift
OIUI/Window/ScreenObserver.swift
```

- [x] `WindowManager`: creates `NotchWindowController` attached to selected screen
- [x] `ScreenObserver`: monitors `didChangeScreenParametersNotification` with 500ms debounce
- [x] `ScreenSelector`: automatic (built-in display) or user-selected screen, persisted as `ScreenIdentifier`

### 4.7 Window System Tests

- [x] Test `NotchGeometry` hit testing with known coordinates
- [x] Test `NotchShape` path generation (snapshot or bounds checking)
- [x] Test screen selector fallback logic

---

## Phase 5 — NotchViewModel & Core UI

### 5.1 NotchViewModel

```
OIUI/ViewModels/NotchViewModel.swift
```

- [x] `@Observable` class managing:
  - [x] `status: NotchStatus` (`.closed`, `.opened`, `.popping`)
  - [x] `contentType: NotchContentType` (`.instances`, `.chat(SessionState)`, `.menu`)
  - [x] `openReason: NotchOpenReason` (`.click`, `.hover`, `.notification`, `.boot`)
  - [x] `geometry: NotchGeometry`
  - [ ] `layoutEngine: ModuleLayoutEngine`
- [x] Computed `openedSize` varying by content type. Each content type computes its own preferred size. For the settings menu, each expandable picker row contributes its expansion height to the total panel height — the panel grows and shrinks as the user opens and closes selectors. Track a `selectorUpdateToken` (or similar mechanism) that triggers view re-computation when any selector's expansion state changes. Without this, the settings panel either clips content or has permanent empty space.
- [x] `makeStatusStream() -> AsyncStream<NotchStatus>` — factory method for window controller subscription. Single-consumer by convention: calling the factory again finishes the previous stream to prevent leaks. Uses `.bufferingNewest(1)`.
- [x] Methods: `notchOpen(reason:)`, `notchClose()`, `switchContent(_:)`
- [x] **State preservation across open/close cycles**: remember the current `contentType` (including which session's chat was displayed) when closing. Restore on next open so the user returns to where they left off.

### 5.2 Event Monitors

```
OIUI/Events/EventMonitor.swift
OIUI/Events/EventMonitors.swift
```

- [x] `NSEvent` global monitor wrapper
- [x] Mouse position tracking for hover detection
- [x] Mouse movement monitor throttled to ~50ms intervals to avoid flooding the event system with position updates
- [x] Mouse drag tracking (for drag interactions within the opened panel)
- [x] Click-outside detection for dismissal
- [x] Keyboard shortcut handling

### 5.3 NotchView (Root SwiftUI View)

```
OIUI/Views/NotchView.swift
```

- [x] Root `ZStack` with `NotchShape` clip mask and shadow
- [x] Header row (always visible): left modules + notch spacer + right modules
- [x] Content view (when opened): switches on `contentType`
- [x] Reactive states: `isVisible`, `isHovering`, `isBouncing`
- [x] Animations:
  - [x] Open: `.spring(response: 0.42, dampingFraction: 0.8)`
  - [x] Close: `.spring(response: 0.45, dampingFraction: 1.0)`
  - [x] **Asymmetric content transitions**: insertion uses `.scale(anchor: .top).combined(with: .opacity)` (expansive entry); removal uses a fast `.opacity` fade (snappy exit)
  - [x] **Layered animation strategy**: use distinct animation curves for different visual properties:
    - [x] Spring for container size changes (width/height between content types)
    - [x] Smooth for activity-state changes
    - [x] Separate spring for bounce/pop animations
    - [x] This creates a polished feel where different elements move at different rates
- [x] Include `#Preview` blocks in every SwiftUI view file. Create preview helpers providing mock `SessionState`, `NotchViewModel`, and `ModuleRenderContext` for self-contained previews. `#Preview` replaces the legacy `PreviewProvider` protocol.

### 5.4 NotchHeaderView

```
OIUI/Views/NotchHeaderView.swift
```

- [x] **Height adaptation**: in the closed state, the header row height matches the physical notch height. In the opened state, it expands to a fixed comfortable height for interactive elements (buttons, text).
- [x] **Closed state**: shows the full module layout — left modules + notch spacer + right modules (from `ModuleLayoutEngine`)
- [x] **Opened state**: shows only modules with `showInExpandedHeader = true`, plus:
  - [x] Menu toggle button (gear icon → settings)
  - [x] Context-dependent navigation: back button (when in sub-view like chat detail) or close button (chevron)
  - [x] Mascot icon (provider-aware — show relevant icon based on active sessions)
  - [x] Activity spinner with `matchedGeometryEffect` between closed/opened states
  - [x] Title text adapting to content type

### 5.5 Basic Instances View (Placeholder)

```
OIUI/Views/InstancesView.swift
```

- [x] List of active sessions from `SessionMonitor`
- [x] Each row shows: provider icon, project name, phase indicator, elapsed time
- [x] Tap to open chat view for that session
- [x] Empty state when no sessions active

### 5.6 SessionMonitor (UI Bridge)

```
OIUI/ViewModels/SessionMonitor.swift
```

- [x] `@Observable` class on MainActor
- [x] Subscribes to `SessionStore.sessionsStream()`
- [x] Updates `instances: [SessionState]` array (filters out ended sessions)
- [x] Convenience methods: `approvePermission()`, `denyPermission()`, `archiveSession()`
- [x] Bridges provider registry for permission responses

---

## Phase 6 — Closed-State Module System

### 6.1 NotchModule Protocol

```
OIModules/NotchModule.swift
```

- [ ] Protocol with associated `ID == String`:
  - [ ] `defaultSide: ModuleSide` (`.left`, `.right`)
  - [ ] `defaultOrder: Int`
  - [ ] `showInExpandedHeader: Bool`
  - [ ] `func isVisible(context: ModuleVisibilityContext) -> Bool`
  - [ ] `func preferredWidth() -> CGFloat`
  - [ ] `@ViewBuilder func makeBody(context: ModuleRenderContext) -> some View`
- [ ] `ModuleVisibilityContext` — struct with `isProcessing`, `hasPendingPermission`, `hasWaitingForInput`, `activeProviders: Set<ProviderID>`, `aggregateProviderState: [ProviderID: ProviderActivitySummary]` — modules can make provider-aware decisions (e.g., show Codex risk level, show Claude-specific indicators) without coupling to a specific provider's identity
- [ ] `ModuleRenderContext` — struct with animation namespace, color settings, etc.
- [ ] Both `ModuleVisibilityContext` and `ModuleRenderContext` must be `Sendable` value types that the layout engine can construct without reaching into global singletons — this keeps the module system testable in isolation

> **Design note on `makeBody` return type**: The protocol uses `some View` with `@ViewBuilder` rather than `AnyView`. Since modules are stored heterogeneously in the registry, the `ModuleRegistry` uses `any NotchModule` for the collection. When `makeBody` is called through `any NotchModule`, the return type becomes an opaque type opened from an existential — this works in Swift 6 thanks to SE-0352 (implicitly opened existentials), but **only** if the call site can handle the opened type (e.g., inside a `@ViewBuilder` context in `NotchHeaderView`).
>
> **Validate early**: in Phase 6's first implementation pass, confirm that calling `module.makeBody(context:)` on an `any NotchModule` reference compiles within a `@ViewBuilder` closure. If the compiler cannot open the existential in that context (e.g., because `some View` is used as a return type that escapes the immediate scope), fall back to requiring `makeBody` to return `AnyView` on the protocol, with concrete implementations using a helper method that returns `some View` internally. Document the decision and rationale in the protocol's DocC comment.

### 6.2 ModuleLayoutEngine

```
OIModules/ModuleLayoutEngine.swift
```

- [ ] Computes closed-state layout from registered modules
- [ ] Filters visible modules per side
- [ ] Computes symmetric side widths (max of left/right)
- [ ] Total expansion width = `symmetricSideWidth × 2`
- [ ] Inter-module spacing: 8px, outer edge inset: 6px
- [ ] **Hit-test / visual sync contract**: the `PassThroughHostingView` (Phase 4.2) and the SwiftUI `NotchView` (Phase 5.3) must both use `ModuleLayoutEngine` as the single source of truth for closed-state width. Add a documented contract (code comment in both locations pointing to the other) or a shared method that both layers consume, to prevent visual bounds and interaction bounds from drifting apart.

### 6.3 ModuleRegistry

```
OIModules/ModuleRegistry.swift
```

- [ ] `@Observable` singleton holding all registered modules
- [ ] Dynamic registration — providers can add custom modules at runtime
- [ ] Updates session-dependent modules (e.g., session dots) when state changes

### 6.4 Built-in Modules

```
OIModules/BuiltIn/MascotModule.swift          — left, order 0, always visible
OIModules/BuiltIn/PermissionIndicatorModule.swift — left, order 1
OIModules/BuiltIn/ActivitySpinnerModule.swift  — right, order 0
OIModules/BuiltIn/ReadyCheckmarkModule.swift   — right, order 1
OIModules/BuiltIn/SessionDotsModule.swift      — right, order 2
OIModules/BuiltIn/TimerModule.swift            — right, order 3
```

- [ ] `MascotModule` replaces `ClawdModule` — shows provider-appropriate icon (crab for Claude, diamond for Codex, Gemini symbol for Gemini CLI, OpenCode logo for OpenCode), or a generic icon when multi-provider sessions are active
- [ ] Each module is a small struct conforming to `NotchModule`

### 6.5 Module Layout Persistence

```
OIModules/ModuleLayoutConfig.swift
```

- [ ] `Codable` struct persisted to `UserDefaults`
- [ ] Stores per-module: side, order overrides
- [ ] Allows user customization of module arrangement
- [ ] On launch, prune module IDs from the persisted config that no longer exist in the registry (stale modules from uninstalled providers)
- [ ] Add any newly registered modules (from new providers or app updates) at their default positions

### 6.6 Module System Tests

- [ ] Test layout engine with various module visibility combinations
- [ ] Test symmetric width calculation
- [ ] Test config persistence round-trip

### 6.7 Module Layout Settings View

```
OIModules/Views/ModuleLayoutSettingsView.swift
```

- [ ] Three-column drag-and-drop interface: **Left**, **Right**, **Hidden**
- [ ] Each column is a drop destination; modules are draggable between columns
- [ ] Visual feedback: insertion indicators at drop position, highlighted drop zones on hover
- [ ] Empty-state placeholders for columns with no modules
- [ ] Reset-to-defaults button restoring the factory layout
- [ ] Config persistence round-trip: changes immediately saved to `ModuleLayoutConfig` (Phase 6.5) and reflected in the closed-state layout
- [ ] Test: drag module between columns → verify layout config updates → verify closed-state view reflects change

---

## Phase 7 — Chat View & Markdown Rendering

### 7.1 ChatView

```
OIUI/Views/ChatView.swift
```

- [ ] Scrollable chat history for a single session
- [ ] Provider-aware styling (accent colors, icon)
- [ ] Message types: user bubbles, assistant text, tool calls (expandable), thinking (collapsible), reasoning (Codex-specific, collapsible), interrupted markers
- [ ] Auto-scroll to bottom on new messages
- [ ] Approval bar at bottom when session is `.waitingForApproval`

### 7.2 Approval Bar

```
OIUI/Views/ApprovalBarView.swift
```

- [ ] Shows tool name and summary from `PermissionContext.displaySummary`
- [ ] Risk level indicator when available (Codex provides `.low`/`.medium`/`.high` risk with approval requests)
- [ ] Three buttons: Approve, Deny, Always Allow
- [ ] Slide-in animation from bottom
- [ ] Calls `SessionMonitor.approvePermission()` / `denyPermission()`

### 7.3 ToolResultViews

```
OIUI/Views/ToolResultViews.swift
```

- [ ] Expandable tool call cards showing:
  - [ ] Tool name + status icon (spinner, checkmark, X)
  - [ ] Input summary (file path, command, etc.)
  - [ ] Expandable result content (truncated by default)
  - [ ] Duration badge (populated from Codex's `durationMs`, or calculated from tool start/complete timestamps for other providers)
  - [ ] Exit code indicator for command executions (Codex provides `exitCode` natively; Claude infers from Bash tool results)
- [ ] Nested subagent tools displayed indented under parent Task

### 7.4 Markdown Renderer

```
OIUI/Components/MarkdownText.swift
```

- [ ] Uses Apple's `swift-markdown` library (pure Swift package — no OS runtime dependency, back-deploys freely)
- [ ] Document cache (keyed by text hash) to avoid re-parsing
- [ ] Inline renderer: bold, italic, code spans, links, strikethrough
- [ ] Block renderer: paragraphs, headings, code blocks (monospace bg), block quotes, lists, thematic breaks
- [ ] Code blocks with syntax-aware monospace styling

### 7.5 Chat View Tests

- [ ] Test `ChatHistoryItem` rendering for each type
- [ ] Test approval bar visibility tied to session phase
- [ ] Test tool result expansion/collapse

---

## Phase 8 — Additional Provider Adapters

### 8.0 Provider Integration Architecture Overview

All four CLI coding agents expose rich event systems, but each uses a fundamentally different architectural pattern:

| Capability | Claude Code | Codex CLI | Gemini CLI | OpenCode |
|---|---|---|---|---|
| **Primary event source** | Hook scripts (stdin/stdout) | JSON-RPC 2.0 app-server (stdio) | Hook scripts (stdin/stdout) | SSE over HTTP |
| **Event count** | 18 hook types | ~15 item/turn types | 11 hook types | 30+ SSE event types |
| **Permission interception** | PermissionRequest hook → JSON response | Server-initiated JSON-RPC request | BeforeTool hook → deny/allow | REST API POST |
| **Approval latency** | Hook script execution time | Native protocol response | Hook script execution time | HTTP round-trip |
| **Session log format** | JSONL (`~/.claude/projects/`) | JSONL (`~/.codex/sessions/`) | JSON (`~/.gemini/tmp/`) | JSON (`~/.local/share/opencode/`) |
| **Config format** | JSON (`settings.json`) | TOML (`config.toml`) | JSON (`settings.json`) | JSON (`opencode.json`) |
| **OpenTelemetry** | Via settings | Native (OTLP-HTTP/gRPC) | Native (local/GCP/OTLP) | Via plugin (community) |
| **MCP support** | Full (native host) | Full | Full | Full |
| **SDK available** | TypeScript + Python | TypeScript (`@openai/codex-sdk`) | — | TypeScript (`@opencode-ai/sdk`) |
| **Headless JSONL stream** | No | `codex exec --json` | `gemini -p --output-format stream-json` | SSE (`/event`) |
| **Plugin/extension system** | Plugins (hooks.json) | — | Extensions (gemini-extension.json) | Plugins (.ts/.js, npm) |
| **macOS sandbox** | — | Seatbelt (`sandbox-exec`) | Seatbelt profiles | — |

**Key architectural insight**: Claude Code and Gemini CLI share the hook-script-to-socket pattern, meaning a single bridge script template (parameterized by event names and socket paths) can serve both. Codex CLI's app-server is the most powerful interface but requires managing a child process and implementing a JSON-RPC client. OpenCode's HTTP/SSE approach is the most modern and language-agnostic, requiring no hook installation or process spawning.

**Permission interception** — the most time-sensitive feature for a notch overlay — works differently for each tool and must be implemented at the protocol level, not as an afterthought. A production adapter should prioritize approval latency, using async hooks where possible and keeping synchronous hook scripts under 2 seconds.

### 8.1 Codex CLI Provider Adapter

Codex CLI (github.com/openai/codex, 60.2k stars, 95.9% Rust) offers the **richest programmatic integration surface** through its `codex app-server` — a bidirectional JSON-RPC 2.0 server over stdio that provides complete session control, real-time event streaming, and approval interception.

```
OIProviders/Codex/CodexProviderAdapter.swift
OIProviders/Codex/CodexAppServerClient.swift
OIProviders/Codex/CodexEventNormalizer.swift
OIProviders/Codex/CodexJSONRPCProtocol.swift
OIProviders/Codex/CodexSessionRolloutParser.swift
```

#### 8.1.1 JSON-RPC 2.0 App-Server Client

- [ ] **Launch**: spawn `codex app-server` as a child process, communicate via stdio JSONL (reads JSONL from stdin, writes JSONL to stdout)
- [ ] **Handshake**: `initialize` request → wait for `initialized` response before sending any other messages
- [ ] **Schema generation**: run `codex app-server generate-json-schema --out ./schemas` at build time to produce version-matched type definitions; use these to validate `CodexJSONRPCProtocol` types
- [ ] **Available methods** (client → server):
  - [ ] `thread/start` — create new conversation thread
  - [ ] `thread/resume` — resume existing thread
  - [ ] `thread/list` — list all threads
  - [ ] `turn/start` — send user message
  - [ ] `turn/interrupt` — cancel current turn
  - [ ] `config/read` — read current configuration
  - [ ] `model/list` — list available models
- [ ] **Event notifications** (server → client, streamed on stdout):
  - [ ] Turn lifecycle: `turn/started`, `turn/completed` (with status: `completed`, `interrupted`, or `failed`; includes token usage), `turn/diff/updated` (aggregated unified diffs), `turn/plan/updated`
  - [ ] Item types form a **tagged union** (`ThreadItem`): `userMessage`, `agentMessage`, `reasoning`, `commandExecution` (with `command`, `cwd`, `status`, `exitCode`, `durationMs`), `fileChange` (with `path`, `kind`, `diff` per change), `mcpToolCall` (server, tool, arguments, result), `webSearch`, `imageView`, `enteredReviewMode`, `compacted`, `collabToolCall`
  - [ ] Each item fires `item/started` and `item/completed` events
  - [ ] **Streaming deltas**: `item/agentMessage/delta`, `item/reasoning/summaryTextDelta`, `item/commandExecution/outputDelta`
- [ ] **Approval interception** (first-class, no hooks needed):
  - [ ] Server sends **server-initiated JSON-RPC request** to client: `item/commandExecution/requestApproval` (with `itemId`, `reason`, `risk`, `parsedCmd`) or `item/fileChange/requestApproval` (with `grantRoot` info)
  - [ ] Client responds with `{"decision": "accept"}` or `{"decision": "decline"}`
  - [ ] This makes Codex the only tool where approval interception requires no hook installation — it's native to the protocol
- [ ] Implement `CodexAppServerClient` as an actor managing the child process lifecycle, JSON-RPC message routing, and request/response correlation

#### 8.1.2 Additional Monitoring Surfaces

- [ ] **`codex exec --json`**: outputs a JSONL event stream on stdout (`thread.started`, `turn.started`, `item.started`, `item.completed`, `turn.completed` with token usage). Useful as a lightweight alternative to the full app-server for read-only monitoring.
- [ ] **`notify` config hook**: configured in `~/.codex/config.toml`, spawns an external command on `agent-turn-complete` events, passing a JSON payload with `thread-id`, `turn-id`, `last-assistant-message`, and `input-messages`. Can be used as a fallback notification mechanism.
- [ ] **Session rollout files**: `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl` — complete conversation history in JSONL format, can be tailed with FSEvents for chat history reconstruction

#### 8.1.3 Configuration & Environment

- [ ] **Config format**: TOML at `~/.codex/config.toml` (user-level), `.codex/config.toml` (project-level)
- [ ] **Directory structure** under `~/.codex/`: `auth.json`, `history.jsonl`, `AGENTS.md`, `rules/`, `skills/`, `log/codex-tui.log`, `sessions/` tree
- [ ] **Sandbox model**: macOS Seatbelt (`sandbox-exec`) with three modes: `read-only`, `workspace-write` (writes confined to CWD, network disabled by default), `danger-full-access`
- [ ] **Approval policies**: `untrusted` (ask for everything), `on-request` (ask for risky actions), `never` (auto-approve). Runtime changes via `/permissions` slash command or per-turn overrides through app-server.
- [ ] **Native OpenTelemetry** configured in `~/.codex/config.toml`:
  ```toml
  [otel]
  exporter = "otlp-http"
  log_user_prompt = true
  [otel.exporter."otlp-http"]
  endpoint = "https://otel.example.com/v1/logs"
  ```

#### 8.1.4 Event Normalization

- [ ] `CodexEventNormalizer` — maps Codex JSON-RPC events → `ProviderEvent`:
  - [ ] `turn/started` → `.processingStarted`
  - [ ] `turn/completed` → `.waitingForInput` + `.tokenUsage` (extracts token counts)
  - [ ] `item/started` (commandExecution) → `.toolStarted`
  - [ ] `item/completed` (commandExecution) → `.toolCompleted` (with `exitCode`, `durationMs` in `providerSpecific`)
  - [ ] `item/started` (fileChange) → `.toolStarted`
  - [ ] `item/completed` (fileChange) → `.toolCompleted` (with `path`, `kind`, `diff`)
  - [ ] `item/started` (mcpToolCall) → `.toolStarted`
  - [ ] `item/completed` (mcpToolCall) → `.toolCompleted`
  - [ ] `item/commandExecution/requestApproval` → `.permissionRequested` (with `risk` field mapped to `PermissionRisk`)
  - [ ] `item/fileChange/requestApproval` → `.permissionRequested`
  - [ ] `item/agentMessage/delta` → `.modelResponse`
  - [ ] `turn/diff/updated` → `.diffUpdated`
  - [ ] `item/started`/`item/completed` (collabToolCall) → `.subagentStarted`/`.subagentStopped`
  - [ ] `item/completed` (compacted) → `.compacting`

#### 8.1.5 Codex Provider Adapter Composition

- [ ] Actor conforming to `ProviderAdapter`
- [ ] `transportType: .jsonRPC`
- [ ] Composes: `CodexAppServerClient` + `CodexEventNormalizer` + `CodexSessionRolloutParser`
- [ ] `start()`: verify `codex` binary exists on PATH, spawn `codex app-server` process, perform JSON-RPC handshake. Uses `throws(ProviderStartupError)` with `.jsonRPCHandshakeFailed` case.
- [ ] `stop()`: send shutdown signal, terminate child process
- [ ] `events()`: stream events from app-server stdout, normalize to `ProviderEvent`
- [ ] `respondToPermission()`: send JSON-RPC response to the held server-initiated request (no hooks, no sockets — pure protocol)
- [ ] `isSessionAlive()`: check child process status + JSON-RPC ping
- [ ] Register in `ProviderRegistry`

### 8.2 Gemini CLI Provider Adapter

Gemini CLI (github.com/google-gemini/gemini-cli, Apache 2.0, TypeScript/Node.js) implements a hook system architecturally similar to Claude Code — **command hooks that receive JSON on stdin and return JSON on stdout** — but with different event naming, native OpenTelemetry integration, and a headless JSONL streaming mode.

```
OIProviders/GeminiCLI/GeminiCLIProviderAdapter.swift
OIProviders/GeminiCLI/GeminiHookSocketServer.swift
OIProviders/GeminiCLI/GeminiEventNormalizer.swift
OIProviders/GeminiCLI/GeminiHeadlessStreamParser.swift
OIProviders/GeminiCLI/GeminiHookInstaller.swift
OIProviders/GeminiCLI/GeminiConversationParser.swift
```

#### 8.2.1 Hook System (Primary Event Source)

- [ ] **11 hook event types**: `SessionStart`, `SessionEnd`, `BeforeAgent` (after user prompt, before planning), `AfterAgent` (after model's final response), `BeforeModel` (before LLM API call), `AfterModel` (after each LLM response chunk), `BeforeToolSelection`, `BeforeTool` (before tool execution — the key interception point), `AfterTool`, `PreCompress`, `Notification`
- [ ] **Hook input format** — same pattern as Claude Code: base JSON object on stdin with `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`, plus event-specific fields:
  - [ ] `BeforeTool`: adds `tool_name`, `tool_input`, optional `mcp_context`
  - [ ] `AfterTool`: adds `tool_response` with `llmContent`, `returnDisplay`, `error`
  - [ ] `BeforeModel`/`AfterModel`: provides full `llm_request` (model, messages array, config, toolConfig) and `llm_response` (candidates with content and finishReason, usageMetadata with `totalTokenCount`)
  - [ ] `Notification`: with `notification_type: "ToolPermission"` provides observability into permission requests but **cannot grant permissions**
- [ ] **Blocking events** that can halt execution: `BeforeAgent`, `AfterAgent`, `BeforeModel`, `AfterModel`, `BeforeTool`, `AfterTool`
- [ ] **High-frequency warning**: `AfterModel` fires **for every chunk during streaming** — requires throttling/debouncing in the normalizer to avoid flooding the event bus. Only process final chunks or aggregate at configurable intervals.
- [ ] **Environment variables**: `GEMINI_PROJECT_DIR`, `GEMINI_SESSION_ID`, `GEMINI_CWD`. A compatibility alias `CLAUDE_PROJECT_DIR` exists, suggesting deliberate cross-tool portability.

#### 8.2.2 Shared Hook Infrastructure with Claude Code

- [ ] **Reuse `ClaudeHookSocketServer` pattern**: Gemini CLI hooks use the same stdin/stdout JSON protocol as Claude Code. Create a shared `HookSocketBridge` that both providers use, parameterized by:
  - [ ] Socket path (`/tmp/open-island-gemini.sock` vs `/tmp/open-island-claude.sock`)
  - [ ] Event name mapping (Gemini's `BeforeTool` vs Claude's `PreToolUse`)
  - [ ] Permission response format
- [ ] **Hook script template**: a single Python hook script template can serve both Claude and Gemini, with the socket path and event name mappings passed as arguments or environment variables

#### 8.2.3 Permission & Approval

- [ ] **Permission modes**: `default` (prompt for each tool call), `auto_edit` (auto-approve edit tools), `yolo`/`-y` (auto-approve everything), experimental `plan` (read-only)
- [ ] **Fine-grained control**: `tools.safeTools` arrays in config (e.g., `["run_shell_command(git status)"]`)
- [ ] **`BeforeTool` is the interception point**: can deny execution or rewrite arguments before the user sees a confirmation prompt. This is distinct from Claude's `PermissionRequest` hook — Gemini's permission interception happens at the tool level, not as a separate permission event.
- [ ] Note: `Notification` with `notification_type: "ToolPermission"` is observation-only — it cannot grant or deny permissions

#### 8.2.4 Configuration & Session Data

- [ ] **Config file priority** (highest to lowest): system override (`/Library/Application Support/GeminiCli/settings.json`), project (`.gemini/settings.json`), user (`~/.gemini/settings.json`), system defaults
- [ ] **Session data**: `~/.gemini/tmp/<project_hash>/chats/` as JSON files
- [ ] **Checkpointing** (enabled via `{"general": {"checkpointing": true}}`): writes to `~/.gemini/tmp/<project_hash>/checkpoints/` with git snapshots
- [ ] **Chat export**: `/chat share file.json` or `/chat share file.md`

#### 8.2.5 Headless Streaming Mode (Alternative Event Source)

- [ ] `gemini -p "query" --output-format stream-json` outputs JSONL with event types: `init` (session metadata), `message` (text chunks), `tool_use` (tool call requests), `tool_result` (execution output), `error`, `result` (final statistics)
- [ ] This stream can be parsed line-by-line for overlay updates **without hooks** — useful as a fallback or for monitoring non-interactive Gemini sessions
- [ ] Implement `GeminiHeadlessStreamParser` to consume this JSONL stream and emit `ProviderEvent`s

#### 8.2.6 OpenTelemetry & Extensions

- [ ] **Native OpenTelemetry**: supports local file output (`.gemini/telemetry.log`), Google Cloud export, or any OTLP backend:
  ```json
  {"telemetry": {"enabled": true, "target": "local", "otlpEndpoint": "", "outfile": ".gemini/telemetry.log", "logPrompts": true}}
  ```
- [ ] **Extensions system**: bundles hooks, MCP servers, custom commands, and agents into installable packages. MCP tools follow the `mcp_<serverAlias>_<toolName>` naming convention and can be matched in hooks using regex.

#### 8.2.7 Event Normalization

- [ ] `GeminiEventNormalizer` — maps Gemini hook events → `ProviderEvent`:
  - [ ] `SessionStart` → `.sessionStarted`
  - [ ] `SessionEnd` → `.sessionEnded`
  - [ ] `BeforeAgent` → `.userPromptSubmitted` + `.processingStarted`
  - [ ] `AfterAgent` → `.waitingForInput`
  - [ ] `BeforeTool` → `.toolStarted` (also the permission interception point)
  - [ ] `AfterTool` → `.toolCompleted`
  - [ ] `BeforeModel` → `.processingStarted` (model-level)
  - [ ] `AfterModel` → `.modelResponse` (streaming delta) + `.tokenUsage` (from `usageMetadata.totalTokenCount`). **Throttle**: only emit `.modelResponse` for final chunks or at 100ms intervals to avoid flooding.
  - [ ] `PreCompress` → `.compacting`
  - [ ] `Notification` (ToolPermission) → `.permissionRequested` (observation-only — the overlay can display it but cannot grant/deny through this event)
  - [ ] MCP tool calls: identified by `mcp_<serverAlias>_<toolName>` naming convention in `tool_name` field

#### 8.2.8 Gemini Provider Adapter Composition

- [ ] Actor conforming to `ProviderAdapter`
- [ ] `transportType: .hookSocket`
- [ ] Composes: `GeminiHookSocketServer` (shared infrastructure with Claude) + `GeminiHookInstaller` + `GeminiConversationParser` + optional `GeminiHeadlessStreamParser`
- [ ] `start()`: install hooks into `~/.gemini/settings.json`, start socket server. Uses `throws(ProviderStartupError)`.
- [ ] `stop()`: stop socket server, cancel file watchers
- [ ] `events()`: merge socket events + conversation file changes. Use `.bufferingOldest(128)`.
- [ ] `respondToPermission()`: delegate to `BeforeTool` hook's held connection (returns deny/allow via stdout JSON). **Limitation**: Gemini's permission model is less granular than Claude's — `Notification` events are observation-only and cannot be used for permission decisions.
- [ ] `isSessionAlive()`: check PID via `kill(pid, 0)`
- [ ] Register in `ProviderRegistry`

### 8.3 OpenCode Provider Adapter

OpenCode (github.com/anomalyco/opencode, formerly sst/opencode, 120k+ stars, MIT) takes a radically different approach: it runs a **Bun HTTP server** (Hono framework) alongside a Go TUI, exposing a full REST API with SSE event streams — making it the most straightforward to integrate with from any language, including Swift.

```
OIProviders/OpenCode/OpenCodeProviderAdapter.swift
OIProviders/OpenCode/OpenCodeSSEClient.swift
OIProviders/OpenCode/OpenCodeRESTClient.swift
OIProviders/OpenCode/OpenCodeEventNormalizer.swift
OIProviders/OpenCode/OpenCodeServerDiscovery.swift
```

#### 8.3.1 SSE Event Stream (Primary Event Source)

- [ ] **Project-scoped endpoint**: `GET /event?directory=/path/to/project`
- [ ] **Cross-project endpoint**: `GET /global/event`
- [ ] **30+ event types** delivered in real-time via Server-Sent Events:
  - [ ] Session lifecycle: `session.created`, `session.updated`, `session.deleted`, `session.status`, `session.idle`, `session.error`, `session.compacted`
  - [ ] Messages: `message.updated`, `message.removed`, `message.part.updated` (with `delta` for incremental text streaming), `message.part.removed`
  - [ ] Tools: `tool.execute.before`, `tool.execute.after`
  - [ ] Permissions: `permission.asked` (with `requestID`, `sessionID`, questions), `permission.replied`
  - [ ] File changes: `file.edited`, `file.watcher.updated`, `session.diff`
  - [ ] Additional: LSP diagnostics, TODO tracking, TUI control events
- [ ] Implement `OpenCodeSSEClient` using `URLSession` with streaming data task, parsing SSE format (`event:`, `data:`, `id:` fields)
- [ ] **No hook scripts or file watchers needed** — pure HTTP communication

#### 8.3.2 REST API (Session Control & Permission Response)

- [ ] **Session management**:
  - [ ] `POST /session` — create session
  - [ ] `POST /session/{id}/prompt` — send message
  - [ ] `POST /session/{id}/abort` — cancel current processing
  - [ ] `GET /session/{id}/message` — list messages (for chat history)
- [ ] **Permission response**: `POST /session/{id}/permissions/{permId}` with decision payload — this is the **sole permission interception mechanism** for OpenCode
- [ ] **Configuration**: `GET /config`, `GET /provider`
- [ ] **OpenAPI spec**: `GET /doc` returns auto-generated OpenAPI 3.1 spec — use this for type generation and validation
- [ ] Implement `OpenCodeRESTClient` as an actor wrapping `URLSession` for all REST calls

#### 8.3.3 Server Discovery

- [ ] **Default**: `opencode serve --port 4096` (headless mode)
- [ ] **mDNS discovery**: `--mdns` flag enables Bonjour-based service discovery — implement `OpenCodeServerDiscovery` using `NWBrowser` (Network framework) to discover running OpenCode instances on the local network
- [ ] **Process argument parsing**: as a fallback, parse `proc_listpids` output to find running `opencode` processes and extract their `--port` arguments
- [ ] **Port configuration**: support user-specified port in settings, with auto-discovery as default

#### 8.3.4 Plugin System (Alternative Integration)

- [ ] OpenCode supports **in-process plugins** — TypeScript/JavaScript files in `.opencode/plugins/` (project) or `~/.config/opencode/plugins/` (global), or npm packages in `opencode.json`
- [ ] Plugin API provides `event` handler for **all** bus events, plus named hooks (`tool.execute.before`, `tool.execute.after`), custom tool registration, auth integration, and SDK client access
- [ ] **Decision**: use SSE + REST as the primary integration path (no plugin installation required). Document the plugin approach in `PROVIDERS.md` as an alternative for power users who want deeper integration.

#### 8.3.5 Configuration & Data Storage

- [ ] **Config files**: `~/.config/opencode/opencode.json` (global), `opencode.json` (project), `tui.json` (TUI settings)
- [ ] **Permission configuration**: per-tool granularity: `{"permission": {"edit": "ask", "bash": "ask", "webfetch": "ask"}}` with values `"ask"`, `"allow"`, or `"deny"`
- [ ] **Data storage**: file-based hierarchical key-value under `~/.local/share/opencode/project/<project-slug>/`. Storage keys: `["session", projectID, sessionID]` for sessions, `["message", sessionID, messageID]` for messages
- [ ] **ACP mode**: `opencode acp` communicates over stdin/stdout with nd-JSON — an alternative to HTTP for embedded integrations (not used by this project)

#### 8.3.6 Event Normalization

- [ ] `OpenCodeEventNormalizer` — maps OpenCode SSE events → `ProviderEvent`:
  - [ ] `session.created` → `.sessionStarted`
  - [ ] `session.deleted` → `.sessionEnded`
  - [ ] `session.status` (processing) → `.processingStarted`
  - [ ] `session.idle` → `.waitingForInput`
  - [ ] `session.compacted` → `.compacting`
  - [ ] `session.error` → `.notification` (with error message)
  - [ ] `tool.execute.before` → `.toolStarted`
  - [ ] `tool.execute.after` → `.toolCompleted`
  - [ ] `permission.asked` → `.permissionRequested` (extract `requestID` for response routing)
  - [ ] `message.part.updated` (with delta) → `.modelResponse` (streaming text)
  - [ ] `message.updated` → `.chatUpdated` (reconstruct chat items from message content)
  - [ ] `session.diff` → `.diffUpdated`
  - [ ] `file.edited` → (optionally feed into tool tracking as implicit file change tool)

#### 8.3.7 OpenCode Provider Adapter Composition

- [ ] Actor conforming to `ProviderAdapter`
- [ ] `transportType: .httpSSE`
- [ ] Composes: `OpenCodeSSEClient` + `OpenCodeRESTClient` + `OpenCodeEventNormalizer` + `OpenCodeServerDiscovery`
- [ ] `start()`: discover or connect to OpenCode HTTP server, establish SSE connection. Uses `throws(ProviderStartupError)` with `.httpServerUnreachable` case.
- [ ] `stop()`: close SSE connection, cancel all pending HTTP requests
- [ ] `events()`: stream events from SSE connection, normalize to `ProviderEvent`. Use `.bufferingOldest(128)`.
- [ ] `respondToPermission()`: `POST /session/{id}/permissions/{permId}` via REST client — the most straightforward permission response of any provider
- [ ] `isSessionAlive()`: `GET /session/{id}` and check response status
- [ ] **Reconnection**: implement exponential backoff for SSE connection drops. SSE standard includes `retry:` field — respect it.
- [ ] Register in `ProviderRegistry`

### 8.4 Provider Adapter Test Suite

- [ ] Shared conformance tests that run against ALL provider adapters
- [ ] Use parameterized tests:

  ```swift
  @Test("Provider emits session start", arguments: ProviderID.allCases)
  func sessionStart(provider: ProviderID) async { ... }
  ```

- [ ] Mock event sources for deterministic testing:
  - [ ] `MockSocketClient` — simulates Claude/Gemini hook scripts sending JSON over Unix socket
  - [ ] `MockJSONRPCServer` — simulates Codex app-server sending JSON-RPC notifications over stdio
  - [ ] `MockHTTPServer` — simulates OpenCode HTTP server with SSE endpoint and REST permission API
- [ ] Test permission round-trips per provider:
  - [ ] Claude: hook sends PermissionRequest → socket → Swift app → approve/deny → socket → hook → stdout JSON
  - [ ] Codex: app-server sends `requestApproval` JSON-RPC → Swift responds with decision JSON-RPC
  - [ ] Gemini: hook sends BeforeTool → socket → Swift app → approve/deny → socket → hook → stdout JSON
  - [ ] OpenCode: SSE delivers `permission.asked` → Swift sends `POST /session/{id}/permissions/{permId}`
- [ ] Test event normalization for each provider's full event set
- [ ] Use `withKnownIssue` for Codex/Gemini/OpenCode tests during Phase 3 development (when only Claude is implemented)

---

## Phase 9 — Settings, Preferences & Sound

### 9.1 AppSettings

```
OICore/Settings/AppSettings.swift
```

- [ ] **`Sendable` struct with static computed properties** backed by `UserDefaults`:
  - [ ] `notificationSound: NotificationSound`
  - [ ] `soundSuppression: SoundSuppression`
  - [ ] `mascotColor: Color`
  - [ ] `mascotAlwaysVisible: Bool`
  - [ ] `notchAutoExpand: Bool`
  - [ ] `enabledProviders: Set<ProviderID>`
  - [ ] `verboseMode: Bool`
- [ ] Per-provider settings namespace (e.g., `claude.hookPath`, `codex.appServerBinary`, `codex.approvalPolicy`, `gemini.hookPath`, `gemini.throttleAfterModelMs`, `opencode.serverPort`, `opencode.useMDNS`)
- [ ] Thread safety note: `UserDefaults` is inherently thread-safe, so static computed properties reading/writing `UserDefaults` are safe across isolation domains without additional synchronization. Do not use static stored properties (which would require `nonisolated(unsafe)` or actor isolation). **Add a code comment** explaining why `Mutex` is not needed here (unlike most shared state) to prevent a well-meaning contributor from "fixing" it:

  ```swift
  // UserDefaults is documented as thread-safe by Apple. Static computed
  // properties here delegate directly to UserDefaults — no Mutex needed.
  // Do NOT add Mutex wrapping or actor isolation to these accessors.
  ```

### 9.2 Settings Menu View

```
OIUI/Views/SettingsMenuView.swift
```

- [ ] Expandable picker rows for: sound, suppression mode, screen selection, mascot color
- [ ] Provider toggles section — enable/disable each provider
- [ ] Per-provider configuration (expandable sub-sections):
  - [ ] Claude: hook installation status, socket path, reinstall hooks button
  - [ ] Codex: app-server binary path, approval policy override, sandbox mode display
  - [ ] Gemini CLI: hook installation status, AfterModel throttle interval, headless mode toggle
  - [ ] OpenCode: server port/URL, mDNS discovery toggle, connection status indicator
- [ ] Module layout customization — see Phase 6.7
- [ ] About / version info

### 9.3 Sound System

```
OICore/Sound/SoundManager.swift
```

- [ ] Play `NSSound` when session enters `.waitingForInput`
- [ ] Suppression modes: `.never`, `.whenFocused`, `.whenVisible`
- [ ] Terminal visibility detection integration (see Phase 10)

### 9.4 Notification Coordinator

```
OIUI/ViewModels/NotchActivityCoordinator.swift
```

- [ ] `@Observable` singleton managing expanding activity state
- [ ] Auto-expand on permission requests (when enabled + terminal not visible)
- [ ] Bounce animation when session needs attention

---

## Phase 10 — Terminal Detection & Process Management

### 10.1 TerminalAppRegistry

```
OICore/Terminal/TerminalAppRegistry.swift
```

- [ ] Static registry of known terminal bundle IDs and names
- [ ] Include: Terminal, iTerm2, Ghostty, Alacritty, kitty, Warp, WezTerm, Hyper
- [ ] Also include editors: VS Code, Cursor, Windsurf, Zed
- [ ] Provider-extensible — adapters can register additional relevant apps

### 10.2 TerminalVisibilityDetector

```
OICore/Terminal/TerminalVisibilityDetector.swift
```

- [ ] `CGWindowListCopyWindowInfo` queries for:
  - [ ] `isTerminalVisibleOnCurrentSpace()`
  - [ ] `isTerminalFrontmost()`
  - [ ] `isSessionTerminalVisible(sessionPID:)` — ≥50% visibility check
- [ ] May require **`@preconcurrency import CoreGraphics`** if `CGWindowListCopyWindowInfo` result types trigger Sendable diagnostics. If using the `OIAppKitBridge` module (Phase 0.7), route these queries through it instead.

### 10.3 ProcessTreeBuilder

```
OICore/Terminal/ProcessTreeBuilder.swift
```

- [ ] Build PID → parent PID tree using `proc_listallpids` / `proc_pidinfo`
- [ ] Map CLI process PID → parent terminal PID
- [ ] Detect tmux sessions
- [ ] Handle Codex's `sandbox-exec` wrapper — the Codex process may be wrapped in Seatbelt sandboxing, requiring process tree traversal through the sandbox-exec parent

### 10.4 TerminalFocuser

```
OICore/Terminal/TerminalFocuser.swift
```

- [ ] Find terminal window by PID → process tree → terminal app
- [ ] `NSRunningApplication.activate()` to bring forward
- [ ] Tmux support: `tmux select-window` / `tmux select-pane` for correct pane focusing

### 10.5 Accessibility Permission Manager

```
OICore/Permissions/AccessibilityPermissionManager.swift
```

- [ ] Check `AXIsProcessTrusted()` on launch
- [ ] Show alert if missing
- [ ] Periodic monitoring for permission grants

### 10.6 Process Detection for All Providers

```
OICore/Terminal/AgentProcessDetector.swift
```

- [ ] Detect running instances of all four CLI agents using `proc_listpids`/`proc_name` polling every 2–5 seconds
- [ ] Binary names to detect:
  - [ ] Claude Code: `claude` process
  - [ ] Codex CLI: `codex` process (may be wrapped in `sandbox-exec`)
  - [ ] Gemini CLI: `gemini` process (Node.js-based — may appear as `node` with gemini in args)
  - [ ] OpenCode: `opencode` process (Go binary)
- [ ] Wrap detection in `AsyncStream` for structured concurrency compatibility
- [ ] FSEvents monitoring of known session directories for new session files:
  - [ ] `~/.claude/projects/` (Claude Code JSONL session files)
  - [ ] `~/.codex/sessions/` (Codex session rollout files)
  - [ ] `~/.gemini/tmp/` (Gemini CLI session JSON files)
  - [ ] `~/.local/share/opencode/` (OpenCode hierarchical key-value session files)
- [ ] Wrap FSEvents in `AsyncStream` for structured concurrency compatibility

---

## Phase 11 — Auto-Update & Distribution

### 11.1 Sparkle Integration

- [ ] Add Sparkle framework dependency
- [ ] Create `NotchUserDriver` for in-notch update UI
- [ ] Configure `SPUUpdater` with hourly check interval
- [ ] Set up appcast XML endpoint
- [ ] Note: if Sparkle types need `Sendable` conformance for crossing isolation boundaries, follow this escalation path: (1) create a wrapper struct isolating Sparkle behind a `Sendable` interface, (2) submit upstream PR to Sparkle adding `Sendable` conformances, (3) `@retroactive @unchecked Sendable` as documented last resort. Prefer wrapper types where possible (per SE-0364 guidance on retroactive conformances).

### 11.2 Release Pipeline

- [ ] GitHub Actions workflow: build → sign → notarize → create DMG
- [ ] Generate appcast XML from GitHub Releases
- [ ] Version bumping script
- [ ] See Phase 0.8.6 for full CI/CD workflow details

### 11.3 Single-Instance Check

```
OICore/App/SingleInstanceGuard.swift
```

- [ ] Check `NSWorkspace.shared.runningApplications` for existing instance
- [ ] Activate existing instance and exit if found

---

## Phase 12 — Polish, Edge Cases & Performance

### 12.1 Interrupt Detection

- [ ] Per-provider interrupt detection strategy:
  - [ ] Claude: `JSONLInterruptWatcher` monitoring for `^C` patterns in JSONL transcripts
  - [ ] Codex: `turn/completed` with status `interrupted`, or `turn/interrupt` method call
  - [ ] Gemini: `AfterAgent` with interruption indicators
  - [ ] OpenCode: `session.error` or `POST /session/{id}/abort` response
- [ ] Fire `.interruptDetected` through `SessionStore`

### 12.2 Context Compaction Handling

- [ ] Handle `.compacting` phase transitions per provider:
  - [ ] Claude: `PreCompact` hook fires before compaction
  - [ ] Codex: `compacted` item type in thread items
  - [ ] Gemini: `PreCompress` hook fires before compression
  - [ ] OpenCode: `session.compacted` SSE event
- [ ] UI indicator during compaction
- [ ] Resume to correct phase after compaction completes

### 12.3 Subagent / Nested Tool Support

- [ ] Full subagent state tracking: `SubagentState` with active tasks stack
- [ ] Attribute nested tool calls to parent Task
- [ ] Provider-specific subagent patterns:
  - [ ] Claude: `SubagentStart`/`SubagentStop` hooks with explicit task IDs, `TeammateIdle`/`TaskCompleted` team events
  - [ ] Codex: `collabToolCall` item type in the ThreadItem tagged union
  - [ ] Gemini: MCP tool calls with `mcp_context` field indicating nesting
  - [ ] OpenCode: nested tool calls via plugin event system
- [ ] UI: nested tool display in chat view
- [ ] Agent file watcher for subagent directory changes

### 12.4 Token Tracking (Optional)

```
OICore/TokenTracking/TokenTrackingManager.swift
OICore/TokenTracking/QuotaService.swift
```

- [ ] `QuotaService` protocol — provider-specific quota API adapters
- [ ] `TokenTrackingManager` — periodic refresh, session + weekly utilization
- [ ] `TokenRingsModule` for closed state, `TokenRingsOverlay` for opened state
- [ ] Provider token data sources:
  - [ ] Claude Code: requires API-level integration (not exposed via hooks)
  - [ ] Codex CLI: `turn/completed` event includes token usage in response payload
  - [ ] Gemini CLI: `AfterModel` hook provides `usageMetadata.totalTokenCount`
  - [ ] OpenCode: token data available via provider-specific message fields

### 12.5 Performance Audit

- [ ] Profile with Instruments: check for unnecessary SwiftUI re-renders
- [ ] Verify incremental JSONL parsing efficiency for large files
- [ ] Audit `AsyncStream` buffering policies — confirm every stream uses an explicit policy:
  - [ ] State snapshot streams: `.bufferingNewest(1)` (latest-value semantics)
  - [ ] Event streams: `.bufferingOldest(N)` (order-preserving, bounded memory)
  - [ ] Document the rationale for each policy choice at the call site
- [ ] Ensure `Mutex` usage doesn't create contention under high event rates
- [ ] Memory leak check: verify **all** `AsyncStream` continuations have `onTermination` handlers and are properly cleaned up on subscriber removal — audit every `AsyncStream.makeStream()` call site across the project
- [ ] Verify no `Task.detached` usage exists unless explicitly justified — grep for `Task.detached` and document each instance's rationale
- [ ] Evaluate `Span<T>` (SE-0447) adoption for socket I/O and conversation parser paths as `@lifetime` annotations stabilize — replace `UnsafeBufferPointer` where possible
- [ ] **Provider-specific performance considerations**:
  - [ ] Gemini CLI `AfterModel` throttling: verify that the streaming chunk debounce (100ms default) is effective and configurable
  - [ ] OpenCode SSE reconnection: verify exponential backoff doesn't cause event loss during network hiccups
  - [ ] Codex app-server child process: verify process monitoring doesn't cause excessive CPU from `waitpid` polling
  - [ ] Multi-provider event merge: verify that the `ProviderRegistry` event merge with `withThrowingDiscardingTaskGroup` handles backpressure correctly when one provider produces events much faster than others

### 12.6 Accessibility

- [ ] VoiceOver labels on all interactive elements
- [ ] Dynamic Type support in chat view
- [ ] Reduced Motion respect for animations
- [ ] High Contrast mode support

---

## Phase 13 — Documentation & Developer Experience

### 13.1 Architecture Documentation

- [ ] `ARCHITECTURE.md` — high-level system overview (modeled on the claude-island reference doc)
- [ ] Provider adapter development guide: how to add a new provider
- [ ] Module development guide: how to create custom closed-state modules

### 13.2 Inline Documentation

- [ ] DocC comments on all `public` and `package` protocol requirements
- [ ] DocC comments on all `SessionEvent` and `ProviderEvent` cases, including which provider events they map from
- [ ] DocC comments on `SessionPhase` transition rules

### 13.3 Example Provider Skeleton

```
OIProviders/Example/ExampleProviderAdapter.swift
```

- [ ] Minimal working provider adapter that emits fake events on a timer
- [ ] Serves as a template and integration test fixture
- [ ] Documented line-by-line for onboarding new contributors
- [ ] Demonstrates all three transport types with comments showing the patterns for each:
  - [ ] Hook-based (Claude/Gemini pattern): socket server setup, hook installation, event forwarding
  - [ ] JSON-RPC (Codex pattern): child process management, message routing, approval interception
  - [ ] HTTP/SSE (OpenCode pattern): SSE connection, REST calls, server discovery

### 13.4 README & Contributing Guide

- [ ] `README.md` — project overview, screenshots, install instructions
- [ ] `CONTRIBUTING.md` — development setup, PR process, testing expectations:
  - [ ] Note about `organizeDeclarations` + `nonisolated` gotcha and `// swiftformat:disable all` guards
  - [ ] Note about forward-scan trailing closure matching (SE-0286) — the first trailing closure label is dropped in Swift 6; use labeled trailing closures for all subsequent closure parameters; avoid trailing closure syntax in `guard` conditions
  - [ ] Note about `AsyncStream` buffering policy conventions (state snapshots → `.bufferingNewest(1)`, event streams → `.bufferingOldest(N)`)
  - [ ] One primary type per file (`NotchViewModel.swift`). Extensions: `TypeName+Feature.swift` (`SessionStore+Streaming.swift`).
- [ ] `PROVIDERS.md` — status matrix of supported providers and their capabilities, including:
  - [ ] Event transport type and setup requirements
  - [ ] Permission interception mechanism and latency characteristics
  - [ ] Session log format and location
  - [ ] Configuration format and file locations
  - [ ] Known limitations per provider
  - [ ] OpenTelemetry support status
  - [ ] MCP integration notes

---

## Phase 14 — OpenTelemetry Unification Layer (Future)

> This phase is optional and depends on demand. OpenTelemetry is the most promising cross-provider unification layer for monitoring.

### 14.1 Local OTEL Collector

- [ ] All four CLI agents support OpenTelemetry export to varying degrees:
  - [ ] Codex CLI: native OTLP-HTTP/gRPC export (traces, metrics, logs)
  - [ ] Gemini CLI: native local/GCP/OTLP export
  - [ ] OpenCode: community OTEL plugin
  - [ ] Claude Code: telemetry configuration support (less documented)
- [ ] Running a local OTEL collector (e.g., Jaeger at `localhost:16686` or a lightweight OTLP receiver) that all four tools export to provides a **single observation point** with standardized GenAI semantic conventions for model parameters, token counts, and tool executions
- [ ] Evaluate whether the OTEL layer provides value beyond what the native event streams already deliver — primarily useful for cross-session analytics and historical dashboards, not real-time notch overlay updates

### 14.2 MCP as Monitoring Layer (Limitations)

- [ ] All four CLI agents support MCP as **clients/hosts** — a custom MCP server registered with all tools could act as an activity logger
- [ ] **However, MCP cannot serve as a passive monitoring layer**: MCP servers only see tool calls explicitly routed to them, not the agent's full internal state, session lifecycle, token usage, or model selection events
- [ ] The MCP logging primitive (`notifications/message`) and notification system (`notifications/tools/list_changed`) are outbound from server to host, not the direction needed for monitoring
- [ ] **Decision**: use native event systems (hooks, JSON-RPC, SSE) as the primary monitoring path. MCP is useful for tool interception but insufficient for comprehensive monitoring.

---

## Dependency Summary

| Dependency | Purpose | Phase |
|---|---|---|
| swift-markdown (Apple) | Markdown rendering in chat view (pure Swift, no OS runtime dependency) | 7 |
| Sparkle | Auto-update framework (note: may need `@retroactive` conformances for Sendable bridging) | 11 |
| swift-syntax (Apple) | If adding macro-based features | Future |
| swift-nio (Apple) | Optional: NIOAsyncChannel for Unix domain socket server (alternative to GCD) | 3 |
| just | Task runner for build/test/release workflows | 0.8 |

> **Design principle**: minimize external dependencies. Use Foundation, SwiftUI, AppKit, and system frameworks wherever possible. No Combine — use `AsyncStream` throughout.

> **Community reference projects** that validate the integration patterns:
> - **Claude Island** (github.com/farouqaldori/claude-island, 914 stars) — native macOS notch app for Claude Code, hook-to-socket pattern
> - **Agent Sessions** (github.com/jazzyalex/agent-sessions) — native macOS app browsing sessions across all four agents + GitHub Copilot CLI
> - **Agent View** — tmux-based TUI dashboard for all four tools
> - **cc-switch-cli** — manages providers, MCP servers, and settings across all four tools from a unified CLI

---

## Swift 6.2 Patterns Checklist

Applied throughout all phases:

### Approachable Concurrency (Phase 0.6 — the three pillars)

- [ ] **Pillar 1**: `MainActor` default isolation for app target only; `nonisolated` default for library targets (SE-0466)
- [ ] **Pillar 2**: `NonisolatedNonsendingByDefault` upcoming feature enabled on all targets — async functions stay on caller's actor (SE-0461)
- [ ] **Pillar 3**: `InferIsolatedConformances` upcoming feature enabled on all targets — protocol conformances in isolated contexts are automatically inferred as isolated (SE-0470)
- [ ] `@concurrent` used only on functions that genuinely need off-actor execution — CPU-bound work, blocking I/O, subprocess spawning, SSE connections, JSON-RPC parsing (SE-0461 usage guideline, not a separate pillar)
- [ ] `CONCURRENCY.md` documenting the project's concurrency contract, including forward-scan trailing closure guidance (SE-0286)

### Data-Race Safety

- [ ] Verify model types and their extensions remain `nonisolated` (the default in library targets) — do not add explicit `nonisolated` annotation as it is redundant; only annotate explicitly when overriding `MainActor` default in the app target
- [ ] `Sendable` explicitly on all `package`/`public` value types; compiler-synthesized for internal types
- [ ] `sending` parameter and result annotations (SE-0430) used at actor isolation boundaries where non-Sendable values are transferred. Key sites include `SessionStore.process(_:)`, any actor method accepting ownership of event payloads, and factory functions returning values for cross-isolation consumption. Note: `Task.init` closures use `sending` automatically in Swift 6.
- [ ] Region-based isolation (SE-0414) leveraged to avoid unnecessary `Sendable` conformances
- [ ] `Mutex<T>` from Synchronization framework for shared mutable class state
- [ ] `actor` for serialized state management (`SessionStore`, parsers, API services, `CodexAppServerClient`, `OpenCodeSSEClient`)
- [ ] No `Task.detached` unless explicitly justified — prefer regular `Task` from within actors
- [ ] `@preconcurrency import` used only on specific files needing it for legacy frameworks (Dispatch, AppKit, CoreGraphics), with comments documenting which types cause the diagnostic — prefer `OIAppKitBridge` module if feasible (Phase 0.7)

### Ownership & Noncopyable Types

- [ ] `~Copyable` struct for unique resource wrappers — `SocketFD` for Unix domain socket file descriptors (Phase 3.1), permission socket connections
- [ ] `consuming` methods for operations that transfer ownership or terminate a resource
- [ ] `borrowing` methods for read-only access to `~Copyable` resources
- [ ] `discard self` in consuming methods that perform explicit cleanup (suppresses `deinit`)
- [ ] `~Copyable` patterns validated early (Phase 3) to confirm toolchain and lint pipeline compatibility
- [ ] `~Escapable` types (SE-0446) and `@lifetime` annotations noted as experimental in Swift 6.2. Evaluate `Span<T>` as replacement for `UnsafeBufferPointer` in socket paths once `@lifetime` stabilizes. Do not adopt in initial implementation.
- [ ] `consume` keyword (SE-0366) used to explicitly end variable lifetimes in `~Copyable` paths and to document ownership transfer intent. Don't sprinkle everywhere — the optimizer handles most cases for copyable types.
- [ ] For copyable types, `borrowing`/`consuming` (SE-0377) are optional optimization hints. Do not annotate without benchmark evidence. Mandatory only for `~Copyable` types.

### Async Patterns

- [ ] `AsyncStream.makeStream()` factory for all producer/consumer patterns (SE-0388)
- [ ] `onTermination` set on **every** `AsyncStream` continuation to clean up resources and prevent memory leaks
- [ ] Explicit buffering policy on every `AsyncStream.makeStream()` call: `.bufferingNewest(1)` for state snapshots, `.bufferingOldest(N)` for ordered event streams — no implicit defaults
- [ ] `withDiscardingTaskGroup` / `withThrowingDiscardingTaskGroup` for long-running event loops (SE-0381) — specifically the `ProviderRegistry` event merge loop
- [ ] No Combine anywhere — `AsyncStream` throughout

### Type System & Access Control

- [ ] `package` access level for intra-package APIs (SE-0386)
- [ ] `any Protocol` required for existential types; `some Protocol` preferred (SE-0335) — `any` reserved for heterogeneous collections (e.g., `ProviderRegistry`); concrete types or `some` used within provider-specific code
- [ ] `ExistentialAny` upcoming feature flag enabled on all targets (compile-time enforcement)
- [ ] `InternalImportsByDefault` upcoming feature flag enabled on all targets (SE-0409) — `public import` only where deliberately re-exporting
- [ ] `MemberImportVisibility` upcoming feature flag enabled on all targets (SE-0444) — members only visible from directly imported modules, preventing transitive dependency leakage
- [ ] `if`/`switch` expressions for value-producing conditionals (SE-0380)
- [ ] `throws(ErrorType)` for closed error domains: `ProviderStartupError`, `EventNormalizationError`, `HookInstallError` (SE-0413). Plain `throws` intentionally used for open error domains (e.g., `respondToPermission()`)
- [ ] `guard let x` shorthand (SE-0345) for optional unwrapping throughout
- [ ] `BitwiseCopyable` on simple `package`/`public` leaf enums with no reference types — `PermissionDecision`, `ModuleSide`, `ToolStatus`, `PermissionRisk` (SE-0426). **Not** on `ProviderID` (has `String` raw values, which are not `BitwiseCopyable`)
- [ ] `#Expression` (macOS 15+, swift-dev-pro.md Section 5) available for type-safe expression building beyond `#Predicate` — evaluate for dynamic module filtering or settings logic if needed
- [ ] `@retroactive` conformances documented and minimized — prefer wrapper types (SE-0364)

### Observation & UI

- [ ] `@Observable` for all view models (SE-0395)
- [ ] `@Bindable` for `$` bindings, `@State` for view-owned objects, `@Environment` for injection
- [ ] Pass `@Observable` objects as plain properties (no wrapper) for read-only child views — SwiftUI auto-tracks changes. Reserve `@Bindable` only when `$` bindings are needed.
- [ ] Apply `@ObservationIgnored` to properties that should not trigger UI updates: UUID/identity properties, cached computation results, internal subscription handles, geometry objects recomputed from external parameters, and high-frequency properties where observation overhead matters.
- [ ] Never write `@ObservationTracked` manually — it is auto-applied by `@Observable`. Use `@ObservationIgnored` to opt out.
- [ ] No `ObservableObject` / `@Published` / `@StateObject` / `@EnvironmentObject` anywhere
- [ ] `#Preview` blocks included in every SwiftUI view file with mock data helpers

### Testing

- [ ] Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`, `#require`) for all new tests
- [ ] Parameterized tests (`@Test(arguments:)`) for multi-provider scenarios
- [ ] `confirmation` for async event verification
- [ ] `single_test_class` SwiftLint rule disabled (incompatible with Swift Testing)
- [ ] Test traits used: `.tags()` for filtering by provider/domain, `.serialized` for shared-resource suites, `.timeLimit(.minutes(1))` for socket/network tests, `.disabled("reason")` over commenting out, `.enabled(if:)` for conditional tests, `.bug(id:)` for bug tracker links
- [ ] `withKnownIssue` used for tests covering known incomplete features (e.g., Codex/Gemini provider tests before implementation). Prefer over `.disabled()` when the test body exists but the feature is not yet complete.
- [ ] Exit testing (Swift 6.2) used for verifying fatal error paths in `~Copyable` resource types. Test attachments used for diagnostic data in socket integration tests.
- [ ] XCTest used only for UI testing (XCUITest) and performance benchmarking (`measure {}`). Not mixed with Swift Testing in the same file.

### Compile-Time Enforcement (Phase 0.3 — lint rules)

- [ ] `no_observable_object` custom SwiftLint rule active — prevents legacy `ObservableObject` / `@Published` / `@StateObject` / `@ObservedObject` / `@EnvironmentObject` usage. Verified against comment/string false positives (Phase 0.3.5).
- [ ] `no_combine_import` custom SwiftLint rule active — prevents `import Combine` (AsyncStream throughout)
- [ ] `no_nonisolated_unsafe` custom SwiftLint rule active — prevents `nonisolated(unsafe)` usage (use `Mutex<T>` or `actor` instead)
- [ ] `private_over_fileprivate` SwiftLint rule enabled for clean module boundaries
- [ ] `redundantSendable` SwiftFormat rule disabled — explicit `Sendable` on public types is intentional (SE-0414 region-based isolation)

### Code Quality (Phase 0.3 — `prek` pipeline)

- [ ] `.pre-commit-config.yaml` configured and `prek install` run
- [ ] `.swiftformat` adapted with correct `--exclude` paths, `--swiftversion 6.2`, `OI,SSE,RPC,OTLP` in `--acronyms`
- [ ] `.swiftlint.yml` adapted with correct `included:` paths, `single_test_class` disabled, custom rules added and verified for false positives
- [ ] `prek run --all-files` passes cleanly on initial project skeleton (including custom rule verification)
- [ ] `justfile` with `format`, `lint`, `test`, `build`, `clean`, `install-hooks` recipes
