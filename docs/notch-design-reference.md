# Notch Design Reference — Lessons from Claude Island

> High-level architectural guidance for Open Island's window system, module
> system, and expanded-view design. Derived from the Claude Island codebase
> (including PR 78's modular notch overhaul and PR 82's auto-expand
> preference). No code examples — this document describes *what* to build
> and *why*, not *how* to write it line by line.

---

## 1. Window Stack: Four Layers with Clear Responsibilities

The notch overlay is not a single view; it is a four-layer stack where each
layer owns exactly one concern.

### 1.1 The Panel (NSPanel subclass)

A borderless, non-activating, transparent floating panel that sits above
every other window — including the menu bar. It joins all Spaces, stays
stationary during Space transitions, and never appears in the window
switcher. It is never the main window.

The panel starts with `ignoresMouseEvents = true` so that menu-bar clicks,
Spotlight invocations, and drag operations pass through as if the panel
does not exist. Mouse event acceptance is toggled dynamically by the
window controller based on notch status.

### 1.2 The Host View (NSHostingView subclass)

A pass-through hosting view that overrides hit-testing. In the closed
state, *no* point is considered a hit — the entire panel surface is
transparent to interaction. In the opened state, only points inside the
computed panel bounds are accepted; everything else falls through.

The hit-test rect is recomputed whenever the notch status or panel size
changes. The hosting view does not decide *what* the hit rect is; it
asks the view model for the current panel dimensions and translates those
into a rect that the `hitTest(_:)` override can evaluate.

### 1.3 The Window Controller (NSWindowController)

Owns the lifecycle of the panel and bridges the view model's state stream
to AppKit-level window behaviour. It subscribes to the view model's status
stream and reacts:

- **Opened**: enables mouse events on the panel so that buttons, scroll
  views, and interactive controls inside the notch work. Conditionally
  activates the app and makes the panel key — but *only* when the user
  explicitly opened the notch (click or hover), not when the notch was
  opened programmatically by a notification. Stealing focus from the
  user's current app on a notification is a poor UX pattern.
- **Closed / Popping**: disables mouse events so the panel goes back to
  full pass-through.

The controller also manages the boot animation: a brief open-then-close
sequence on first launch that teaches the user where the notch is.

### 1.4 Click-Through Re-posting

When the panel is in the opened state and the user clicks *outside* the
panel content (but still within the full-screen panel window), the click
must reach the window or app behind the panel. The panel achieves this by
intercepting the event in `sendEvent(_:)`, checking whether the content
view's hit test returns nil, and if so, temporarily disabling mouse events
and re-posting the click as a CGEvent at the correct screen coordinates
(converting from AppKit's bottom-up coordinate system to CoreGraphics'
top-down system).

Without this mechanism, clicking the menu bar or another app's window
while the notch is expanded would silently swallow the click.

---

## 2. Geometry: A Pure, Testable Value Type

All coordinate math lives in a single `Sendable` struct that has no
dependency on AppKit, SwiftUI, or any observable state. It takes the
device notch rect, the screen rect, and the window height at init time
and exposes pure functions:

- **Is a point in the notch area?** With padding (roughly ±10pt
  horizontal, ±5pt vertical) so the interaction target is larger than the
  visual notch.
- **Is a point inside the opened panel?** Given the current panel size.
- **Is a point outside the opened panel?** The inverse, used for
  click-outside dismissal.

The geometry struct also provides the notch rect in screen coordinates
(for global mouse-position hit testing) and the opened panel rect in
screen coordinates (for the same purpose). These screen-coordinate rects
account for the screen origin, which differs between the built-in display
and external monitors.

Keeping geometry as a pure value type means it is trivially testable with
known coordinates — no mocking of screens or windows required.

---

## 3. The Notch Shape: Animatable Quadratic Curves

The visual outline of the notch is a custom SwiftUI `Shape` that draws
a path using quadratic Bézier curves. It has two animatable parameters:
a top corner radius and a bottom corner radius. The closed state uses
tight corners (small radii) that hug the hardware notch; the opened
state uses larger, rounder corners that give the expanded panel a
softer appearance.

