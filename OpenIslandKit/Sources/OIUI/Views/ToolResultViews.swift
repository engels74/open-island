package import OICore
package import SwiftUI

// MARK: - ToolResultView

/// Expandable card for a single tool call, showing status, input summary,
/// result content, and optional duration/exit-code badges.
///
/// Nested subagent tools render indented beneath the parent card with a
/// visual connector line.
package struct ToolResultView: View {
    // MARK: Lifecycle

    package init(tool: ToolCallItem) {
        self.tool = tool
    }

    // MARK: Package

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolCardRow(tool: self.tool, isExpanded: self.$isExpanded)

            // Expanded result content
            if self.isExpanded, let result = self.tool.result {
                ResultContentView(result: result)
                    .padding(.leading, 28)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }

            // Nested subagent tools
            if !self.tool.nestedTools.isEmpty {
                NestedToolsView(tools: self.tool.nestedTools)
                    .padding(.leading, 20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.05)),
        )
    }

    // MARK: Private

    @State private var isExpanded = false

    private let tool: ToolCallItem
}

// MARK: - ToolCardRow

/// Header row of a tool card: status icon, name, input summary, badges.
private struct ToolCardRow: View {
    // MARK: Internal

    let tool: ToolCallItem

    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                self.isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                StatusIcon(status: self.tool.status)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.tool.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let summary = inputSummary {
                        Text(summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                self.badges
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    // MARK: - Input Summary

    private var inputSummary: String? {
        guard let input = self.tool.input else { return nil }

        // Bash-like tools: show command
        if let command = input["command"]?.stringValue {
            return command
        }
        // File tools: show path
        if let path = input["path"]?.stringValue {
            return path
        }
        if let filePath = input["file_path"]?.stringValue {
            return filePath
        }
        // Fallback: truncated JSON representation
        return truncatedJSON(input, maxLength: 80)
    }

    private var formattedDuration: String? {
        guard let ms = self.tool.providerSpecific?["durationMs"]?.intValue else {
            return nil
        }
        return if ms >= 1000 {
            String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            "\(ms)ms"
        }
    }

    // MARK: - Badges

    private var badges: some View {
        HStack(spacing: 6) {
            if let exitCode = self.tool.providerSpecific?["exitCode"]?.intValue {
                ExitCodeBadge(code: exitCode)
            }
            if let duration = formattedDuration {
                DurationBadge(text: duration)
            }
        }
    }
}

// MARK: - StatusIcon

/// Renders the appropriate icon for a tool's execution status.
private struct StatusIcon: View {
    let status: ToolStatus

    var body: some View {
        switch self.status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        case .interrupted:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 14))
        }
    }
}

// MARK: - ExitCodeBadge

/// Small badge showing a process exit code, colored by success/failure.
private struct ExitCodeBadge: View {
    let code: Int

    var body: some View {
        Text("exit \(self.code)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(self.code == 0 ? .green : .red)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((self.code == 0 ? Color.green : Color.red).opacity(0.15)),
            )
    }
}

// MARK: - DurationBadge

/// Small badge showing tool execution duration.
private struct DurationBadge: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08)),
            )
    }
}

// MARK: - ResultContentView

/// Displays the result content of a tool call as formatted text.
private struct ResultContentView: View {
    // MARK: Internal

    let result: JSONValue

