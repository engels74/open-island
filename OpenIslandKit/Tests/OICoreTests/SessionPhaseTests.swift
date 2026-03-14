import Foundation
@testable import OICore
import Testing

struct SessionPhaseTests {
    @Test
    func `Valid transitions from idle`() {
        #expect(SessionPhase.idle.canTransition(to: .processing))
        #expect(SessionPhase.idle.canTransition(to: .ended))
    }

    @Test
    func `Invalid transitions from idle`() {
        #expect(!SessionPhase.idle.canTransition(to: .idle))
        #expect(!SessionPhase.idle.canTransition(to: .waitingForInput))
        #expect(!SessionPhase.idle.canTransition(to: .compacting))
    }

    @Test
    func `Valid transitions from processing`() {
        #expect(SessionPhase.processing.canTransition(to: .waitingForInput))
        #expect(SessionPhase.processing.canTransition(to: .waitingForApproval(
            PermissionContext(toolUseID: "t", toolName: "test", timestamp: .now),
        )))
        #expect(SessionPhase.processing.canTransition(to: .compacting))
        #expect(SessionPhase.processing.canTransition(to: .ended))
    }

    @Test
    func `Invalid transitions from processing`() {
        #expect(!SessionPhase.processing.canTransition(to: .idle))
        #expect(!SessionPhase.processing.canTransition(to: .processing))
    }

    @Test
    func `Valid transitions from waitingForInput`() {
        #expect(SessionPhase.waitingForInput.canTransition(to: .processing))
        #expect(SessionPhase.waitingForInput.canTransition(to: .ended))
    }

    @Test
    func `Invalid transitions from waitingForInput`() {
        #expect(!SessionPhase.waitingForInput.canTransition(to: .idle))
        #expect(!SessionPhase.waitingForInput.canTransition(to: .waitingForInput))
        #expect(!SessionPhase.waitingForInput.canTransition(to: .compacting))
    }

    @Test
    func `Valid transitions from waitingForApproval`() {
        let ctx = PermissionContext(toolUseID: "t", toolName: "test", timestamp: .now)
        let phase = SessionPhase.waitingForApproval(ctx)
        #expect(phase.canTransition(to: .processing))
        #expect(phase.canTransition(to: .ended))
    }

    @Test
    func `Invalid transitions from waitingForApproval`() {
        let ctx = PermissionContext(toolUseID: "t", toolName: "test", timestamp: .now)
        let phase = SessionPhase.waitingForApproval(ctx)
        #expect(!phase.canTransition(to: .idle))
        #expect(!phase.canTransition(to: .waitingForInput))
        #expect(!phase.canTransition(to: .compacting))
    }

    @Test
    func `Valid transitions from compacting`() {
        #expect(SessionPhase.compacting.canTransition(to: .processing))
        #expect(SessionPhase.compacting.canTransition(to: .ended))
    }

    @Test
    func `Invalid transitions from compacting`() {
        #expect(!SessionPhase.compacting.canTransition(to: .idle))
        #expect(!SessionPhase.compacting.canTransition(to: .waitingForInput))
        #expect(!SessionPhase.compacting.canTransition(to: .compacting))
    }

    @Test
    func `Ended is terminal — no transitions out`() {
        let ctx = PermissionContext(toolUseID: "t", toolName: "test", timestamp: .now)
        let allPhases: [SessionPhase] = [
            .idle, .processing, .waitingForInput,
            .waitingForApproval(ctx), .compacting, .ended,
        ]
        for phase in allPhases {
            #expect(!SessionPhase.ended.canTransition(to: phase))
        }
    }

    @Test
    func `Equatable ignores associated values`() {
        let ctx1 = PermissionContext(toolUseID: "a", toolName: "tool1", timestamp: .now)
        let ctx2 = PermissionContext(toolUseID: "b", toolName: "tool2", timestamp: .now)
        #expect(SessionPhase.waitingForApproval(ctx1) == SessionPhase.waitingForApproval(ctx2))
    }

    @Test
    func `Same-phase equality`() {
        let idle: SessionPhase = .idle
        let sameIdle: SessionPhase = .idle
        #expect(idle == sameIdle)
        let processing: SessionPhase = .processing
        let sameProcessing: SessionPhase = .processing
        #expect(processing == sameProcessing)
        let waitingForInput: SessionPhase = .waitingForInput
        let sameWaitingForInput: SessionPhase = .waitingForInput
        #expect(waitingForInput == sameWaitingForInput)
        let compacting: SessionPhase = .compacting
        let sameCompacting: SessionPhase = .compacting
        #expect(compacting == sameCompacting)
        let ended: SessionPhase = .ended
        let sameEnded: SessionPhase = .ended
        #expect(ended == sameEnded)
    }

    @Test
    func `Different phases are not equal`() {
        #expect(SessionPhase.idle != SessionPhase.processing)
        #expect(SessionPhase.processing != SessionPhase.ended)
        #expect(SessionPhase.waitingForInput != SessionPhase.compacting)
    }
}
