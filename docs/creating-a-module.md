# Creating a Notch Module

This guide walks through creating a custom module for the Open Island closed-state notch header. Modules are self-contained UI components that appear alongside the notch when the overlay is collapsed.

## Architecture Overview

The module system consists of four core types:

| Type | File | Purpose |
|------|------|---------|
| `NotchModule` | `OpenIslandKit/Sources/OIModules/NotchModule.swift` | Protocol every module conforms to |
| `ModuleRegistry` | `OpenIslandKit/Sources/OIModules/ModuleRegistry.swift` | Central registry holding all modules |
| `ModuleLayoutConfig` | `OpenIslandKit/Sources/OIModules/ModuleLayoutConfig.swift` | User-customizable side, order, and visibility overrides |
| `ModuleLayoutEngine` | `OpenIslandKit/Sources/OIModules/ModuleLayoutEngine.swift` | Pure-computation engine that positions modules |

Two context types feed data into modules:

- **`ModuleVisibilityContext`** — aggregated session state (is processing? pending permission? active providers?) used to decide whether a module is visible.
- **`ModuleRenderContext`** — rendering parameters (animation namespace, accent color, highlight state, active provider count) passed when building the view.

## Step 1: Create the Module File

Add a new Swift file in `OpenIslandKit/Sources/OIModules/BuiltIn/`. Name it after your module: `MyCustomModule.swift`.

```swift
package import SwiftUI

// MARK: - MyCustomModule

/// One-line description of what this module shows.
///
/// Longer explanation of when it's visible and what it displays.
package struct MyCustomModule: NotchModule {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    package let id = "my-custom"
    package let defaultSide = ModuleSide.left
    package let defaultOrder = 2
    package let showInExpandedHeader = false

    package func isVisible(context: ModuleVisibilityContext) -> Bool {
        // Return true when this module should appear
        !context.activeProviders.isEmpty
    }

    package func preferredWidth() -> CGFloat {
        20
    }

    @MainActor
    package func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(self.body(context: context))
    }

    // MARK: Private

    @MainActor
    private func body(context: ModuleRenderContext) -> some View {
        Image(systemName: "star.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(context.accentColor)
    }
}
```

## Step 2: Implement the NotchModule Protocol

Every module must satisfy these requirements:

### Required Properties

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique identifier. Used for registry deduplication, layout persistence, and hiding. Use a kebab-case string (e.g., `"my-custom"`). |
| `defaultSide` | `ModuleSide` | `.left` or `.right` of the notch. The user can override this via `ModuleLayoutConfig`. |
| `defaultOrder` | `Int` | Sort order within its side. Lower values are laid out first from the outer edge inward. The user can override this. |
| `showInExpandedHeader` | `Bool` | Whether this module also appears in the expanded (opened) notch header. Most modules set this to `false`. |

### Required Methods

#### `isVisible(context:) -> Bool`

Determines whether the module appears given the current session state. The `ModuleVisibilityContext` provides:

```swift
package struct ModuleVisibilityContext: Sendable, Equatable {
    /// Whether any active session is currently processing.
    package let isProcessing: Bool

    /// Whether any active session has a pending permission request.
    package let hasPendingPermission: Bool

    /// Whether any active session is waiting for user input.
    package let hasWaitingForInput: Bool

    /// Set of providers with active sessions.
    package let activeProviders: Set<ProviderID>

    /// Per-provider activity summaries for provider-aware module decisions.
    package let aggregateProviderState: [ProviderID: ProviderActivitySummary]
}
```

Common visibility patterns from built-in modules:

```swift
// Always visible
func isVisible(context: ModuleVisibilityContext) -> Bool { true }

// Only during processing
func isVisible(context: ModuleVisibilityContext) -> Bool { context.isProcessing }

// Only when idle with active sessions
func isVisible(context: ModuleVisibilityContext) -> Bool {
    !context.isProcessing && !context.activeProviders.isEmpty
}

// Only when a permission is pending
func isVisible(context: ModuleVisibilityContext) -> Bool { context.hasPendingPermission }
```

