# open-island — Implementation Plan

> A provider-agnostic macOS notch overlay for monitoring CLI/TUI coding agents.
> Supports Claude Code, Codex, Gemini CLI, OpenCode — and any future provider.

---

## Phase 0 — Project Scaffolding & Tooling

### 0.1 Xcode Project Setup

- [ ] Create a new macOS app target in Xcode 17 (Swift 6.2, minimum deployment macOS 16.0)
  - [ ] **Deployment target rationale**: macOS 16.0 (Tahoe, shipped Fall 2025) is Xcode 17's default new-project template target. All Swift 6.2 compile-time features back-deploy freely (swift-dev-pro.md Section 12). The primary runtime-dependent feature used by this project is `@Observable` (macOS 14+). `#Predicate` (requires macOS 14+) and `#Expression` (requires macOS 15+) are both available at our macOS 16.0 deployment target if needed for session filtering or dynamic module logic. Targeting macOS 16.0 gives access to any Tahoe-specific AppKit improvements (NSPanel behaviors, window management) and matches the expected audience — developers running CLI coding agents are overwhelmingly on the latest macOS.
- [ ] Set activation policy to `.accessory` (no dock icon)
- [ ] Configure build settings:
  - [ ] `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466)
  - [ ] `SWIFT_APPROACHABLE_CONCURRENCY = YES`
  - [ ] Swift Language Mode: Swift 6
  - [ ] Note: Swift 6 language mode subsumes strict concurrency checking — `SWIFT_STRICT_CONCURRENCY` is not needed. Do not add `SWIFT_STRICT_CONCURRENCY = complete`; it is a Swift 5 migration setting and is a no-op under Swift 6 language mode.
  - [ ] Note: `SWIFT_APPROACHABLE_CONCURRENCY = YES` is an **Xcode-only build setting** that applies exclusively to the Xcode-managed app target (`open-island.app`). It is the Xcode equivalent of enabling `NonisolatedNonsendingByDefault` + `InferIsolatedConformances` together. SPM library targets (`OIKit`, `OIProviders`, etc.) do not inherit Xcode build settings and instead receive these features via the `.enableUpcomingFeature()` calls in Phase 0.2's Package.swift. These cover different targets and are not redundant.
- [ ] Add a `Settings { EmptyView() }` scene as the only SwiftUI scene (all UI via custom NSPanel)
- [ ] Set bundle identifier, app icon placeholder, and Info.plist entries (LSUIElement = YES for accessory)

### 0.2 SPM / Package.swift for Internal Modules

- [ ] Create a local Swift package (`OpenIslandKit`) with these initial library targets:
  - [ ] `OICore` — shared models, protocols, utilities
  - [ ] `OIProviders` — provider adapter protocol + concrete implementations
  - [ ] `OIWindow` — notch window system, geometry, shape
  - [ ] `OIModules` — closed-state module system
  - [ ] `OIUI` — SwiftUI views
  - [ ] `OIState` — SessionStore, state machine, event processing
- [ ] Configure `swift-tools-version: 6.2` (Swift 6 language mode is enabled by default for all targets with `swift-tools-version: 6.0+` — do not add `.swiftLanguageMode(.v6)` on targets, as it is redundant. Note: swift-dev-pro.md Section 1 example includes `.swiftLanguageMode(.v6)` explicitly for clarity, but it is a no-op with `swift-tools-version: 6.2`.)
- [ ] Enable upcoming feature flags per target:
  ```swift
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  ```
- [ ] Use `package` access level for intra-package APIs instead of `public` where possible
- [ ] `.defaultIsolation(MainActor.self)` is intentionally absent from Package.swift — the SPM package contains only library targets, which keep `nonisolated` default per project guidelines. The app target receives MainActor default isolation via Xcode build setting (Phase 0.1).
- [ ] Since `OpenIslandKit` is an internal package (no library evolution mode), `@inlinable`, `@usableFromInline`, and `@frozen` are unnecessary. Don't add unless benchmarks show measurable improvement.
- [ ] With `InternalImportsByDefault` enabled, all `import` statements default to `internal` visibility. Use `public import Foundation` (or `public import AppKit`, etc.) **only** in modules that deliberately re-export those symbols to downstream targets. This prevents transitive dependency leakage across module boundaries.
- [ ] **Per-target warning control** (SE-0480, Swift 6.2): use `.swiftSettings([.warningLevel(.error, for: .deprecation)])` on production targets to promote deprecation warnings to errors. Keep default warning levels on test targets where mock/fixture code may use deprecated APIs intentionally. Evaluate need during Phase 12.5 performance audit; add only if specific warning categories prove problematic.

> **Note on `ExistentialAny`**: Deferred to Swift 7 as a mandatory language change (not required in Swift 6), but enabled here as an upcoming feature flag to enforce `any Protocol` discipline at compile time in a greenfield project. This aligns with the project checklist requirement that `any Protocol` is required for all existential types (SE-0335).

> **Note on `InternalImportsByDefault`**: Also targeting Swift 7 (SE-0409), but enabled here to enforce minimal transitive dependency exposure from day one. Combined with `package` access level, this ensures each module's public surface is deliberate.

### 0.3 Pre-commit & Code Quality Pipeline (`prek`)

Set up the full `prek` (pre-commit) pipeline before writing any application code. This gates every commit.

#### 0.3.1 `.pre-commit-config.yaml`

Adapt the claude-island config with these changes:

- [ ] **`exclude` regex**: update project-specific paths — replace `ClaudeIsland` references with `OpenIsland` and `OpenIslandKit` module paths. Add `OpenIslandKit/\.build/.*` for the SPM package build directory.
- [ ] **SwiftFormat hook**: keep `types: [swift]`, ensure `entry: swiftformat` uses the system-installed binary (same as claude-island)
- [ ] **SwiftLint hook**: keep `entry: swiftlint lint --strict`, `types: [swift]`
- [ ] **Ruff hooks** (`ruff-check`, `ruff-format`): update `files:` pattern from `^ClaudeIsland/Resources/.*\.py$` to `^OpenIsland/Resources/Hooks/.*\.py$` — this covers the provider hook scripts (Claude's Python hook, and any future Python-based hooks)
- [ ] **Shellcheck**: update `files:` to `^scripts/.*\.sh$` (same pattern, verify `scripts/` directory exists)
- [ ] **Markdownlint**: keep as-is, update `exclude` if needed for new directory names
- [ ] **Standard hooks**: keep all (`trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-json`, `check-merge-conflict`, `detect-private-key`, `no-commit-to-branch`, `check-added-large-files`)
- [ ] **Bump versions**: check for latest revs of all repos (pre-commit-hooks, SwiftFormat, SwiftLint, shellcheck-py, ruff-pre-commit, markdownlint-cli) at project creation time
- [ ] Keep `ci: skip: [swiftformat, swiftlint]` since CI runners may not have these installed system-wide

Full config:

```yaml
# Pre-commit configuration for open-island
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