Both radii are combined into an `AnimatablePair` so that SwiftUI can
interpolate between the closed and opened shapes smoothly. The shape
itself knows nothing about state — it is parameterised purely by the
two radii. The view layer decides which radii to use based on the
current notch status.

---

## 4. View Model: An @Observable State Machine

The view model is the central coordination point. It is `@Observable`
and `@MainActor`-isolated (not `ObservableObject`) and manages:

### 4.1 Status (the state machine)

Three states: **closed**, **opened**, **popping**. "Popping" is a brief
intermediate state used for bounce animations — the notch visually
"pops" down and then returns to closed. Transitions are explicit methods
(`notchOpen(reason:)`, `notchClose()`, `notchPop()`, `notchUnpop()`).

The open reason (click, hover, notification, boot) is tracked so that
downstream behaviour can vary. Notification opens should not steal focus.
Boot opens auto-close after a short delay.

### 4.2 Content Type (what the expanded view shows)

An enum with distinct cases for the different content modes: session
list, settings menu, and per-session chat detail. The view model manages
transitions between content types and preserves state across
open/close cycles (e.g., remembering which chat was open so it can be
restored on the next open).

### 4.3 Opened Size (dynamic, content-aware)

The expanded panel is not a fixed size. Each content type computes its
own preferred size, and some content types have dynamically varying
heights — for instance, a settings menu with expandable picker rows
changes height as the user opens and closes selectors. The view model
tracks a selector update token that triggers view re-computation when
any selector's expansion state changes.

This dynamic sizing is what makes the expanded settings view (the
auto-expand preference and similar rows) feel native rather than
cramped or wasteful.

### 4.4 Event Routing (global mouse monitors)

The view model owns the interaction model: global `NSEvent` monitors
for mouse movement (throttled to ~50ms to avoid flooding), mouse-down
(for click detection), and mouse drag. These monitors feed into the
geometry struct's hit-testing functions to determine hover state
and dismiss-on-click-outside behaviour.

When the notch is opened and the user clicks outside the panel, the
view model closes the notch *and* re-posts the click to the underlying
window so the user's intended interaction is not lost.

### 4.5 Status Stream

The view model exposes a factory method that returns an `AsyncStream`
of status changes. This is consumed by the window controller (to
toggle `ignoresMouseEvents`) and by any other non-SwiftUI component
that needs to react to state changes. The stream is single-consumer
by convention — calling the factory again finishes the previous stream.

---

## 5. The Module System: PR 78's Modular Notch

The closed-state notch is not a monolithic view. It is composed of
self-contained modules arranged in a left-right layout around the
physical notch.

### 5.1 The Module Protocol

Each module declares:

- **Identity**: a stable string ID.
- **Default placement**: which side (left or right) and what order.
- **Visibility logic**: a pure function that takes a context describing
  the current session state (is anything processing? is a permission
  pending? is the user being asked for input?) and returns whether the
  module should be visible.
- **Preferred width**: how much horizontal space the module needs.
- **Body**: a SwiftUI view factory.
- **Expanded-header flag**: whether the module should also appear in
  the opened state's header row (not all closed-state modules make
  sense when expanded).

### 5.2 The Layout Engine

The engine takes the registered modules, the current session state,
and the physical notch dimensions, and computes a layout: which modules
are visible on each side, their widths, the total expansion width, and
a symmetric side width (the max of left and right, so both sides expand
equally for visual balance).

The engine is also the single source of truth for spacing constants
(inter-module spacing, side inset, outer edge inset, shape edge margin).
Both the SwiftUI view layer and the AppKit hit-test computation must use
the same engine to avoid drift between visual bounds and interaction
bounds.

### 5.3 The Registry

A singleton `@Observable`, `@MainActor`-isolated class that holds all
registered modules. It provides lookup by ID and bulk session-state updates (some modules, like
session dots, need to know the current session list to compute their
visibility and width).