    var body: some View {
        let text = self.resultText
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(self.showFullResult ? nil : 6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

        if text.split(separator: "\n").count > 6 {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    self.showFullResult.toggle()
                }
            } label: {
                Text(self.showFullResult ? "Show less" : "Show more\u{2026}")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Private

    @State private var showFullResult = false

    private var resultText: String {
        switch self.result {
        case let .string(text):
            text
        case let .object(dict):
            // Common pattern: result has a "content" or "output" key
            if let content = dict["content"]?.stringValue {
                content
            } else if let output = dict["output"]?.stringValue {
                output
            } else {
                formatJSON(self.result)
            }
        default:
            formatJSON(self.result)
        }
    }
}

// MARK: - NestedToolsView

/// Renders nested/subagent tool calls with indentation and a connector line.
private struct NestedToolsView: View {
    let tools: [ToolCallItem]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Visual connector line
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1.5)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(self.tools) { nested in
                    ToolResultView(tool: nested)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - JSON Helpers

/// Produce a truncated single-line representation of a JSONValue.
private func truncatedJSON(_ value: JSONValue, maxLength: Int) -> String {
    let full = formatJSON(value)
    let firstLine = String(full.prefix { $0 != "\n" })
    guard firstLine.count <= maxLength else {
        return String(firstLine.prefix(maxLength - 1)) + "\u{2026}"
    }
    return firstLine
}

/// Format a JSONValue as a readable string.
private func formatJSON(_ value: JSONValue) -> String {
    switch value {
    case let .string(text): return text
    case let .int(i): return String(i)
    case let .double(number): return String(number)
    case let .bool(flag): return flag ? "true" : "false"
    case .null: return "null"
    case let .array(arr):
        return "[\(arr.map { formatJSON($0) }.joined(separator: ", "))]"
    case let .object(dict):
        let entries = dict.sorted { $0.key < $1.key }
            .map { "\($0.key): \(formatJSON($0.value))" }
        return "{\(entries.joined(separator: ", "))}"
    }
}

// MARK: - Previews

#Preview("Running Tool") {
    ToolResultView(
        tool: ToolCallItem(
            id: "1",
            name: "Bash",
            input: .object(["command": .string("swift build")]),
            status: .running,
        ),
    )
    .padding()
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Successful Tool with Result") {
    ToolResultView(
        tool: ToolCallItem(
            id: "2",
            name: "Read",
            input: .object(["path": .string("/Users/dev/project/Sources/App.swift")]),
            status: .success,
            result: .string("""
            import Foundation

            @main
            struct App {
                static func main() async throws {
                    print("Hello, world!")
                }
            }
            """),
        ),
    )
    .padding()
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Failed Tool with Error") {
    ToolResultView(
        tool: ToolCallItem(
            id: "3",
            name: "Bash",
            input: .object(["command": .string("cargo build")]),
            status: .error,
            result: .string("error[E0308]: mismatched types\n  --> src/main.rs:12:5"),
            providerSpecific: .object([
                "exitCode": .int(1),
                "durationMs": .int(2340),
            ]),
        ),
    )
    .padding()
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Tool with Nested Subagent Tools") {
    ToolResultView(
        tool: ToolCallItem(
            id: "4",
            name: "Task",
            input: .object(["description": .string("Explore codebase structure")]),
            status: .success,
            result: .string("Found 12 Swift files across 3 modules."),
            nestedTools: [
                ToolCallItem(
                    id: "4-1",
                    name: "Glob",
                    input: .object(["pattern": .string("**/*.swift")]),
                    status: .success,
                    result: .string("12 files matched"),
                    providerSpecific: .object(["durationMs": .int(45)]),
                ),
                ToolCallItem(
                    id: "4-2",
                    name: "Read",
                    input: .object(["path": .string("Package.swift")]),
                    status: .success,
                    result: .string("// swift-tools-version: 6.2\n..."),
                    providerSpecific: .object(["durationMs": .int(12)]),
                ),
                ToolCallItem(
                    id: "4-3",
                    name: "Bash",
                    input: .object(["command": .string("wc -l Sources/**/*.swift")]),
                    status: .error,
                    result: .string("zsh: no matches found: Sources/**/*.swift"),
                    providerSpecific: .object([
                        "exitCode": .int(1),
                        "durationMs": .int(89),
                    ]),
                ),
            ],
            providerSpecific: .object(["durationMs": .int(3200)]),
        ),
    )
    .padding()
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Tool with Duration and Exit Code") {
    ToolResultView(
        tool: ToolCallItem(
            id: "5",
            name: "Bash",
            input: .object(["command": .string("pytest tests/ -v --tb=short")]),
            status: .success,
            result: .string("===== 42 passed in 3.21s ====="),
            providerSpecific: .object([
                "exitCode": .int(0),
                "durationMs": .int(3450),
            ]),
        ),
    )
    .padding()
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}