- [ ] `--swiftversion 6.2` (already correct)
- [ ] **`--exclude`**: update to `build,DerivedData,.build,Pods,releases,*.xcodeproj,*.xcworkspace,xcuserdata,.sparkle-keys,OpenIslandKit/.build` — remove the claude-island-specific `HookSocketServer.swift` exclusion (start fresh; if the new socket server triggers the same `organizeDeclarations` timeout, exclude it then)
- [ ] **`--acronyms`**: keep all existing (`ID,URL,UUID,HTTP,HTTPS,JSON,API,UI,MCP,PID,JSONL,SSH,TCP,IP,DNS,HTML,XML,CSS,JS,SDK,CLI,TLS,SSL`) — add `OI` (project prefix) for type names
- [ ] **All enabled rules**: keep `acronyms`, `blankLinesBetweenImports`, `blockComments`, `docComments`, `isEmpty`, `markTypes`, `organizeDeclarations`, `sortDeclarations`, `wrapEnumCases`, `wrapSwitchCases`
- [ ] **All disabled rules**: keep `andOperator`, `redundantSendable`, `wrapMultilineStatementBraces`
- [ ] **`redundantSendable` rationale**: Swift 6.2's region-based isolation (SE-0414) means many explicit `Sendable` conformances that look redundant are actually intentional public API contracts — do not auto-remove them
- [ ] **Gotcha from claude-island**: `organizeDeclarations` can strip explicit `nonisolated` on synthesizable conformances (e.g., `Equatable`). Document this in a `CONTRIBUTING.md` note and use `// swiftformat:disable all` / `// swiftformat:enable all` guards around affected declarations

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
# Added OI (project prefix) per open-island naming conventions
--acronyms ID,URL,UUID,HTTP,HTTPS,JSON,API,UI,MCP,PID,JSONL,SSH,TCP,IP,DNS,HTML,XML,CSS,JS,SDK,CLI,TLS,SSL,OI

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

- [ ] **`included:`**: update from `[ClaudeIsland]` to `[OpenIsland, OpenIslandKit]` (main app + SPM package sources)
- [ ] **`excluded:`**: keep `build`, `DerivedData`, `.build`, `Pods`, `releases`, `*.xcodeproj`, `*.xcworkspace`, `xcuserdata`
- [ ] **Opt-in rules**: keep the full list from claude-island with the following changes:
  - [ ] **Remove** `single_test_class` — move to `disabled_rules`. This rule is incompatible with Swift Testing: Swift Testing uses `@Suite` structs (not `XCTestCase` subclasses), multiple `@Suite` structs per file is valid, and global `@Test` functions have no enclosing type at all.
  - [ ] **Add** `private_over_fileprivate` — for clean module boundaries in a greenfield project
- [ ] **Rule configs**: keep all thresholds (line_length 150/200, function_body_length 60/100, file_length 500/1000, type_body_length 300/500, cyclomatic_complexity 15/25, nesting 3/5 type + 5/8 function)
- [ ] **Identifier exclusions**: keep `id, ok, to, x, y, i, j, n` — add `fd` for file descriptors used in `~Copyable` resource types (e.g., `FileHandle` with `fd: Int32`)
- [ ] **Custom `no_print_statements` rule**: keep — use `os.Logger` throughout the project instead of `print()`
- [ ] **Add custom `no_observable_object` rule**: warn on `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` — enforces the project's `@Observable`-only convention at lint time instead of relying on developer memory
- [ ] **Add custom `no_combine_import` rule**: warn on `import Combine` — enforces the project's `AsyncStream`-only convention

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

#### 0.3.4 `Makefile` / `justfile`

Create a `Makefile` (or `justfile` if preferred) with these targets:

```makefile
format:          ## Run SwiftFormat on all Swift files
lint:            ## Run SwiftLint in strict mode
test:            ## Run all Swift Testing suites
build:           ## Build all targets (debug)
build-release:   ## Build all targets (release)
pre-commit:      ## Run prek on all files (manual full check)
clean:           ## Remove build artifacts and DerivedData
install-hooks:   ## Install prek hooks (pre-commit + pre-push)
```

- [ ] **Optional**: Consider adding SwiftLint and SwiftFormat as SwiftPM command plugins (SE-0332) for IDE-integrated linting via `swift package plugin swiftlint`. This complements the `prek` pre-commit hooks by enabling linting from any context without hook installation. Evaluate if team workflow benefits from this during Phase 13.

#### 0.3.5 Verify Pipeline End-to-End

- [ ] Run `prek install --hook-type pre-commit --hook-type pre-push`
- [ ] Create a test Swift file with intentional formatting issues
- [ ] Commit → verify SwiftFormat auto-fixes, SwiftLint catches violations
- [ ] Create a test Python file in `Resources/Hooks/` → verify Ruff catches issues
- [ ] Confirm `prek run --all-files` passes cleanly on the empty project skeleton
- [ ] Verify the `no_observable_object` custom rule fires on `@Published var test = ""` in a test file, and does **not** fire on `// We migrated from ObservableObject` in a comment
- [ ] Verify the `no_combine_import` custom rule fires on `import Combine` in a test file
- [ ] Clean up test files after verification

### 0.4 Testing Infrastructure

- [ ] Add a `OICoreTests` target using Swift Testing (`import Testing`)
- [ ] Add a `OIStateTests` target for state machine and SessionStore tests
- [ ] Add a `OIProvidersTests` target for provider adapter tests
- [ ] Configure all test suites as `@Suite` structs (not classes)
- [ ] Establish parameterized test patterns for multi-provider scenarios
- [ ] Note: `single_test_class` SwiftLint rule is disabled — multiple `@Suite` structs per file and global `@Test` functions are valid Swift Testing patterns
- [ ] Define project-wide test tags: `extension Tag { @Tag static var claude: Self; @Tag static var socket: Self; @Tag static var ui: Self }`. Use `.serialized` on suites with shared file system resources. Use `.timeLimit(.minutes(1))` on socket tests. Use `.disabled("reason")` over commenting out tests. Use `.enabled(if:)` for provider-specific tests conditional on binary availability. Use `.bug(id:)` to link tests to bug tracker.
- [ ] Implement custom test traits for common setup/teardown: `MockSocketTrait` (creates/destroys temp socket), `TempDirectoryTrait` (creates/cleans temp directory). Uses `TestTrait` + `TestScoping` (Swift 6.1+).
- [ ] XCTest remains required for UI testing (XCUITest) and performance benchmarking (`measure {}`). Create separate XCTest-based targets if needed. Do not mix XCTest and Swift Testing assertions in the same file.
- [ ] Name test files as `<TypeUnderTest>Tests.swift`: `SessionPhaseTests.swift`, `JSONValueTests.swift`, `ClaudeEventNormalizerTests.swift`.

### 0.5 Git & CI Foundations

- [ ] Initialize repo with `.gitignore` (Xcode, SPM, DerivedData, build artifacts)
- [ ] Set up branch protection on `main`
- [ ] Add a basic GitHub Actions workflow: build + test on macOS runner
- [ ] Install pre-commit hooks

### 0.6 Approachable Concurrency Strategy (Swift 6.2)