The registry supports dynamic registration, which is important for a
provider-agnostic app — providers can contribute custom modules at
runtime.

### 5.4 Layout Persistence

The user's module arrangement (which modules are on which side, in
what order, and which are hidden) is stored as a `Codable` struct in
UserDefaults. On launch, the engine loads the persisted config, prunes
any module IDs that no longer exist in the registry, and adds any
newly registered modules at their default positions.

### 5.5 Layout Settings UI

A three-column drag-and-drop interface (Left, Right, Hidden) lets
the user rearrange modules. Each column is a drop destination; modules
are draggable between columns. Visual feedback (insertion indicators,
highlighted drop zones) guides the interaction. A reset-to-defaults
button restores the factory layout.

---

## 6. The Expanded View: Content Switching with Preserved State

When the notch opens, the content area below the header row shows one
of several content views, determined by the view model's content type.

### 6.1 Transition Animations

Content insertion uses a combined scale-from-top and opacity animation;
content removal uses a fast opacity fade. These are asymmetric
transitions — the entry feels expansive while the exit feels snappy.

The container itself animates width and height changes smoothly so that
switching between content types (e.g., from the session list to the
settings menu, which may be wider or taller) does not jump.

### 6.2 The Header Row

Always visible in both closed and opened states. In the closed state,
it contains the module layout (left modules, notch spacer, right
modules). In the opened state, it shows a subset of the modules
(those with `showInExpandedHeader = true`) plus a menu toggle button
and, depending on the content type, a back button or close button.

The header row's height adapts: in the closed state it matches the
physical notch height; in the opened state it is a fixed comfortable
height for interactive elements.

### 6.3 Settings Menu

A scrollable list of setting rows. Each row is either a toggle, a
picker with an expandable inline selector, or a navigation row that
pushes a sub-view (like the module layout settings). Expandable picker
rows animate their appearance with a combined opacity and vertical
slide.

The menu dynamically contributes to the view model's `openedSize`
calculation: each expanded picker adds its picker height to the total
panel height, so the panel grows and shrinks as the user opens and
closes selectors. This avoids both fixed-size overflow scrolling and
wasteful empty space.

### 6.4 Auto-Expand Preference

A boolean preference (default off) that controls whether the notch
should auto-open when a session needs attention (permission request,
waiting for input) and the user's terminal is not visible on the
current Space.

When enabled, the notch opens with reason `.notification`, which
means the window controller skips focus activation — the notch
appears as an unobtrusive overlay without stealing the user's
keyboard focus.

The auto-expand check also considers whether the terminal is
frontmost, visible, or occluded, using accessibility APIs and window
list queries. The detection is conservative: if in doubt, don't
auto-expand.

---

## 7. Notification and Attention System

When a session transitions to a state that needs user attention, several
things happen in parallel:

- **Bounce animation**: a brief spring-based vertical displacement
  of the closed notch, drawing the eye without being disruptive.
- **Notification sound**: an `NSSound` plays if configured, with a
  suppression system that skips the sound when the user is already
  looking at the terminal (three modes: never suppress, suppress when
  terminal is focused, suppress when terminal is visible).
- **Auto-expand**: if enabled and the terminal is not visible, the
  notch opens programmatically.

These are coordinated through an `@Observable`, `@MainActor`-isolated
activity coordinator singleton that manages the expanding-activity state
and schedules auto-hide timers.

---

## 8. Data Flow: From Hook Event to Pixel

The full pipeline, high level:

1. **External source** (CLI tool) emits an event.
2. **Transport layer** (socket server, file watcher, SSE client)
   receives the raw data.
3. **Normaliser** converts provider-specific event formats into a
   canonical internal event type.
4. **State store** (actor) processes the event through a strict state
   machine with validated transitions, then broadcasts the new state
   to all subscribers via UUID-keyed `AsyncStream` continuations.
5. **Session monitor** (`@Observable`, MainActor) subscribes to the
   state store's stream and mirrors the data into properties that
   SwiftUI can observe.
