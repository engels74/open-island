package import Foundation
package import OICore
import OSLog

private let logger = Logger(subsystem: "com.engels74.openisland", category: "SessionTransitions")

// MARK: - Provider Event Handling

extension SessionStore {
    func handleProviderEvent(_ taggedEvent: TaggedProviderEvent) {
        let event = taggedEvent.event

        // Auto-recover unknown sessions: if an event arrives for a session ID
        // we don't have, create it on the fly so the event is not silently dropped.
        // This handles the case where Open Island restarts while a provider session
        // is still active — the next event self-heals the session.
        if let sessionID = event.sessionID,
           self.sessions[sessionID] == nil {
            switch event {
            case .sessionStarted:
                // Will be handled normally below — no recovery needed.
                break
            case .sessionEnded:
                // Don't create a zombie session for an already-gone session.
                break
            default:
                logger.warning("Auto-recovering unknown session \(sessionID) from incoming event")
                self.handleSessionStarted(sessionID, providerID: taggedEvent.providerID, cwd: "", pid: nil)
            }
        }

        switch event {
        case let .sessionStarted(sessionID, providerID: providerID, cwd: cwd, pid: pid):
            handleSessionStarted(sessionID, providerID: providerID, cwd: cwd, pid: pid)

        case let .sessionEnded(sessionID):
            transitionSession(sessionID, to: .ended)

        case let .userPromptSubmitted(sessionID):
            transitionSession(sessionID, to: .processing)

        case let .processingStarted(sessionID):
            transitionSession(sessionID, to: .processing)

        case .toolStarted,
             .toolCompleted,
             .subagentStarted,
             .subagentStopped:
            handleToolEvent(event)

        case .permissionRequested,
             .waitingForInput,
             .compacting:
            handleWaitingEvent(event)

        case .chatUpdated,
             .tokenUsage,
             .configChanged:
            handleDataUpdateEvent(event)

        case let .interruptDetected(sessionID):
            handleInterruptDetected(sessionID)

        case .notification,
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

        case let .subagentStarted(sessionID, taskID: taskID, parentToolID: parentToolID):
            var tracker = toolTrackers[sessionID, default: ToolTracker()]
            ToolEventProcessor.processSubagentStarted(taskID: taskID, parentToolID: parentToolID, tracker: &tracker)
            toolTrackers[sessionID] = tracker
            touchSession(sessionID)

        case let .subagentStopped(sessionID, taskID: taskID):
            var tracker = toolTrackers[sessionID, default: ToolTracker()]
            let subagent = ToolEventProcessor.processSubagentStopped(taskID: taskID, tracker: &tracker)
            toolTrackers[sessionID] = tracker

            if let subagent, var session = sessions[sessionID] {
                ToolEventProcessor.applyNestedTools(subagent: subagent, activeTools: &session.activeTools)
                session.lastActivityAt = Date()
                sessions[sessionID] = session
                publishState()
            } else {
                touchSession(sessionID)
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
    private func handleSessionStarted(_ sessionID: String, providerID: ProviderID, cwd: String, pid: Int32?) {
        let projectName = (cwd as NSString).lastPathComponent
        let now = Date()
        let session = SessionState(
            id: sessionID,
            providerID: providerID,
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

    private func transitionSession(_ sessionID: String, to target: SessionPhase) {
        guard var session = sessions[sessionID] else {
            logger.warning("Transition to \(String(describing: target)) for unknown session \(sessionID)")
            return
        }

        let current = session.phase

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

    /// Phase transition to `.waitingForInput` is handled by the separate
    /// `.waitingForInput` event that providers emit alongside `.interruptDetected`.
    private func handleInterruptDetected(_ sessionID: String) {
        guard var session = sessions[sessionID] else { return }

        let item = ChatHistoryItem(
            id: "\(sessionID)-interrupt-\(session.chatItems.count)",
            timestamp: Date(),
            type: .interrupted,
            content: "Session interrupted",
        )
        session.chatItems.append(item)
        session.lastActivityAt = Date()
        sessions[sessionID] = session
        publishState()
    }

    private func touchSession(_ sessionID: String) {
        guard var session = sessions[sessionID] else { return }
        session.lastActivityAt = Date()
        sessions[sessionID] = session
        publishState()
    }
}