This is a **deliberate architectural decision**, not just build flags. Swift 6.2's Approachable Concurrency has three pillars — all three must be configured consistently across the project.

#### 0.6.1 Pillar 1 — MainActor by Default ("single-threaded by default")

- [ ] **App target** (`OpenIsland`): enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466). This means every type, function, and property in the app target is `@MainActor`-isolated unless explicitly opted out.
- [ ] **SPM library targets** (`OICore`, `OIProviders`, etc.): keep `nonisolated` as the default. Libraries should not assume main-thread execution — they are consumed by the app target, which decides isolation.
- [ ] **Implication**: all model types, utility functions, and protocol definitions in SPM targets must be explicitly `nonisolated` (which they are by default in those targets). When used from the app target, the compiler handles the isolation boundary correctly.
- [ ] In `Package.swift`, only the app-facing target gets `.defaultIsolation(MainActor.self)`. In Xcode, set the build setting on the app target only.

#### 0.6.2 Pillar 2 — Nonisolated Nonsending by Default ("intuitive async functions")

- [ ] Enable `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` (SE-0461) on **all targets**.
- [ ] **What this changes**: nonisolated `async` functions no longer hop to the global concurrent executor. They run in the caller's execution context. This means calling an `async` function from the main actor keeps you on the main actor — no implicit thread hop.
- [ ] **Practical impact**: most `async` functions in the app "just work" without data-race issues. You can write `async` methods on classes without needing `@Sendable` closures or actor isolation annotations everywhere.
- [ ] **Where this matters most**: `ConversationParser`, `ClaudeAPIService`, and other actors already serialize access. But helper `async` functions that don't need their own isolation domain (e.g., file reading utilities, JSON parsing) will stay on the caller's actor instead of bouncing to a background thread.

#### 0.6.3 Pillar 3 — Infer Isolated Conformances ("less boilerplate")

- [ ] Enable `.enableUpcomingFeature("InferIsolatedConformances")` (SE-0470) on **all targets**.
- [ ] **What this changes**: when a type is isolated to an actor (e.g., MainActor-isolated in the app target), its protocol conformances are automatically inferred as isolated too. Without this flag, conforming to a protocol like `Hashable` from a MainActor-isolated type requires explicitly marking `hash(into:)` as `nonisolated` or `@MainActor`.
- [ ] **Practical impact**: `@Observable` view models in the app target can conform to protocols without boilerplate isolation annotations. Model types in library targets (which default to `nonisolated`) are unaffected.
- [ ] **Example**: With this flag enabled, a MainActor-isolated type conforming to `Equatable` gets its `==` method inferred as MainActor-isolated automatically, instead of requiring explicit annotation.

#### 0.6.4 `@concurrent` Usage Guidelines ("opting into concurrency")

