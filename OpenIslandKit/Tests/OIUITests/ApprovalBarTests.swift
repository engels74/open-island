import Foundation
@testable import OICore
import Testing

// MARK: - ApprovalBarTests

struct ApprovalBarTests {
    // MARK: - Approval Bar Visibility

    @Test
    func `Approval bar should be visible when phase is waitingForApproval`() {
        let context = PermissionContext(
            toolUseID: "req-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("rm -rf node_modules")]),
            timestamp: .now,
            risk: .high,
        )
        let phase = SessionPhase.waitingForApproval(context)

        if case .waitingForApproval = phase {
        } else {
            Issue.record("Phase should be .waitingForApproval")
        }
    }

    @Test(
        arguments: [
            SessionPhase.idle,
            SessionPhase.processing,
            SessionPhase.waitingForInput,
            SessionPhase.compacting,
            SessionPhase.ended,
        ],
    )
    func `Approval bar should be hidden for non-approval phases`(phase: SessionPhase) {
        if case .waitingForApproval = phase {
            Issue.record("Phase \(phase) should NOT show approval bar")
        }
    }

    @Test
    func `Approval context is extractable from waitingForApproval phase`() {
        let context = PermissionContext(
            toolUseID: "req-42",
            toolName: "Write",
            toolInput: .object(["path": .string("/etc/hosts")]),
            timestamp: .now,
            risk: .medium,
        )
        let phase = SessionPhase.waitingForApproval(context)

        if case let .waitingForApproval(extracted) = phase {
            #expect(extracted.toolUseID == "req-42")
            #expect(extracted.toolName == "Write")
            #expect(extracted.risk == .medium)
        } else {
            Issue.record("Failed to extract context from phase")
        }
    }

    // MARK: - Risk Level Mapping

    @Test
    func `Low risk maps to expected properties`() {
        let context = PermissionContext(
            toolUseID: "r1",
            toolName: "Read",
            timestamp: .now,
            risk: .low,
        )
        #expect(context.risk == .low)
    }

    @Test
    func `Medium risk maps to expected properties`() {
        let context = PermissionContext(
            toolUseID: "r2",
            toolName: "Write",
            timestamp: .now,
            risk: .medium,
        )
        #expect(context.risk == .medium)
    }

    @Test
    func `High risk maps to expected properties`() {
        let context = PermissionContext(
            toolUseID: "r3",
            toolName: "Bash",
            timestamp: .now,
            risk: .high,
        )
        #expect(context.risk == .high)
    }

    @Test
    func `Nil risk is valid (no badge shown)`() {
        let context = PermissionContext(
            toolUseID: "r4",
            toolName: "Glob",
            timestamp: .now,
        )
        #expect(context.risk == nil)
    }

    @Test(
        arguments: [PermissionRisk.low, .medium, .high],
    )
    func `All risk levels are distinct`(risk: PermissionRisk) {
        let allRisks: [PermissionRisk] = [.low, .medium, .high]
        let otherRisks = allRisks.filter { $0 != risk }
        #expect(otherRisks.count == 2)
    }

    // MARK: - PermissionContext Data

    @Test
    func `PermissionContext stores all fields correctly`() {
        let timestamp = Date.now
        let input: JSONValue = .object(["command": .string("swift build")])
        let context = PermissionContext(
            toolUseID: "use-123",
            toolName: "Bash",
            toolInput: input,
            timestamp: timestamp,
            risk: .high,
        )

        #expect(context.toolUseID == "use-123")
        #expect(context.toolName == "Bash")
        #expect(context.toolInput == input)
        #expect(context.timestamp == timestamp)
        #expect(context.risk == .high)
    }

    @Test
    func `displaySummary extracts command from toolInput`() {
        let context = PermissionContext(
            toolUseID: "ds1",
            toolName: "Bash",
            toolInput: .object(["command": .string("rm -rf /tmp/test")]),
            timestamp: .now,
        )
        #expect(context.displaySummary == "Bash: rm -rf /tmp/test")
    }

    @Test
    func `displaySummary extracts path from toolInput`() {
        let context = PermissionContext(
            toolUseID: "ds2",
            toolName: "Read",
            toolInput: .object(["path": .string("/etc/hosts")]),
            timestamp: .now,
        )
        #expect(context.displaySummary == "Read: /etc/hosts")
    }

    @Test
    func `displaySummary falls back to tool name when no command/path`() {
        let context = PermissionContext(
            toolUseID: "ds3",
            toolName: "Glob",
            timestamp: .now,
        )
        #expect(context.displaySummary == "Glob")
    }

    // MARK: - Session Integration

    @Test
    func `SessionState with waitingForApproval phase carries context`() {
        let context = PermissionContext(
            toolUseID: "req-99",
            toolName: "Bash",
            toolInput: .object(["command": .string("npm install")]),
            timestamp: .now,
            risk: .medium,
        )
        let session = SessionState(
            id: "s1",
            providerID: .claude,
            phase: .waitingForApproval(context),
            projectName: "TestProject",
            cwd: "/tmp/test",
            createdAt: .now,
            lastActivityAt: .now,
        )

        if case let .waitingForApproval(ctx) = session.phase {
            #expect(ctx.toolUseID == "req-99")
            #expect(ctx.toolName == "Bash")
        } else {
            Issue.record("Session phase should be .waitingForApproval")
        }
    }
}