6. **SwiftUI views** react to property changes through `@Observable`'s
   per-property tracking — only views that read a changed property
   re-render.

Permission approvals flow in the reverse direction: SwiftUI button
action → session monitor method → transport layer writes the
decision back to the external source.

### 8.1 AsyncStream Patterns

Three patterns recur throughout:

- **Multi-subscriber broadcast**: the state store uses a dictionary
  of UUID-keyed continuations. Each subscriber gets an independent
  stream. Current state is yielded immediately on subscription.
  `onTermination` removes the continuation from the dictionary.
  Buffering policy is `.bufferingNewest(1)` so slow consumers
  always see the latest state.

- **Single-consumer stream**: view models and event monitors
  expose a factory method that creates a stream with a single
  continuation. Calling the factory again finishes the previous
  stream to prevent leaks.

- **Void signal streams**: used to signal "something happened"
  without carrying data (e.g., mouse-down events). The yield call
  must explicitly discard the return value to disambiguate the
  overload.

---

## 9. Recommendations for Open Island

The implementation plan (Phases 4–6, 9) already aligns well with the
patterns above. The following areas deserve additional attention.

### 9.1 Click-Through Re-posting (Phase 4.1)

The plan should explicitly call out the `sendEvent(_:)` override and
CGEvent re-posting mechanism. Without it, clicks on the menu bar
while the notch is expanded are silently swallowed. This is a subtle
but critical UX issue that is easy to miss in initial implementation.

### 9.2 Conditional Focus per Open Reason (Phase 4.3)

The window controller must differentiate between user-initiated opens
(click, hover) and programmatic opens (notification, boot). Only
user-initiated opens should activate the app and make the panel key.
Programmatic opens should leave the user's focus undisturbed. The plan
mentions this briefly; make it a first-class requirement with test
coverage.

### 9.3 Dynamic Opened Size for Expandable Settings (Phase 5.1)

The plan says "Computed `openedSize` varying by content type" but does
not describe the dynamic height contribution from expanded picker rows
within the settings menu. Each expandable row must contribute its
expansion height to the total, and a token or similar mechanism must
trigger view re-computation when a selector opens or closes. Without
this, the settings panel either clips content or has permanent empty
space.

### 9.4 Hit-Test / Visual Width Sync Contract (Phase 4.2 / 6.2)

The pass-through hosting view and the SwiftUI notch view must compute
the same closed-state width. Both should call the layout engine with
identical parameters. Consider a single source-of-truth method that
both layers consume, or at minimum a documented contract with a
comment in each location pointing to the other.

### 9.5 Module Context Structs (Phase 6.1)

The plan's `ModuleVisibilityContext` and `ModuleRenderContext` structs
are a good improvement over the reference codebase's approach of
passing multiple individual parameters. Make sure these structs are
`Sendable` value types that the layout engine can construct without
reaching into global singletons — this keeps the module system testable
in isolation.

### 9.6 Layered Animation Strategy (Phase 5.3)

Rather than a single open/close animation pair, use distinct animations
for different visual properties: spring for the container size change,
smooth for activity-state changes, a separate spring for bounce, and
asymmetric transitions for content insertion vs. removal. This layered
approach creates a polished feel where different elements move at
different rates rather than everything snapping in unison.

### 9.7 Module Layout Settings as a Dedicated Sub-Phase (Phase 6)

The three-column drag-and-drop layout settings view is substantial
(roughly 250 lines in the reference) and tightly coupled to the module
system. Consider giving it a dedicated sub-phase (e.g., 6.7) rather
than a single line item in Phase 9.2. It needs its own drop-target
handling, insertion indicators, empty-state placeholders, and config
persistence round-trip testing.

### 9.8 Provider-Aware Module Visibility

The reference codebase hardcodes some visibility logic to a single
provider (e.g., "is processing" checks against `.claude` activity
type). In a provider-agnostic app, module visibility context should
include which providers are active and what their aggregate state is,
so modules can make provider-aware decisions without coupling to a
specific provider's identity.
