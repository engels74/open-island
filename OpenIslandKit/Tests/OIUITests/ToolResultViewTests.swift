import Foundation
@testable import OICore
import Testing

// MARK: - ToolResultViewTests

/// Tests for tool result data extraction and formatting logic
/// used by ``ToolResultView`` and ``ToolCardRow``.
///
/// Since the views are SwiftUI structs with private internals, these tests
/// verify the underlying data model operations that drive the view display.
struct ToolResultViewTests {
    // MARK: Internal

    // MARK: - Tool Status

    @Test(
        arguments: [ToolStatus.running, .success, .error, .interrupted],
    )
    func `ToolStatus has four distinct cases`(status: ToolStatus) {
        let allStatuses: [ToolStatus] = [.running, .success, .error, .interrupted]
        let others = allStatuses.filter { $0 != status }
        #expect(others.count == 3)
    }

    @Test
    func `Success status differs from error`() {
        #expect(ToolStatus.success != ToolStatus.error)
    }

    @Test
    func `Running status differs from interrupted`() {
        #expect(ToolStatus.running != ToolStatus.interrupted)
    }

    // MARK: - Input Summary Extraction

    @Test
    func `Command extraction from input`() {
        let input: JSONValue = .object(["command": .string("swift build")])
        let command = input["command"]?.stringValue
        #expect(command == "swift build")
    }

    @Test
    func `Path extraction from input`() {
        let input: JSONValue = .object(["path": .string("/Users/dev/project/App.swift")])
        let path = input["path"]?.stringValue
        #expect(path == "/Users/dev/project/App.swift")
    }

    @Test
    func `file_path extraction from input`() {
        let input: JSONValue = .object(["file_path": .string("/src/main.rs")])
        let filePath = input["file_path"]?.stringValue
        #expect(filePath == "/src/main.rs")
    }

    @Test
    func `Input with neither command nor path falls back to nil for both`() {
        let input: JSONValue = .object(["pattern": .string("**/*.swift")])
        #expect(input["command"]?.stringValue == nil)
        #expect(input["path"]?.stringValue == nil)
        #expect(input["file_path"]?.stringValue == nil)
    }

    @Test
    func `Nil input produces no summary`() {
        let tool = ToolCallItem(id: "t1", name: "Bash", status: .running)
        #expect(tool.input == nil)
    }

    // MARK: - Duration Formatting

    @Test
    func `Milliseconds below 1000 format as ms`() {
        let ms = 350
        let formatted = self.formatDuration(ms: ms)
        #expect(formatted == "350ms")
    }

    @Test
    func `Milliseconds at 1000+ format as seconds`() {
        let ms = 1200
        let formatted = self.formatDuration(ms: ms)
        #expect(formatted == "1.2s")
    }

    @Test
    func `Exact 1000ms formats as seconds`() {
        let formatted = self.formatDuration(ms: 1000)
        #expect(formatted == "1.0s")
    }

    @Test
    func `Large duration formats correctly`() {
        let formatted = self.formatDuration(ms: 3450)
        #expect(formatted == "3.5s")
    }

    // MARK: - Exit Code Extraction

    @Test
    func `Exit code 0 extracted from providerSpecific`() {
        let tool = ToolCallItem(
            id: "ec1",
            name: "Bash",
            status: .success,
            providerSpecific: .object(["exitCode": .int(0)]),
        )
        let exitCode = tool.providerSpecific?["exitCode"]?.intValue
        #expect(exitCode == 0)
    }

    @Test
    func `Non-zero exit code extracted`() {
        let tool = ToolCallItem(
            id: "ec2",
            name: "Bash",
            status: .error,
            providerSpecific: .object([
                "exitCode": .int(1),
                "durationMs": .int(2340),
            ]),
        )
        let exitCode = tool.providerSpecific?["exitCode"]?.intValue
        #expect(exitCode == 1)
    }

    @Test
    func `Missing exit code returns nil`() {
        let tool = ToolCallItem(
            id: "ec3",
            name: "Read",
            status: .success,
        )
        let exitCode = tool.providerSpecific?["exitCode"]?.intValue
        #expect(exitCode == nil)
    }

    @Test
    func `Duration extracted from providerSpecific`() {
        let tool = ToolCallItem(
            id: "d1",
            name: "Bash",
            status: .success,
            providerSpecific: .object(["durationMs": .int(450)]),
        )
        let ms = tool.providerSpecific?["durationMs"]?.intValue
        #expect(ms == 450)
    }

    // MARK: - Nested Tools

    @Test
    func `Tool with no nested tools has empty array`() {
        let tool = ToolCallItem(id: "n1", name: "Read", status: .success)
        #expect(tool.nestedTools.isEmpty)
    }

    @Test
    func `Nested tools count is accessible`() {
        let nested = [
            ToolCallItem(id: "n1-1", name: "Glob", status: .success),
            ToolCallItem(id: "n1-2", name: "Read", status: .success),
            ToolCallItem(id: "n1-3", name: "Bash", status: .error),
        ]
        let tool = ToolCallItem(
            id: "n1",
            name: "Task",
            status: .success,
            nestedTools: nested,
        )
        #expect(tool.nestedTools.count == 3)
    }

    @Test
    func `Nested tools preserve individual status`() {
        let nested = [
            ToolCallItem(id: "s1", name: "Glob", status: .success),
            ToolCallItem(id: "s2", name: "Bash", status: .error),
            ToolCallItem(id: "s3", name: "Read", status: .interrupted),
        ]
        let tool = ToolCallItem(
            id: "parent",
            name: "Task",
            status: .success,
            nestedTools: nested,
        )
        #expect(tool.nestedTools[0].status == .success)
        #expect(tool.nestedTools[1].status == .error)
        #expect(tool.nestedTools[2].status == .interrupted)
    }

    // MARK: - ToolCallItem Data Integrity

    @Test
    func `ToolCallItem preserves all fields`() {
        let input: JSONValue = .object(["command": .string("ls -la")])
        let result: JSONValue = .string("output text")
        let extra: JSONValue = .object([
            "exitCode": .int(0),
            "durationMs": .int(120),
        ])

        let tool = ToolCallItem(
            id: "full-1",
            name: "Bash",
            input: input,
            status: .success,
            result: result,
            providerSpecific: extra,
        )

        #expect(tool.id == "full-1")
        #expect(tool.name == "Bash")
        #expect(tool.input == input)
        #expect(tool.status == .success)
        #expect(tool.result == result)
        #expect(tool.nestedTools.isEmpty)
        #expect(tool.providerSpecific == extra)
    }

    // MARK: Private

    // MARK: - Helpers

    /// Replicates the duration formatting logic from ToolCardRow.
    private func formatDuration(ms: Int) -> String {
        if ms >= 1000 {
            String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            "\(ms)ms"
        }
    }
}
