package import Foundation
package import OICore
import OSLog

private let logger = Logger(subsystem: "com.openisland", category: "SessionTransitions")

// MARK: - Provider Event Handling

extension SessionStore {
    /// Process a provider event through the phase transition logic.
    ///
    /// Each ``ProviderEvent`` is mapped to an optional ``SessionPhase`` transition.
    /// Transitions are validated via ``SessionPhase/canTransition(to:)`` before
    /// applying — invalid transitions are logged and skipped.
    func handleProviderEvent(_ event: ProviderEvent) {
        switch event {
        case let .sessionStarted(sessionID, cwd: cwd, pid: pid):
            handleSessionStarted(sessionID, cwd: cwd, pid: pid)

        case let .sessionEnded(sessionID):
            transitionSession(sessionID, to: .ended)

        case let .userPromptSubmitted(sessionID):
            transitionSession(sessionID, to: .processing)

        case let .processingStarted(sessionID):
            transitionSession(sessionID, to: .processing)

        case .toolStarted,
             .toolCompleted:
            handleToolEvent(event)

        case .permissionRequested,
             .waitingForInput,
             .compacting:
            handleWaitingEvent(event)

        case .chatUpdated,
             .tokenUsage,
             .configChanged:
            handleDataUpdateEvent(event)

        case .notification,
             .subagentStarted,
             .subagentStopped,
             .diffUpdated,
             .modelResponse:
            handleActivityEvent(event)
        }
    }
}

// MARK: - Session Event Handling (non-provider)

extension SessionStore {
    func handlePermissionApproved(_ sessionID: String, requestID _: String) {
        transitionSession(sessionID, to: .processing)
    }

    func handlePermissionDenied(_ sessionID: String, requestID _: String, reason _: String?) {
        transitionSession(sessionID, to: .processing)
    }

    func handleArchiveSession(_ sessionID: String) {
        transitionSession(sessionID, to: .ended)
    }

    func handleUserAction(_: String, action _: UserAction) {
        // User actions (scroll, copy, cancel) are handled by the UI layer.
        // No session state changes needed.
    }
}

// MARK: - Event Category Handlers

extension SessionStore {
    private func handleToolEvent(_ event: ProviderEvent) {
        switch event {
        case let .toolStarted(sessionID, toolEvent):
            var tracker = toolTrackers[sessionID, default: ToolTracker()]
            let item = ToolEventProcessor.processToolStarted(toolEvent, tracker: &tracker)
            toolTrackers[sessionID] = tracker

            if var session = sessions[sessionID] {
                session.activeTools.append(item)
                session.lastActivityAt = Date()
                sessions[sessionID] = session
                publishState()
            }

        case let .toolCompleted(sessionID, toolEvent, toolResult):
            var tracker = toolTrackers[sessionID, default: ToolTracker()]
            let item = ToolEventProcessor.processToolCompleted(toolEvent, result: toolResult, tracker: &tracker)
            toolTrackers[sessionID] = tracker

            if var session = sessions[sessionID], let item {
                if let index = session.activeTools.firstIndex(where: { $0.id == item.id }) {
                    session.activeTools[index] = item
                } else {
                    session.activeTools.append(item)
                }
                session.lastActivityAt = Date()
                sessions[sessionID] = session
                publishState()
            }

        default:
            break
        }
    }

    private func handleWaitingEvent(_ event: ProviderEvent) {
        switch event {
        case let .permissionRequested(sessionID, request):
            let context = PermissionContext(
                toolUseID: request.id,
                toolName: request.toolName,
                toolInput: request.toolInput,
                timestamp: request.timestamp,
                risk: request.risk,
            )
            transitionSession(sessionID, to: .waitingForApproval(context))

        case let .waitingForInput(sessionID):
            transitionSession(sessionID, to: .waitingForInput)

        case let .compacting(sessionID):
            transitionSession(sessionID, to: .compacting)

        default:
            break
        }
    }

    private func handleDataUpdateEvent(_ event: ProviderEvent) {
        switch event {
        case let .chatUpdated(sessionID, items):
            if var session = sessions[sessionID] {
                session.chatItems = items
                session.lastActivityAt = Date()
                sessions[sessionID] = session
                publishState()
            }

        case let .tokenUsage(sessionID, promptTokens: prompt, completionTokens: completion, totalTokens: total):
            if var session = sessions[sessionID] {
                session.tokenUsage = TokenUsageSnapshot(
                    promptTokens: prompt,
                    completionTokens: completion,
                    totalTokens: total,
                    timestamp: Date(),
                )
                session.lastActivityAt = Date()
                sessions[sessionID] = session
                publishState()
            }

        case let .configChanged(sessionID):
            if let sessionID {
                _ = sessions[sessionID]
            }

        default:
            break
        }
    }

    private func handleActivityEvent(_ event: ProviderEvent) {
        switch event {
        case .notification(let sessionID, message: _):
            touchSession(sessionID)

        case .subagentStarted(let sessionID, taskID: _, parentToolID: _):
            touchSession(sessionID)

        case .subagentStopped(let sessionID, taskID: _):
            touchSession(sessionID)

        case .diffUpdated(let sessionID, unifiedDiff: _):
            touchSession(sessionID)

        case .modelResponse(let sessionID, textDelta: _):
            touchSession(sessionID)

        default:
            break
        }
    }
}

// MARK: - Private Helpers

extension SessionStore {
    /// Create a new session from a `.sessionStarted` event.
    private func handleSessionStarted(_ sessionID: String, cwd: String, pid: Int32?) {
        let projectName = (cwd as NSString).lastPathComponent
        let now = Date()
        let session = SessionState(
            id: sessionID,
            providerID: .claude, // TODO: infer from provider context in Phase 3+
            phase: .idle,
            projectName: projectName,
            cwd: cwd,
            pid: pid,
            createdAt: now,
            lastActivityAt: now,
        )
        sessions[sessionID] = session
        publishState()
    }

    /// Validate and apply a phase transition for the given session.
    ///
    /// If the transition is invalid, the event is logged and the phase remains
    /// unchanged. If the target phase equals the current phase, only
    /// `lastActivityAt` is updated.
    private func transitionSession(_ sessionID: String, to target: SessionPhase) {
        guard var session = sessions[sessionID] else {
            logger.warning("Transition to \(String(describing: target)) for unknown session \(sessionID)")
            return
        }

        let current = session.phase

        // Same phase — just touch the timestamp.
        if current == target {
            session.lastActivityAt = Date()
            sessions[sessionID] = session
            publishState()
            return
        }

        guard current.canTransition(to: target) else {
            logger.warning(
                "Invalid transition \(String(describing: current)) → \(String(describing: target)) for session \(sessionID)",
            )
            return
        }

        session.phase = target
        session.lastActivityAt = Date()
        sessions[sessionID] = session
        publishState()
    }

    /// Update `lastActivityAt` without changing phase.
    private func touchSession(_ sessionID: String) {
        guard var session = sessions[sessionID] else { return }
        session.lastActivityAt = Date()
        sessions[sessionID] = session
        publishState()
    }
}
