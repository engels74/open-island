// @preconcurrency: NSRunningApplication predates Sendable annotations
@preconcurrency import AppKit
package import Darwin
import Foundation

// MARK: - TmuxPaneInfo

/// Identifies a specific tmux pane by session, window, and pane index.
package struct TmuxPaneInfo: Sendable {
    package let sessionName: String
    package let windowIndex: Int
    package let paneIndex: Int
}

// MARK: - TerminalFocuser

/// Activates the terminal application owning a given session PID and, for tmux
/// sessions, focuses the correct pane.
///
/// Uses ``ProcessTreeBuilder`` to walk the process tree and
/// ``TerminalAppRegistry`` to identify terminal bundle IDs.
package enum TerminalFocuser {
    // MARK: Package

    /// Focus the terminal that owns the given session PID.
    ///
    /// 1. Builds a process tree snapshot.
    /// 2. Walks from `sessionPID` up to find the terminal ancestor.
    /// 3. Activates the terminal app via `NSRunningApplication`.
    /// 4. If tmux is detected, focuses the correct tmux pane.
    ///
    /// - Parameter sessionPID: The PID of the CLI session (shell or tool).
    /// - Returns: `true` if the terminal was successfully activated.
    @discardableResult
    package static func focusTerminal(
        for sessionPID: pid_t,
        registry: TerminalAppRegistry = .shared,
    ) async -> Bool {
        let tree = await ProcessTreeBuilder.build()

        guard let ancestor = tree.findTerminalAncestor(of: sessionPID, registry: registry) else {
            return false
        }

        let activated = await activateApp(pid: ancestor.terminalPID)

        if ancestor.isTmuxSession {
            await self.focusTmuxPane(for: sessionPID)
        }

        return activated
    }

    // MARK: Private

    /// Activates the application with the given PID via `NSRunningApplication`.
    @MainActor
    private static func activateApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.activate()
    }

    /// Finds the tmux pane containing `sessionPID` and focuses it.
    ///
    /// Shells out to `tmux list-panes` to map pane PIDs to session/window/pane
    /// coordinates, then uses `tmux select-window` and `tmux select-pane`.
    private static func focusTmuxPane(for sessionPID: pid_t) async {
        guard let paneInfo = await findTmuxPane(for: sessionPID) else {
            return
        }

        let target = "\(paneInfo.sessionName):\(paneInfo.windowIndex)"

        await self.runTmuxCommand(["select-window", "-t", target])
        await self.runTmuxCommand(["select-pane", "-t", "\(target).\(paneInfo.paneIndex)"])
    }

    /// Queries tmux for all panes and finds the one containing `sessionPID`.
    ///
    /// Walks up from `sessionPID` checking each PID against tmux's pane PID list
    /// to handle cases where the target PID is a child of the pane's shell.
    @concurrent
    private static func findTmuxPane(for sessionPID: pid_t) async -> TmuxPaneInfo? {
        guard let output = await runShellCommand(
            "/usr/bin/env",
            arguments: [
                "tmux", "list-panes", "-a",
                "-F", "#{pane_pid} #{session_name} #{window_index} #{pane_index}",
            ],
        )
        else {
            return nil
        }

        var paneMap = [pid_t: TmuxPaneInfo]()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3)
            guard parts.count == 4,
                  let panePID = Int32(parts[0]),
                  let windowIndex = Int(parts[2]),
                  let paneIndex = Int(parts[3])
            else {
                continue
            }
            paneMap[panePID] = TmuxPaneInfo(
                sessionName: String(parts[1]),
                windowIndex: windowIndex,
                paneIndex: paneIndex,
            )
        }

        if let info = paneMap[sessionPID] {
            return info
        }

        // The session PID may be a child of the pane's shell, not the pane itself.
        var current = sessionPID
        var visited = Set<pid_t>()
        for _ in 0 ..< 20 {
            guard !visited.contains(current) else { break }
            visited.insert(current)

            let parent = self.parentPID(of: current)
            if parent <= 1 || parent == current { break }

            if let info = paneMap[parent] {
                return info
            }
            current = parent
        }

        return nil
    }

    /// Runs a tmux subcommand.
    @concurrent
    private static func runTmuxCommand(_ arguments: [String]) async {
        _ = await self.runShellCommand("/usr/bin/env", arguments: ["tmux"] + arguments)
    }

    /// Runs a shell command and returns its standard output, or `nil` on failure.
    @concurrent
    private static func runShellCommand(
        _ executablePath: String,
        arguments: [String],
    ) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress stderr.

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Returns the parent PID of the given process using `sysctl`.
    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }
}
