package import OICore
import OIState
import OIWindow
package import SwiftUI

// MARK: - ChatView

/// Scrollable chat history for a single session.
///
/// Renders each ``ChatHistoryItem`` by its type — user bubbles, assistant
/// Markdown, tool results, collapsible thinking/reasoning sections, and
/// interruption dividers. An ``ApprovalBarView`` slides in from the bottom
/// when the session phase is `.waitingForApproval`.
package struct ChatView: View {
    // MARK: Lifecycle

    package init(session: SessionState, monitor: SessionMonitor, viewModel: NotchViewModel) {
        self.session = session
        self.monitor = monitor
        self.viewModel = viewModel
    }

    // MARK: Package

    package var body: some View {
        let accentColor = Color(hex: self.providerMeta.accentColorHex) ?? .orange

        VStack(spacing: 0) {
            // Back button header
            self.backBar(accent: accentColor)

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(self.session.chatItems) { item in
                            ChatItemView(
                                item: item,
                                accentColor: accentColor,
                                activeTools: self.session.activeTools,
                            )
                        }

                        // Scroll anchor
                        Color.clear
                            .frame(height: 1)
                            .id(Self.scrollAnchorID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: self.session.chatItems.count) {
                    if self.reduceMotion {
                        proxy.scrollTo(Self.scrollAnchorID, anchor: .bottom)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(Self.scrollAnchorID, anchor: .bottom)
                        }
                    }
                }
            }

            // Compaction banner — shown during context compaction
            if self.session.phase == .compacting {
                CompactingBanner()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Approval bar — conditionally shown
            if case let .waitingForApproval(context) = self.session.phase {
                ApprovalBarView(
                    context: context,
                    sessionID: self.session.id,
                    monitor: self.monitor,
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(self.reduceMotion ? .none : .snappy(duration: 0.25), value: self.session.phase)
    }

    // MARK: Private

    private static let scrollAnchorID = "chat-scroll-anchor"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    private let session: SessionState
    private let monitor: SessionMonitor
    private let viewModel: NotchViewModel

    private var providerMeta: ProviderMetadata {
        .metadata(for: self.session.providerID)
    }

    // MARK: - Back Bar

    private func backBar(accent: Color) -> some View {
        HStack(spacing: 6) {
            Button {
                self.viewModel.switchContent(.instances)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Sessions")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to sessions")
            .accessibilityHint("Returns to the session list")

            Spacer()

            Text(self.session.projectName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - ChatItemView

/// Routes a single ``ChatHistoryItem`` to the appropriate visual representation.
private struct ChatItemView: View {
    let item: ChatHistoryItem
    let accentColor: Color
    let activeTools: [ToolCallItem]

    var body: some View {
        switch self.item.type {
        case .user:
            UserBubble(content: self.item.content, accentColor: self.accentColor)
        case .assistant:
            AssistantMessage(content: self.item.content)
        case .toolCall:
            ToolCallMessage(item: self.item, activeTools: self.activeTools)
        case .thinking:
            CollapsibleSection(header: "Thinking...", content: self.item.content, isThinking: true)
        case .reasoning:
            CollapsibleSection(header: "Reasoning", content: self.item.content, isThinking: false)
        case .interrupted:
            InterruptedDivider()
        }
    }
}

// MARK: - UserBubble

private struct UserBubble: View {
    let content: String
    let accentColor: Color

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(self.content)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(self.accentColor, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(self.content)")
    }
}

// MARK: - AssistantMessage

private struct AssistantMessage: View {
    let content: String

    var body: some View {
        MarkdownText(self.content)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Assistant: \(self.content)")
    }
}

// MARK: - ToolCallMessage

private struct ToolCallMessage: View {
    // MARK: Internal

    let item: ChatHistoryItem
    let activeTools: [ToolCallItem]

    var body: some View {
        let tool = self.resolvedTool
        ToolResultView(tool: tool)
    }

    // MARK: Private

    private var resolvedTool: ToolCallItem {
        // Try to find matching tool from activeTools by item ID
        if let match = self.activeTools.first(where: { $0.id == self.item.id }) {
            return match
        }
        // Fallback: create a basic ToolCallItem from the chat item
        return ToolCallItem(
            id: self.item.id,
            name: self.item.providerSpecific?["tool_name"]?.stringValue ?? "Tool",
            input: self.item.providerSpecific?["input"],
            status: .success,
            result: .string(self.item.content),
        )
    }
}

// MARK: - CollapsibleSection

private struct CollapsibleSection: View {
    // MARK: Internal

    let header: String
    let content: String
    let isThinking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if self.reduceMotion {
                    self.isExpanded.toggle()
                } else {
                    withAnimation(.snappy(duration: 0.2)) {
                        self.isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: self.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Text(self.header)
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(self.header), \(self.isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint(self.isExpanded ? "Double-tap to collapse" : "Double-tap to expand")

            if self.isExpanded {
                Text(self.content)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    @State private var isExpanded = false
}

// MARK: - InterruptedDivider

private struct InterruptedDivider: View {
    // MARK: Internal

    var body: some View {
        HStack(spacing: 8) {
            self.line
            Text("Interrupted")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            self.line
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversation interrupted")
    }

    // MARK: Private

    @Environment(\.colorSchemeContrast) private var contrast // swiftlint:disable:this attributes

    private var line: some View {
        Rectangle()
            .fill(.white.opacity(self.contrast == .increased ? 0.3 : 0.1))
            .frame(height: 1)
    }
}

// MARK: - CompactingBanner

/// Inline banner shown at the bottom of the chat when context compaction is in progress.
private struct CompactingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.purple)
            Text("Compacting context\u{2026}")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.purple)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.purple.opacity(0.1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Context compaction in progress")
    }
}

// MARK: - Color + Hex

extension Color {
    /// Creates a `Color` from a hex string (e.g., `"#D97706"` or `"D97706"`).
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        guard hexString.count == 6, let rgb = UInt64(hexString, radix: 16) else {
            return nil
        }
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue)
    }
}

// MARK: - Previews

@MainActor
private func previewGeometry() -> NotchGeometry {
    NotchGeometry(
        notchSize: CGSize(width: 200, height: 32),
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    )
}

@MainActor
private func previewSession(phase: SessionPhase = .processing) -> SessionState {
    SessionState(
        id: "preview-chat-1",
        providerID: .claude,
        phase: phase,
        projectName: "MyProject",
        cwd: "/Users/dev/MyProject",
        chatItems: [
            ChatHistoryItem(id: "1", timestamp: .now, type: .user, content: "Fix the login bug in auth.swift"),
            ChatHistoryItem(
                id: "2", timestamp: .now, type: .assistant,
                content: "I'll look into the login bug. Let me read the file first.",
            ),
            ChatHistoryItem(
                id: "tool-1", timestamp: .now, type: .toolCall,
                content: "import Foundation\n...",
                providerSpecific: .object(["tool_name": .string("Read")]),
            ),
            ChatHistoryItem(
                id: "3", timestamp: .now, type: .thinking,
                content: "The bug is in the token validation logic. The expiry check uses > instead of >=.",
            ),
            ChatHistoryItem(
                id: "4", timestamp: .now, type: .assistant,
                content: """
                I found the issue. The token expiry check on **line 42** uses `>` instead \
                of `>=`, causing tokens to be rejected one second early. Let me fix it.
                """,
            ),
            ChatHistoryItem(id: "5", timestamp: .now, type: .interrupted, content: ""),
            ChatHistoryItem(id: "6", timestamp: .now, type: .reasoning, content: "User interrupted the previous approach. Adjusting strategy."),
            ChatHistoryItem(id: "7", timestamp: .now, type: .user, content: "Actually, also check the refresh token flow"),
        ],
        activeTools: [
            ToolCallItem(
                id: "tool-1",
                name: "Read",
                input: .object(["path": .string("/Users/dev/MyProject/Sources/Auth.swift")]),
                status: .success,
                result: .string("import Foundation\n\nfunc validateToken(_ token: Token) -> Bool {\n    token.expiry > Date.now\n}"),
            ),
        ],
        createdAt: .now,
        lastActivityAt: .now,
    )
}

#Preview("Chat — Various Messages") {
    let viewModel = NotchViewModel(geometry: previewGeometry())

    ChatView(
        session: previewSession(),
        monitor: SessionMonitor(store: SessionStore()),
        viewModel: viewModel,
    )
    .frame(width: 720, height: 520)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Chat — With Approval Bar") {
    let viewModel = NotchViewModel(geometry: previewGeometry())
    let context = PermissionContext(
        toolUseID: "req-42",
        toolName: "Bash",
        toolInput: .object(["command": .string("rm -rf node_modules")]),
        timestamp: .now,
        risk: .high,
    )

    ChatView(
        session: previewSession(phase: .waitingForApproval(context)),
        monitor: SessionMonitor(store: SessionStore()),
        viewModel: viewModel,
    )
    .frame(width: 720, height: 520)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Chat — Compacting") {
    let viewModel = NotchViewModel(geometry: previewGeometry())

    ChatView(
        session: previewSession(phase: .compacting),
        monitor: SessionMonitor(store: SessionStore()),
        viewModel: viewModel,
    )
    .frame(width: 720, height: 520)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Chat — Empty") {
    let viewModel = NotchViewModel(geometry: previewGeometry())

    ChatView(
        session: SessionState(
            id: "empty-1",
            providerID: .codex,
            phase: .idle,
            projectName: "EmptyProject",
            cwd: "/Users/dev/EmptyProject",
            createdAt: .now,
            lastActivityAt: .now,
        ),
        monitor: SessionMonitor(store: SessionStore()),
        viewModel: viewModel,
    )
    .frame(width: 720, height: 520)
    .background(.black)
    .preferredColorScheme(.dark)
}
