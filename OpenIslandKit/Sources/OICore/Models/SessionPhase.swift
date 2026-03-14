// MARK: - SessionPhase

/// The current phase of a provider session's lifecycle.
///
/// Forms a state machine with validated transitions via ``canTransition(to:)``.
/// The `.ended` phase is terminal — no transitions out.
package enum SessionPhase: Sendable {
    case idle
    case processing
    case waitingForInput
    case waitingForApproval(PermissionContext)
    case compacting
    case ended

    // MARK: Package

    /// Whether a transition from `self` to `target` is valid.
    ///
    /// Transition table:
    /// - `.idle` → `.processing`, `.ended`
    /// - `.processing` → `.waitingForInput`, `.waitingForApproval`, `.compacting`, `.ended`
    /// - `.waitingForInput` → `.processing`, `.ended`
    /// - `.waitingForApproval` → `.processing`, `.ended`
    /// - `.compacting` → `.processing`, `.ended`
    /// - `.ended` → (terminal)
    package func canTransition(to target: Self) -> Bool {
        switch (self, target) {
        case (.idle, .processing),
             (.idle, .ended),
             (.processing, .waitingForInput),
             (.processing, .waitingForApproval),
             (.processing, .compacting),
             (.processing, .ended),
             (.waitingForInput, .processing),
             (.waitingForInput, .ended),
             (.waitingForApproval, .processing),
             (.waitingForApproval, .ended),
             (.compacting, .processing),
             (.compacting, .ended):
            true
        default:
            false
        }
    }
}

// MARK: Equatable

/// Compares by case only — ignores associated values on `.waitingForApproval`.
extension SessionPhase: Equatable {
    package static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.processing, .processing),
             (.waitingForInput, .waitingForInput),
             (.waitingForApproval, .waitingForApproval),
             (.compacting, .compacting),
             (.ended, .ended):
            true
        default:
            false
        }
    }
}