#### `preferredWidth() -> CGFloat`

Returns the desired width in points. The layout engine uses this to compute module positions and the total notch expansion width. Typical values:

- **20 pt** — small icon (spinner, checkmark, dots)
- **22 pt** — ring/badge (token rings)
- **40 pt** — text content (timer)

#### `makeBody(context:) -> AnyView`

Builds the module's SwiftUI view. Must be `@MainActor`-isolated because `ModuleRenderContext` contains non-Sendable SwiftUI types.

**Important:** The return type is `AnyView`, not `some View`. This is required because modules are stored heterogeneously as `any NotchModule` in the registry. The recommended pattern is to delegate to a private `@ViewBuilder` method and wrap:

```swift
@MainActor
package func makeBody(context: ModuleRenderContext) -> AnyView {
    AnyView(self.body(context: context))
}

@MainActor
private func body(context: ModuleRenderContext) -> some View {
    // Your view hierarchy here
}
```

The `ModuleRenderContext` provides rendering parameters:

```swift
@MainActor
package struct ModuleRenderContext {
    /// Animation namespace for matched geometry effects across modules.
    package let animationNamespace: Namespace.ID

    /// Accent color derived from the active provider or system theme.
    package let accentColor: Color

    /// Whether this module's area is visually highlighted (e.g., during hover).
    package let isHighlighted: Bool

    /// Number of active providers.
    package let activeProviderCount: Int
}
```

Use `context.accentColor` for foreground styling to ensure visual consistency across all modules.

## Step 3: Register the Module

Modules are registered with `ModuleRegistry` at runtime. Create a `ModuleRegistry` instance, then call `register(_:)` for each module:

```swift
let registry = ModuleRegistry()
registry.register(MyCustomModule())
registry.register(ActivitySpinnerModule())
registry.register(SessionDotsModule())
```

`ModuleRegistry` is `@Observable` and `@MainActor`-isolated. Key behaviors:

- **Deduplication** — registering a module with an `id` that already exists is silently ignored.
- **Layout reconciliation** — after registering all modules, call `applyPersistedLayout()` to load user-customized positions from `UserDefaults` and reconcile against the current set of modules.

```swift
// After all modules are registered:
registry.applyPersistedLayout()
```

The registry is injected into `NotchViewModel`, which drives the header layout:

```swift
let viewModel = NotchViewModel(geometry: geometry, registry: registry)
```

## Step 4: User-Customizable Layout

Users can rearrange modules via `ModuleLayoutConfig`. Each module gets a `ModuleLayoutEntry` that can override its default side, order, and visibility:

```swift
package struct ModuleLayoutEntry: Codable, Sendable, Equatable {
    package let moduleID: String
    package var side: ModuleSide     // overrides defaultSide
    package var order: Int           // overrides defaultOrder
    package var isHidden: Bool       // user can hide modules
}
```

The layout engine uses `ModuleLayoutConfig` when computing positions:

- `effectiveSide(for:)` returns the user's chosen side, falling back to the module's `defaultSide`.
- `effectiveOrder(for:)` returns the user's chosen order, falling back to `defaultOrder`.
- `isHidden(_:)` returns whether the user has hidden the module.

When a new module is registered that has no persisted entry, `reconcile(with:)` adds it at its default position. Stale entries for unregistered modules are pruned.

Your module needs no special code to support this — it works automatically through the registry.

## Step 5: Add a Preview

Follow the existing preview pattern. Create a private preview struct that provides a `@Namespace` for the render context:

```swift
// MARK: - Preview

#Preview("MyCustomModule") {
    _MyCustomPreview()
        .padding()
        .background(.black)
}

// MARK: - _MyCustomPreview

@MainActor
private struct _MyCustomPreview: View {
    // MARK: Internal

    var body: some View {
        MyCustomModule()
            .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
    }

    // MARK: Private

    @Namespace private var ns
}
```

