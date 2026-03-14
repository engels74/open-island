import Foundation
@testable import OICore
import Testing

struct PermissionContextTests {
    @Test
    func `Basic initialization`() {
        let ctx = PermissionContext(
            toolUseID: "tool-123",
            toolName: "Edit",
            timestamp: .now,
        )
        #expect(ctx.toolUseID == "tool-123")
        #expect(ctx.toolName == "Edit")
        #expect(ctx.risk == nil)
        #expect(ctx.toolInput == nil)
    }

    @Test
    func `Full initialization with all fields`() {
        let input: JSONValue = ["path": "/etc/hosts"]
        let ctx = PermissionContext(
            toolUseID: "tool-456",
            toolName: "Bash",
            toolInput: input,
            timestamp: .now,
            risk: .high,
        )
        #expect(ctx.toolName == "Bash")
        #expect(ctx.risk == .high)
        #expect(ctx.toolInput?["path"]?.stringValue == "/etc/hosts")
    }

    @Test
    func `displaySummary with command input`() {
        let ctx = PermissionContext(
            toolUseID: "t1",
            toolName: "Bash",
            toolInput: ["command": "rm -rf /tmp/test"],
            timestamp: .now,
        )
        #expect(ctx.displaySummary == "Bash: rm -rf /tmp/test")
    }

    @Test
    func `displaySummary with path input`() {
        let ctx = PermissionContext(
            toolUseID: "t2",
            toolName: "Edit",
            toolInput: ["path": "/src/main.swift"],
            timestamp: .now,
        )
        #expect(ctx.displaySummary == "Edit: /src/main.swift")
    }

    @Test
    func `displaySummary with command takes priority over path`() {
        let ctx = PermissionContext(
            toolUseID: "t3",
            toolName: "Bash",
            toolInput: ["command": "ls", "path": "/tmp"],
            timestamp: .now,
        )
        #expect(ctx.displaySummary == "Bash: ls")
    }

    @Test
    func `displaySummary falls back to tool name`() {
        let ctx = PermissionContext(
            toolUseID: "t4",
            toolName: "Read",
            timestamp: .now,
        )
        #expect(ctx.displaySummary == "Read")
    }

    @Test
    func `displaySummary falls back when input has no command or path`() {
        let ctx = PermissionContext(
            toolUseID: "t5",
            toolName: "Custom",
            toolInput: ["other": "data"],
            timestamp: .now,
        )
        #expect(ctx.displaySummary == "Custom")
    }

    @Test
    func `All risk levels`() {
        let low = PermissionContext(toolUseID: "r1", toolName: "T", timestamp: .now, risk: .low)
        let med = PermissionContext(toolUseID: "r2", toolName: "T", timestamp: .now, risk: .medium)
        let high = PermissionContext(toolUseID: "r3", toolName: "T", timestamp: .now, risk: .high)
        #expect(low.risk == .low)
        #expect(med.risk == .medium)
        #expect(high.risk == .high)
    }
}