- [ ] `@concurrent` is a usage pattern within SE-0461 (Pillar 2), not a separate pillar. It is the explicit opt-in for off-actor execution when the default (run on caller's actor) is not appropriate.
- [ ] Use `@concurrent` **only** on functions that genuinely need to run off the calling actor — CPU-heavy computation, blocking I/O that shouldn't freeze the main thread, or work that benefits from parallelism.
- [ ] Examples in `open-island`:
  - [ ] `@concurrent func parseJSONLChunk(_ data: Data) async -> [ChatMessage]` — parsing large JSONL chunks should not block the main actor
  - [ ] `@concurrent func detectPythonRuntime() async -> PythonRuntime?` — spawns subprocesses, should not block UI
  - [ ] `@concurrent func buildProcessTree() async -> [Int32: Int32]` — enumerates all PIDs, CPU-bound
- [ ] **Rule**: if a function doesn't need to run in parallel, don't mark it `@concurrent`. The default (run on caller's actor) is safer and simpler.

#### 0.6.5 Configuration Summary

| Target | Default Isolation | NonisolatedNonsending | InferIsolatedConformances | `@concurrent` Usage |
|---|---|---|---|---|
| `OpenIsland` (app) | `MainActor` | Yes (upcoming feature) | Yes (upcoming feature) | Sparingly — heavy computation only |
| `OICore` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | On CPU-bound utilities |
| `OIProviders` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | On file I/O, process spawning |
| `OIState` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Rarely — actors serialize already |
| `OIWindow` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Never — all UI work |
| `OIUI` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Never — all UI work |
| `OIModules` | `nonisolated` | Yes (upcoming feature) | Yes (upcoming feature) | Never — all UI work |

#### 0.6.6 Document the Concurrency Contract

Create `CONCURRENCY.md` in the repo root explaining:

- [ ] Why `MainActor` is the default for the app target (safety, simplicity, matches Xcode 17's default template)
- [ ] Why library targets stay `nonisolated` (reusability, no main-thread assumption)
- [ ] When to use `@concurrent` (include the 3 examples above as canonical patterns)
- [ ] When to use `actor` (shared mutable state accessed from multiple isolation domains)
- [ ] When to use `Mutex<T>` (protecting state in `Sendable` classes, GCD-bridging code). **`Mutex<T>` requires `import Synchronization`** (Swift 6.0+) — add this import wherever `Mutex` is used. The `Synchronization` framework is a compiler-level module with no OS runtime dependency (back-deploys freely).
- [ ] When **not** to mark functions `@concurrent` (most of the time — the default is correct)
- [ ] When `InlineArray` (SE-0452) may be a fit for fixed-size buffers with trivially-copyable elements (e.g., small `ProviderID` → color lookup tables) — note as a future optimization opportunity, but **not** suitable for collections of complex types like `SessionEvent` (see Phase 2.1 note)
- [ ] When to use `@preconcurrency import` for legacy frameworks (see Phase 0.7)
- [ ] **`nonisolated(unsafe)` — never use in this project.** Prefer `Mutex<T>`, `actor`, or `@preconcurrency import`. A SwiftLint custom rule (`no_nonisolated_unsafe`) enforces this at compile time (Phase 0.3.3).
- [ ] **`async let` for structured concurrency**: use `async let` for fixed-count parallel operations; task groups for dynamic counts. Example:
  ```swift
  // Phase 3.6 — starting independent subsystems
  async let hooks = installer.install()
  async let socket = socketServer.start()
  async let watcher = conversationParser.startWatching()
  try await (hooks, socket, watcher)
  ```
- [ ] **`Task.init` closures use `sending` semantics (not `@Sendable`)**: In Swift 6, `Task { }` closures use `sending` semantics. Captured values need only be disconnected from their current isolation region, not fully `Sendable`. Don't reflexively add `Sendable` conformance just because a type is captured in a `Task { }` closure.
- [ ] **`Span<T>` for safe contiguous access**: Prefer `Span<T>` (SE-0447) over `UnsafeBufferPointer` for read-only contiguous access. Full adoption requires `@lifetime` annotations (experimental in 6.2). Adopt incrementally as annotations stabilize.
- [ ] **Forward-scan trailing closures** (SE-0286): Swift 6 changed trailing closure matching from backward-scan to forward-scan. When designing APIs with multiple closure parameters, the first trailing closure label is dropped. Use labeled trailing closures for all subsequent closure parameters. Avoid trailing closure syntax in `guard` conditions. Document this in `CONTRIBUTING.md` as well so contributors from Swift 5 habits are aware.

### 0.7 Legacy Framework Import Strategy

Several system frameworks predate Swift concurrency and may produce Sendable diagnostics in strict Swift 6 mode. Use `@preconcurrency import` to suppress warnings from frameworks the project cannot control:

- [ ] **`@preconcurrency import Dispatch`** — required in `ClaudeHookSocketServer.swift` (Phase 3.1) and anywhere using `DispatchSource`, `DispatchQueue`, or GCD primitives
- [ ] **`@preconcurrency import AppKit`** — may be needed in `NotchPanel.swift`, `WindowManager.swift`, and other AppKit-bridging code where `NSWindow`, `NSEvent`, or `NSScreen` types cross isolation boundaries
- [ ] **`@preconcurrency import CoreGraphics`** — if `CGWindowListCopyWindowInfo` results trigger Sendable warnings in `TerminalVisibilityDetector.swift`

**Preferred approach — `OIAppKitBridge` module**: rather than scattering `@preconcurrency import AppKit` across multiple files, consider creating a thin `OIAppKitBridge` internal module that encapsulates all AppKit interactions behind `@MainActor`-isolated `Sendable` wrappers. This confines `@preconcurrency` to one module's source files and gives the rest of the codebase clean, compiler-verified types to work with. Evaluate feasibility in Phase 4; if the bridging surface is small enough, a single module is cleaner than per-file annotations.

**Rule**: if the `OIAppKitBridge` approach is not feasible, use `@preconcurrency import` only on the specific files that need it, not as a blanket project-wide practice. Each usage should include a comment explaining which types cause the diagnostic. Treat these as temporary — remove them when Apple ships Sendable-annotated framework headers.

Document these in `CONCURRENCY.md` under a "Legacy Framework Imports" section.

---

## Phase 1 — Core Models & Provider Protocol

### 1.1 Define `ProviderID` and `ProviderMetadata`

```
OICore/Provider/ProviderID.swift
OICore/Provider/ProviderMetadata.swift
```

- [ ] `ProviderID` — a `RawRepresentable<String>`, `Sendable`, `Hashable` enum with cases: `.claude`, `.codex`, `.geminiCLI`, `.openCode`
- [ ] `ProviderMetadata` — struct holding display name, icon name (SF Symbol or bundled), accent color, CLI binary name(s)
- [ ] Both must be `Sendable` value types
- [ ] **Note**: `ProviderID` has `String` raw values. `String` is a reference-counted, heap-allocated type and is **not** `BitwiseCopyable`. Do not mark `ProviderID` as `BitwiseCopyable` — the compiler would reject this conformance. `BitwiseCopyable` (SE-0426) is reserved for types whose stored properties are all trivially copyable via `memcpy` (e.g., enums with `Int` raw values and no associated values containing reference types).

### 1.2 Define Universal Event Types

```
OICore/Events/ProviderEvent.swift
OICore/Events/SessionEvent.swift
```

- [ ] `ProviderEvent` — the normalized event enum that all providers emit:
  - [ ] `.sessionStarted(SessionID, cwd: String, pid: Int32?)`
  - [ ] `.sessionEnded(SessionID)`
  - [ ] `.userPromptSubmitted(SessionID)`
  - [ ] `.processingStarted(SessionID)`
  - [ ] `.toolStarted(SessionID, ToolEvent)`
  - [ ] `.toolCompleted(SessionID, ToolEvent, ToolResult?)`
  - [ ] `.permissionRequested(SessionID, PermissionRequest)`
  - [ ] `.waitingForInput(SessionID)`
  - [ ] `.compacting(SessionID)`
  - [ ] `.notification(SessionID, message: String)`
  - [ ] `.chatUpdated(SessionID, [ChatHistoryItem])`
- [ ] `SessionEvent` — internal event for the `SessionStore` (superset of ProviderEvent + UI events like `.permissionApproved`, `.archiveSession`, etc.)
- [ ] All payloads are `Sendable` structs/enums — explicitly marked `Sendable` since they are `package`-visible and cross module boundaries

### 1.3 Define Session Models

```
OICore/Models/SessionState.swift
OICore/Models/SessionPhase.swift
OICore/Models/PermissionContext.swift
OICore/Models/ToolCallItem.swift
OICore/Models/ChatHistoryItem.swift
```

- [ ] `SessionPhase` — state machine enum: `.idle`, `.processing`, `.waitingForInput`, `.waitingForApproval(PermissionContext)`, `.compacting`, `.ended`
  - [ ] Include `canTransition(to:) -> Bool` with the validated transition table from claude-island
  - [ ] Validated transitions, invalid ones logged and ignored
  - [ ] Explicitly marked `Sendable` — the `.waitingForApproval(PermissionContext)` associated value requires `PermissionContext` to also be `Sendable`
  - [ ] Use `guard let` shorthand (SE-0345) in transition validation methods:
    ```swift
    func validate(event: SessionEvent) -> SessionPhase? {
        guard let targetPhase = event.targetPhase else { return nil }
        guard canTransition(to: targetPhase) else { return nil }
        return targetPhase
    }
    ```
- [ ] `SessionState` — complete snapshot struct:
  - [ ] `id: String` (session ID)
  - [ ] `providerID: ProviderID`
  - [ ] `phase: SessionPhase`
  - [ ] `projectName: String`
  - [ ] `cwd: String`
  - [ ] `pid: Int32?`
  - [ ] `chatItems: [ChatHistoryItem]`
  - [ ] `toolTracker: ToolTracker`
  - [ ] `createdAt: Date`
  - [ ] `lastActivityAt: Date`
  - [ ] Explicitly marked `Sendable` — all stored properties must be `Sendable`
- [ ] `PermissionContext` — tool use ID, name, input, timestamp, `displaySummary` computed property. Explicitly `Sendable`.
- [ ] `ChatHistoryItem` — ID, timestamp, type enum (`.user`, `.assistant`, `.toolCall`, `.thinking`, `.interrupted`). Explicitly `Sendable`.
- [ ] `ToolCallItem` — name, input, status (`.running`, `.success`, `.error`, `.interrupted`), result, nested subagent tools. Explicitly `Sendable`.
- [ ] Simple leaf enums with no reference types (`PermissionDecision`, `ModuleSide`, `ToolStatus`) should be marked `BitwiseCopyable` (SE-0426) — these contain only trivial cases (no `String` associated values, no reference-type payloads) and explicit conformance on `package`-visible types enables more efficient generic code paths.
- [ ] Note: `BitwiseCopyable` is auto-inferred for `internal` types but must be declared explicitly when promoting to `package` or `public`. Audit for missing conformance when elevating access levels.

### 1.4 Define `JSONValue` Type

```
OICore/Models/JSONValue.swift
```

- [ ] Recursive enum: `.string`, `.int`, `.double`, `.bool`, `.null`, `.array([JSONValue])`, `.object([String: JSONValue])`
- [ ] `Sendable`, `Equatable`, `Codable`
- [ ] Replaces `AnyCodable` / `@unchecked Sendable` dictionary patterns
- [ ] Include subscript accessors for ergonomic nested access

### 1.5 Provider Adapter Protocol

```
OIProviders/ProviderAdapter.swift
```

- [ ] Protocol definition:
  ```swift
  package protocol ProviderAdapter: Sendable {
      var providerID: ProviderID { get }
      var metadata: ProviderMetadata { get }

      func start() async throws(ProviderStartupError)
      func stop() async

      /// Stream of normalized events from this provider
      func events() -> some AsyncSequence<ProviderEvent, Never>

      /// Respond to a permission request.
      /// Uses plain `throws` intentionally — failure modes are provider-specific
      /// and not a closed domain (network errors, timeout, provider-specific
      /// protocol failures, etc.).
      func respondToPermission(
          _ request: PermissionRequest,
          decision: PermissionDecision
      ) async throws

      /// Check if a session is still alive
      func isSessionAlive(_ sessionID: String) -> Bool
  }
  ```
- [ ] `PermissionDecision` — enum: `.allow`, `.deny(reason: String?)`
- [ ] Each provider implementation is a concrete actor conforming to this protocol

#### Typed throws candidates

Use `throws(ErrorType)` (SE-0413) in these closed error domains:

- [ ] **`ProviderAdapter.start()`** → `throws(ProviderStartupError)`:
  ```swift
  package enum ProviderStartupError: Error, Sendable {
      case binaryNotFound(String)
      case hookInstallationFailed(String)
      case socketBindFailed(path: String, errno: Int32)
      case permissionDenied(String)
  }
  ```
  This is a closed domain — all startup failure modes are known. Callers can exhaustively match without a generic `catch`.

- [ ] **`ClaudeEventNormalizer.normalize()`** → `throws(EventNormalizationError)`:
  ```swift
  package enum EventNormalizationError: Error, Sendable {
      case unknownEventType(String)
      case malformedPayload(field: String)
      case missingRequiredField(String)
  }
  ```

- [ ] **`ClaudeHookInstaller.install()`** → `throws(HookInstallError)`:
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

- [ ] `ProviderRegistry` — actor that:
  - [ ] Holds registered `[ProviderID: any ProviderAdapter]` — `any` is correct here for runtime heterogeneity across provider types
  - [ ] Starts/stops all adapters
  - [ ] Merges all provider event streams into a single `AsyncStream<ProviderEvent>`
  - [ ] Provides lookup by ID
- [ ] Use `withTaskGroup` to start all adapters concurrently
- [ ] Use **`withThrowingDiscardingTaskGroup`** (SE-0381) to merge event streams — this is a long-running event loop that runs for the app's lifetime and doesn't collect results. `withDiscardingTaskGroup` prevents memory leaks from accumulated child task results:
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
- [ ] Always set `onTermination` on the merged stream's continuation to cancel child tasks on consumer disconnect

**`any` vs `some` guidance for provider references**: The registry stores `any ProviderAdapter` because it holds a heterogeneous collection of different concrete adapter types. However, within provider-specific code (e.g., inside `ClaudeProviderAdapter`), always use concrete types or `some ProviderAdapter` — reserve `any` for the registry's heterogeneous collection. Start concrete → move to `some` → resort to `any` only when necessary.

### 1.7 Write Core Model Tests

- [ ] Test `SessionPhase` transitions: valid, invalid, terminal state, same-state no-op
- [ ] Test `JSONValue` encoding/decoding round-trips
- [ ] Test `PermissionContext.displaySummary` for various tool inputs
- [ ] Test `ChatHistoryItem` construction and deduplication
- [ ] Use parameterized tests (`@Test(arguments:)`) for transition matrix

---

## Phase 2 — State Management Layer

### 2.1 SessionStore Actor

```
OIState/SessionStore.swift
```

- [ ] Swift `actor` — the single source of truth for all session state
- [ ] Single entry point: `func process(_ event: sending SessionEvent) async` — the `sending` annotation (SE-0430) documents at the type level that the event's ownership is transferred into the actor's isolation domain. This is the canonical boundary where events cross from provider actors into the `SessionStore` actor. Even though `SessionEvent` is currently `Sendable`, `sending` makes the ownership transfer explicit and future-proofs for potential non-Sendable provider extension payloads.
- [ ] Internal state: `private var sessions: [String: SessionState]`
- [ ] Event audit trail: circular buffer array of last 100 events for debugging, using a simple index-wrapping array implementation. **Do not use `InlineArray<100, SessionEvent>`** — `InlineArray` (SE-0452) requires its element type to be stack-allocatable for real benefit, and `SessionEvent` carries `String`s, `Array`s, and nested structs that are heap-allocated. Reserve `InlineArray` for genuinely fixed-size, trivially-copyable element buffers (e.g., small `ProviderID` lookup tables).
- [ ] On each state change, call `publishState()` to broadcast to all subscribers
- [ ] Session state snapshots use standard CoW types. Broadcasting to multiple subscribers creates shared references without copying storage until mutation — efficient by design.

### 2.2 Multi-Subscriber Broadcast

```
OIState/SessionStore+Streaming.swift
```

- [ ] UUID-keyed `AsyncStream` continuations pattern (from claude-island):
  ```swift
  private var continuations: [UUID: AsyncStream<[SessionState]>.Continuation]
  ```
- [ ] `func sessionsStream() -> AsyncStream<[SessionState]>` — registers a new subscriber, immediately yields current state
- [ ] `.bufferingNewest(1)` policy — correct for "latest snapshot" semantics where consumers only need the most recent state
- [ ] `onTermination` set synchronously before the registration Task to avoid race conditions — **always set `onTermination`** on all `AsyncStream` continuations to clean up the UUID entry from the `continuations` dictionary, preventing memory leaks from accumulated dead continuations
- [ ] `publishState()` iterates all continuations, yields sorted sessions

### 2.3 Session Phase Validation & Transitions

```
OIState/SessionStore+Transitions.swift
```

- [ ] Map `ProviderEvent` to `SessionPhase` transitions
- [ ] Validate via `canTransition(to:)` before applying
- [ ] Log invalid transitions with the audit trail
- [ ] Handle edge cases: permission during processing, compacting during any state, ended from any state

### 2.4 Tool Tracking

```
OIState/ToolTracker.swift
OIState/ToolEventProcessor.swift
```

- [ ] `ToolTracker` struct: `inProgress: [String: ToolInProgress]`, `seenIDs: Set<String>`
- [ ] `ToolEventProcessor` — static methods processing tool start/complete events
- [ ] Track tool durations, statuses, nested subagent tools
- [ ] Subagent state machine: active tasks stack, attribute nested tools to parent Task

### 2.5 Periodic Health Check

```
OIState/SessionStore+HealthCheck.swift
```

- [ ] Every 3 seconds, iterate sessions and call provider adapter's `isSessionAlive()`
- [ ] Transition zombie sessions to `.ended`
- [ ] Use a **regular `Task`** (not `Task.detached`) launched from within the `SessionStore` actor — it inherits the actor's isolation, which is exactly what we want for iterating sessions:
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
- [ ] Store the `Task` handle for cancellation support on `stop()`

### 2.6 SessionStore Tests

- [ ] Test event processing for each `SessionEvent` case
- [ ] Test multi-subscriber broadcast: 2+ consumers see same state
- [ ] Test zombie session cleanup
- [ ] Test audit trail ring buffer behavior
- [ ] Test concurrent event processing (use `withTaskGroup` to fire events simultaneously)
- [ ] Use `confirmation` from Swift Testing for async event verification

---

## Phase 3 — Claude Code Provider Adapter

> Build the first concrete provider to validate the architecture end-to-end.

### 3.1 Hook Socket Server

```
OIProviders/Claude/ClaudeHookSocketServer.swift
```

- [ ] Port `HookSocketServer` from claude-island
- [ ] GCD-based Unix domain socket server at `/tmp/open-island-claude.sock`
- [ ] Non-blocking accept via `DispatchSource.makeReadSource`
- [ ] **`@preconcurrency import Dispatch`** at the top of this file — GCD types predate Swift concurrency and will trigger Sendable diagnostics in strict mode. Add a comment: `// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations`
- [ ] `Mutex<PermissionsState>` for permission tracking (Sendable-safe)
- [ ] Permission socket lifecycle: keep client socket open for `PermissionRequest`, 5-minute timeout
- [ ] Emit raw `ClaudeHookEvent` structs to a callback
- [ ] **Always set `onTermination`** on any `AsyncStream` continuations used to bridge GCD callbacks → async streams, to ensure socket cleanup on consumer disconnect
- [ ] **Buffering policy**: use `.bufferingOldest(128)` for the event stream from the socket — events are sequential and order-matters, so dropping the oldest events silently would cause incorrect state reconstruction. `.bufferingOldest` with a generous capacity preserves event ordering under load while bounded memory. Log a warning if the buffer fills (indicates consumer is too slow).

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

- [ ] `ClaudeHookEvent` — raw struct matching the Python script's JSON payload (session_id, cwd, event, status, pid, tty, tool, tool_input, tool_use_id)
- [ ] `ClaudeEventNormalizer` — maps `ClaudeHookEvent` → `ProviderEvent`
  - [ ] Uses `throws(EventNormalizationError)` for closed error domain (see Phase 1.5)
- [ ] Handle all Claude-specific event types: `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `SessionStart`, `SessionEnd`, `PreCompact`, `SubagentStop`

### 3.3 Python Hook Script

```
Resources/Hooks/Claude/open-island-claude-hook.py
```

- [ ] Port `claude-island-state.py` with updated socket path (`/tmp/open-island-claude.sock`)
- [ ] Keep the same protocol: JSON over Unix socket, blocking for permission responses
- [ ] Update the hook event names to match `open-island` naming

### 3.4 Hook Installer

```
OIProviders/Claude/ClaudeHookInstaller.swift
```

- [ ] Port `HookInstaller` logic:
  - [ ] Copy bundled Python script to `~/.claude/hooks/`
  - [ ] Detect Python runtime via `PythonRuntimeDetector`
  - [ ] Update `~/.claude/settings.json` with hook config for all event types
- [ ] Handle deduplication, legacy format migration, uninstallation
- [ ] Make this async with cancellation support
- [ ] Uses `throws(HookInstallError)` for closed error domain (see Phase 1.5)

### 3.5 Claude Conversation Parser

```
OIProviders/Claude/ClaudeConversationParser.swift
```

- [ ] Actor that reads Claude Code's JSONL conversation files incrementally
- [ ] Track `lastFileOffset` per session, detect file truncation
- [ ] Parse user messages, assistant messages (text, tool_use, thinking blocks), tool results
- [ ] Handle `/clear` detection
- [ ] Emit parsed `[ChatHistoryItem]` via `ProviderEvent.chatUpdated`
- [ ] Large file handling: tail-based parsing for files > 10MB
- [ ] The file handle used for incremental reading is another candidate for a `~Copyable` wrapper (see Phase 3.1 pattern) — evaluate whether the ownership model adds value here or if the actor's isolation is sufficient

### 3.6 Claude Provider Adapter (Composition)

```
OIProviders/Claude/ClaudeProviderAdapter.swift
```

- [ ] Actor conforming to `ProviderAdapter`
- [ ] Composes: `ClaudeHookSocketServer` + `ClaudeHookInstaller` + `ClaudeConversationParser`
- [ ] `start()`: install hooks, start socket server, begin file watching. Uses `throws(ProviderStartupError)`.
- [ ] `stop()`: stop socket server, cancel file watchers
- [ ] `events()`: merge socket events + file change events into single `AsyncStream<ProviderEvent>` — **always set `onTermination`** on the merged stream's continuation to cancel internal tasks and close the socket listener when consumers disconnect. Use `.bufferingOldest(128)` to preserve event ordering (same rationale as Phase 3.1).
- [ ] `respondToPermission()`: delegate to socket server's held-open connection
- [ ] `isSessionAlive()`: check PID via `kill(pid, 0)`

### 3.7 Integration Test: Claude Adapter End-to-End

- [ ] Mock socket client sending Claude hook events
- [ ] Verify `ProviderEvent` stream emits correct normalized events
- [ ] Test permission flow: request → response → socket write
- [ ] Test conversation parsing with sample JSONL fixtures

---

## Phase 4 — Window System & Notch Geometry

### 4.1 NotchPanel (NSPanel Subclass)

```
OIUI/Window/NotchPanel.swift
```

- [ ] Borderless, non-activating, transparent floating panel
- [ ] Configuration: `.nonactivatingPanel`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`
- [ ] `canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`, `.ignoresCycle`
- [ ] Level set above menu bar
- [ ] `becomesKeyOnlyIfNeeded = true`
- [ ] If the `OIAppKitBridge` module from Phase 0.7 is feasible, this class lives there with `@preconcurrency import AppKit` confined to that module. Otherwise, use **`@preconcurrency import AppKit`** on this file with a comment: `// @preconcurrency: NSPanel, NSWindow predate Sendable annotations`

### 4.2 PassThroughHostingView

```
OIUI/Window/PassThroughHostingView.swift
```

- [ ] `NSHostingView` subclass overriding `hitTest(_:)`
- [ ] Closed state: returns `nil` for all points (pass-through to menu bar)
- [ ] Opened state: returns `nil` for points outside the panel bounds
- [ ] Dynamic hit rect computed from `NotchViewModel.status`

### 4.3 NotchWindowController

```
OIUI/Window/NotchWindowController.swift
```

- [ ] `NSWindowController` managing panel lifecycle
- [ ] Subscribe to `NotchViewModel.makeStatusStream()` to toggle `ignoresMouseEvents`
- [ ] Opened by notification → don't steal focus (`NSApp.activate` skipped)

### 4.4 NotchGeometry

```
OIWindow/NotchGeometry.swift
```

- [ ] Pure struct with geometry calculations:
  - [ ] `deviceNotchRect` — hardware notch rect in window coordinates
  - [ ] `screenRect`, `windowHeight` (fixed 750px)
  - [ ] `isPointInNotch(_:)` with ±10px/±5px padding
  - [ ] `isPointOutsidePanel(_:, size:)` for click-outside dismiss
- [ ] `NSScreen` extensions: `notchSize`, `hasPhysicalNotch`, `isBuiltinDisplay`, `builtin`

### 4.5 NotchShape (Custom SwiftUI Shape)

```
OIWindow/NotchShape.swift
```

- [ ] Quadratic Bézier curve path drawing the notch outline
- [ ] Animatable `topCornerRadius` and `bottomCornerRadius` via `AnimatablePair`
- [ ] Closed radii: top 6, bottom 14
- [ ] Opened radii: top 19, bottom 24

### 4.6 WindowManager & ScreenObserver

```
OIUI/Window/WindowManager.swift
OIUI/Window/ScreenObserver.swift
```

- [ ] `WindowManager`: creates `NotchWindowController` attached to selected screen
- [ ] `ScreenObserver`: monitors `didChangeScreenParametersNotification` with 500ms debounce
- [ ] `ScreenSelector`: automatic (built-in display) or user-selected screen, persisted as `ScreenIdentifier`

### 4.7 Window System Tests

- [ ] Test `NotchGeometry` hit testing with known coordinates
- [ ] Test `NotchShape` path generation (snapshot or bounds checking)
- [ ] Test screen selector fallback logic

---

## Phase 5 — NotchViewModel & Core UI

### 5.1 NotchViewModel

```
OIUI/ViewModels/NotchViewModel.swift
```

- [ ] `@Observable` class managing:
  - [ ] `status: NotchStatus` (`.closed`, `.opened`, `.popping`)
  - [ ] `contentType: NotchContentType` (`.instances`, `.chat(SessionState)`, `.menu`)
  - [ ] `openReason: NotchOpenReason` (`.hover`, `.notification`, `.boot`, `.unknown`)
  - [ ] `geometry: NotchGeometry`
  - [ ] `layoutEngine: ModuleLayoutEngine`
- [ ] Computed `openedSize` varying by content type
- [ ] `makeStatusStream()` for window controller subscription
- [ ] Methods: `notchOpen(reason:)`, `notchClose()`, `switchContent(_:)`

### 5.2 Event Monitors

```
OIUI/Events/EventMonitor.swift
OIUI/Events/EventMonitors.swift
```

- [ ] `NSEvent` global monitor wrapper
- [ ] Mouse position tracking for hover detection
- [ ] Click-outside detection for dismissal
- [ ] Keyboard shortcut handling

### 5.3 NotchView (Root SwiftUI View)

```
OIUI/Views/NotchView.swift
```

- [ ] Root `ZStack` with `NotchShape` clip mask and shadow
- [ ] Header row (always visible): left modules + notch spacer + right modules
- [ ] Content view (when opened): switches on `contentType`
- [ ] Reactive states: `isVisible`, `isHovering`, `isBouncing`
- [ ] Animations:
  - [ ] Open: `.spring(response: 0.42, dampingFraction: 0.8)`
  - [ ] Close: `.spring(response: 0.45, dampingFraction: 1.0)`
  - [ ] Content transitions: `.scale.combined(with: .opacity)`
- [ ] Boot animation: open briefly after 0.3s delay, close after 1.0s
- [ ] Include `#Preview` blocks in every SwiftUI view file. Create preview helpers providing mock `SessionState`, `NotchViewModel`, and `ModuleRenderContext` for self-contained previews. `#Preview` replaces the legacy `PreviewProvider` protocol.

### 5.4 NotchHeaderView

```
OIUI/Views/NotchHeaderView.swift
```

- [ ] Gear icon → settings
- [ ] Mascot icon (provider-aware — show relevant icon based on active sessions)
- [ ] Activity spinner with `matchedGeometryEffect` between closed/opened states
- [ ] Title text adapting to content type
- [ ] Close button (animated chevron)

### 5.5 Basic Instances View (Placeholder)

```
OIUI/Views/InstancesView.swift
```

- [ ] List of active sessions from `SessionMonitor`
- [ ] Each row shows: provider icon, project name, phase indicator, elapsed time
- [ ] Tap to open chat view for that session
- [ ] Empty state when no sessions active

### 5.6 SessionMonitor (UI Bridge)

```
OIUI/ViewModels/SessionMonitor.swift
```

- [ ] `@Observable` class on MainActor
- [ ] Subscribes to `SessionStore.sessionsStream()`
- [ ] Updates `instances: [SessionState]` array (filters out ended sessions)
- [ ] Convenience methods: `approvePermission()`, `denyPermission()`, `archiveSession()`
- [ ] Bridges provider registry for permission responses

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
- [ ] `ModuleVisibilityContext` — struct with `isProcessing`, `hasPendingPermission`, `hasWaitingForInput`, provider info
- [ ] `ModuleRenderContext` — struct with animation namespace, color settings, etc.

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

- [ ] `MascotModule` replaces `ClawdModule` — shows provider-appropriate icon (crab for Claude, diamond for Codex, etc.), or a generic icon when multi-provider sessions are active
- [ ] Each module is a small struct conforming to `NotchModule`

### 6.5 Module Layout Persistence

```
OIModules/ModuleLayoutConfig.swift
```

- [ ] `Codable` struct persisted to `UserDefaults`
- [ ] Stores per-module: side, order overrides
- [ ] Allows user customization of module arrangement

### 6.6 Module System Tests

- [ ] Test layout engine with various module visibility combinations
- [ ] Test symmetric width calculation
- [ ] Test config persistence round-trip

---

## Phase 7 — Chat View & Markdown Rendering

### 7.1 ChatView

```
OIUI/Views/ChatView.swift
```

- [ ] Scrollable chat history for a single session
- [ ] Provider-aware styling (accent colors, icon)
- [ ] Message types: user bubbles, assistant text, tool calls (expandable), thinking (collapsible), interrupted markers
- [ ] Auto-scroll to bottom on new messages
- [ ] Approval bar at bottom when session is `.waitingForApproval`

### 7.2 Approval Bar

```
OIUI/Views/ApprovalBarView.swift
```

- [ ] Shows tool name and summary from `PermissionContext.displaySummary`
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
  - [ ] Duration badge
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

### 8.1 Codex Provider Adapter

```
OIProviders/Codex/CodexProviderAdapter.swift
OIProviders/Codex/CodexEventSource.swift
OIProviders/Codex/CodexEventNormalizer.swift
```

- [ ] Research Codex CLI's event/hook mechanism (file-based, API, or stdout parsing)
- [ ] Implement appropriate event source (file watcher, socket, or log tailer)
- [ ] Normalize Codex-specific events → `ProviderEvent`
- [ ] Implement `respondToPermission()` via Codex's approval mechanism
- [ ] Register in `ProviderRegistry`

### 8.2 Gemini CLI Provider Adapter

```
OIProviders/GeminiCLI/GeminiCLIProviderAdapter.swift
OIProviders/GeminiCLI/GeminiCLIEventSource.swift
OIProviders/GeminiCLI/GeminiCLIEventNormalizer.swift
```

- [ ] Research Gemini CLI's monitoring capabilities
- [ ] Implement event source appropriate to Gemini CLI's architecture
- [ ] Normalize events → `ProviderEvent`
- [ ] Handle permission model (if applicable)

### 8.3 OpenCode Provider Adapter

```
OIProviders/OpenCode/OpenCodeProviderAdapter.swift
OIProviders/OpenCode/OpenCodeEventSource.swift
OIProviders/OpenCode/OpenCodeEventNormalizer.swift
```

- [ ] Research OpenCode's hook/event system
- [ ] Implement event source
- [ ] Normalize events → `ProviderEvent`
- [ ] Handle permissions

### 8.4 Provider Adapter Test Suite

- [ ] Shared conformance tests that run against ALL provider adapters
- [ ] Use parameterized tests:
  ```swift
  @Test("Provider emits session start", arguments: ProviderID.allCases)
  func sessionStart(provider: ProviderID) async { ... }
  ```
- [ ] Mock event sources for deterministic testing
- [ ] Test permission round-trips per provider

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
- [ ] Per-provider settings namespace (e.g., `claude.hookPath`, `codex.logDirectory`)
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
- [ ] Per-provider configuration (expandable sub-sections)
- [ ] Module layout customization
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

### 11.3 Single-Instance Check

```
OICore/App/SingleInstanceGuard.swift
```

- [ ] Check `NSWorkspace.shared.runningApplications` for existing instance
- [ ] Activate existing instance and exit if found

---

## Phase 12 — Polish, Edge Cases & Performance

### 12.1 Interrupt Detection

- [ ] Per-provider interrupt detection strategy
- [ ] Claude: `JSONLInterruptWatcher` monitoring for `^C` patterns
- [ ] Others: provider-specific mechanisms
- [ ] Fire `.interruptDetected` through `SessionStore`

### 12.2 Context Compaction Handling

- [ ] Handle `.compacting` phase transitions per provider
- [ ] UI indicator during compaction
- [ ] Resume to correct phase after compaction completes

### 12.3 Subagent / Nested Tool Support

- [ ] Full subagent state tracking: `SubagentState` with active tasks stack
- [ ] Attribute nested tool calls to parent Task
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
- [ ] Only for providers that expose quota APIs

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
- [ ] DocC comments on all `SessionEvent` cases
- [ ] DocC comments on `SessionPhase` transition rules

### 13.3 Example Provider Skeleton

```
OIProviders/Example/ExampleProviderAdapter.swift
```

- [ ] Minimal working provider adapter that emits fake events on a timer
- [ ] Serves as a template and integration test fixture
- [ ] Documented line-by-line for onboarding new contributors

### 13.4 README & Contributing Guide

- [ ] `README.md` — project overview, screenshots, install instructions
- [ ] `CONTRIBUTING.md` — development setup, PR process, testing expectations:
  - [ ] Note about `organizeDeclarations` + `nonisolated` gotcha and `// swiftformat:disable all` guards
  - [ ] Note about forward-scan trailing closure matching (SE-0286) — the first trailing closure label is dropped in Swift 6; use labeled trailing closures for all subsequent closure parameters; avoid trailing closure syntax in `guard` conditions
  - [ ] Note about `AsyncStream` buffering policy conventions (state snapshots → `.bufferingNewest(1)`, event streams → `.bufferingOldest(N)`)
  - [ ] One primary type per file (`NotchViewModel.swift`). Extensions: `TypeName+Feature.swift` (`SessionStore+Streaming.swift`).
- [ ] `PROVIDERS.md` — status matrix of supported providers and their capabilities

---

## Dependency Summary

| Dependency | Purpose | Phase |
|---|---|---|
| swift-markdown (Apple) | Markdown rendering in chat view (pure Swift, no OS runtime dependency) | 7 |
| Sparkle | Auto-update framework (note: may need `@retroactive` conformances for Sendable bridging) | 11 |
| swift-syntax (Apple) | If adding macro-based features | Future |

> **Design principle**: minimize external dependencies. Use Foundation, SwiftUI, AppKit, and system frameworks wherever possible. No Combine — use `AsyncStream` throughout.

---

## Swift 6.2 Patterns Checklist

Applied throughout all phases:

### Approachable Concurrency (Phase 0.6 — the three pillars)

- [ ] **Pillar 1**: `MainActor` default isolation for app target only; `nonisolated` default for library targets (SE-0466)
- [ ] **Pillar 2**: `NonisolatedNonsendingByDefault` upcoming feature enabled on all targets — async functions stay on caller's actor (SE-0461)
- [ ] **Pillar 3**: `InferIsolatedConformances` upcoming feature enabled on all targets — protocol conformances in isolated contexts are automatically inferred as isolated (SE-0470)
- [ ] `@concurrent` used only on functions that genuinely need off-actor execution — CPU-bound work, blocking I/O, subprocess spawning (SE-0461 usage guideline, not a separate pillar)
- [ ] `CONCURRENCY.md` documenting the project's concurrency contract, including forward-scan trailing closure guidance (SE-0286)

### Data-Race Safety

- [ ] Verify model types and their extensions remain `nonisolated` (the default in library targets) — do not add explicit `nonisolated` annotation as it is redundant; only annotate explicitly when overriding `MainActor` default in the app target
- [ ] `Sendable` explicitly on all `package`/`public` value types; compiler-synthesized for internal types
- [ ] `sending` parameter and result annotations (SE-0430) used at actor isolation boundaries where non-Sendable values are transferred. Key sites include `SessionStore.process(_:)`, any actor method accepting ownership of event payloads, and factory functions returning values for cross-isolation consumption. Note: `Task.init` closures use `sending` automatically in Swift 6.
- [ ] Region-based isolation (SE-0414) leveraged to avoid unnecessary `Sendable` conformances
- [ ] `Mutex<T>` from Synchronization framework for shared mutable class state
- [ ] `actor` for serialized state management (`SessionStore`, parsers, API services)
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
- [ ] `BitwiseCopyable` on simple `package`/`public` leaf enums with no reference types — `PermissionDecision`, `ModuleSide`, `ToolStatus` (SE-0426). **Not** on `ProviderID` (has `String` raw values, which are not `BitwiseCopyable`)
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
- [ ] `.swiftformat` adapted with correct `--exclude` paths, `--swiftversion 6.2`, `OI` in `--acronyms`
- [ ] `.swiftlint.yml` adapted with correct `included:` paths, `single_test_class` disabled, custom rules added and verified for false positives
- [ ] `prek run --all-files` passes cleanly on initial project skeleton (including custom rule verification)
- [ ] `Makefile` with `format`, `lint`, `test`, `build`, `clean`, `install-hooks` targets