For modules with multiple states, show them side by side:

```swift
#Preview("MyCustomModule") {
    HStack(spacing: 16) {
        _MyCustomPreviewItem(/* state A */, label: "State A")
        _MyCustomPreviewItem(/* state B */, label: "State B")
    }
    .padding()
    .background(.black)
}
```

## Step 6: Write Tests

Add tests in `OpenIslandKit/Tests/OIModulesTests/`. Use Swift Testing (`import Testing`), not XCTest.

### Visibility Tests

```swift
import Testing
@testable import OIModules

struct MyCustomModuleTests {
    @Test
    func `Visible when active providers exist`() {
        let module = MyCustomModule()
        let context = ModuleVisibilityContext(activeProviders: [.claude])
        #expect(module.isVisible(context: context))
    }

    @Test
    func `Hidden when no active providers`() {
        let module = MyCustomModule()
        let context = ModuleVisibilityContext()
        #expect(!module.isVisible(context: context))
    }
}
```

### Registry Integration Test

```swift
@MainActor
@Test
func `Module registers with unique ID`() {
    let registry = ModuleRegistry()
    registry.register(MyCustomModule())
    #expect(registry.allModules.count == 1)
    #expect(registry.allModules[0].id == "my-custom")
}
```

## Built-in Module Reference

These existing modules serve as working examples:

| Module | File | Side | Description |
|--------|------|------|-------------|
| `MascotModule` | `BuiltIn/MascotModule.swift` | Left | Provider icon; always visible. Takes constructor parameter for active providers. |
| `PermissionIndicatorModule` | `BuiltIn/PermissionIndicatorModule.swift` | Left | Exclamation mark; visible during pending permissions. |
| `ActivitySpinnerModule` | `BuiltIn/ActivitySpinnerModule.swift` | Right | Spinner; visible during processing. Simplest module — good starting point. |
| `ReadyCheckmarkModule` | `BuiltIn/ReadyCheckmarkModule.swift` | Right | Checkmark; visible when idle with active sessions. |
| `SessionDotsModule` | `BuiltIn/SessionDotsModule.swift` | Right | Dot per provider; visible with active providers. |
| `TimerModule` | `BuiltIn/TimerModule.swift` | Right | Elapsed time display; takes optional `startDate`. Wider (40pt). |
| `TokenRingsModule` | `BuiltIn/TokenRingsModule.swift` | Right | Token usage ring; takes `totalTokens` and optional `quotaFraction`. Shows computed properties and custom drawing. |

## Layout Geometry

The `ModuleLayoutEngine` positions modules symmetrically around the notch:

```
◄── symmetricSideWidth ──►◄── device notch ──►◄── symmetricSideWidth ──►
┌─────────────────────────┬──────────────────────┬─────────────────────────┐
│  6pt │ mod │ 8pt │ mod  │                      │ mod │ 8pt │ mod  │ 6pt  │
└─────────────────────────┴──────────────────────┴─────────────────────────┘
```

- **Outer edge inset:** 6pt from the expansion zone boundary to the first module.
- **Inter-module spacing:** 8pt between adjacent modules on the same side.
- **Symmetry:** Both sides are padded to the same width (`max(left, right)`) so the notch stays centered.

## Checklist

Before submitting your module:

- [ ] Struct conforms to `NotchModule` with a unique `id`
- [ ] `isVisible(context:)` returns `true` only when meaningful content exists
- [ ] `preferredWidth()` returns an appropriate value for your content
- [ ] `makeBody(context:)` uses `context.accentColor` for consistent styling
- [ ] Module is registered in the `ModuleRegistry`
- [ ] Preview renders correctly on a dark background
- [ ] Visibility tests cover the expected show/hide conditions
