@preconcurrency import AppKit
package import Darwin

// MARK: - ProcessInfo

/// Lightweight snapshot of a single process entry.
package struct ProcessInfo: Sendable, Hashable {
    /// The process identifier.
    package let pid: pid_t

    /// The parent process identifier.
    package let parentPID: pid_t

    /// The process name (from `pbi_name`).
    package let name: String
}

// MARK: - TerminalAncestorResult

/// Result of walking a process tree from a child PID up to a terminal ancestor.
package struct TerminalAncestorResult: Sendable {
    /// The PID of the terminal application that owns the session.
    package let terminalPID: pid_t

    /// The bundle identifier of the terminal application.
    package let terminalBundleID: String

    /// Whether a `tmux` server process was found in the ancestry chain.
    package let isTmuxSession: Bool

    /// The PID of the tmux server process, if found.
    package let tmuxServerPID: pid_t?
}

// MARK: - ProcessTree

/// A snapshot of the system process table, mapping each PID to its ``ProcessInfo``.
///
/// Built from Darwin `proc_listallpids` / `proc_pidinfo` calls. All data is
/// captured once and then queried in-memory — no further system calls after
/// construction.
package struct ProcessTree: Sendable {
    // MARK: Lifecycle

    package init(entries: [pid_t: ProcessInfo]) {
        self.entries = entries
    }

    // MARK: Package

    /// Look up a process by PID.
    package func process(for pid: pid_t) -> ProcessInfo? {
        self.entries[pid]
    }

    /// Walk from `pid` up through parent processes looking for the first
    /// ancestor whose bundle ID is registered in ``TerminalAppRegistry``.
    ///
    /// Skips through `sandbox-exec` wrapper processes transparently.
    /// Detects `tmux` server processes in the ancestry chain.
    ///
    /// - Parameter pid: The starting process (typically a shell or CLI tool).
    /// - Returns: A ``TerminalAncestorResult`` if a terminal ancestor is found,
    ///   or `nil` if the walk reaches PID 1 / launchd without finding one.
    package func findTerminalAncestor(
        of pid: pid_t,
        registry: TerminalAppRegistry = .shared,
    ) -> TerminalAncestorResult? {
        var current = pid
        var visited = Set<pid_t>()
        var foundTmux = false
        var tmuxPID: pid_t?

        // Cap iterations to prevent infinite loops on unexpected trees.
        for _ in 0 ..< 64 {
            guard !visited.contains(current) else { return nil }
            visited.insert(current)

            guard let entry = entries[current] else {
                // Process not in snapshot — try parent via direct lookup.
                // This handles cases where the snapshot missed the entry.
                break
            }

            // Detect tmux server in ancestry.
            if !foundTmux, self.isTmuxProcess(entry.name) {
                foundTmux = true
                tmuxPID = current
            }

            // Check if this process is a known terminal via its bundle ID.
            if let bundleID = bundleIdentifier(for: current),
               registry.isTerminalBundleID(bundleID) {
                return TerminalAncestorResult(
                    terminalPID: current,
                    terminalBundleID: bundleID,
                    isTmuxSession: foundTmux,
                    tmuxServerPID: tmuxPID,
                )
            }

            // sandbox-exec wraps the real process — continue traversal through it.
            // No special handling needed; we just follow parentPID like any other process.

            let parent = entry.parentPID
            // Reached init/launchd or self-referencing — stop.
            if parent <= 1 || parent == current {
                return nil
            }

            current = parent
        }

        return nil
    }

    // MARK: Private

    /// PID-keyed lookup of process entries.
    private let entries: [pid_t: ProcessInfo]

    private func isTmuxProcess(_ name: String) -> Bool {
        name == "tmux" || name.hasPrefix("tmux:")
    }

    private func bundleIdentifier(for pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}

// MARK: - ProcessTreeBuilder

/// Builds a ``ProcessTree`` by enumerating all system processes via Darwin C APIs.
///
/// The `build()` method is marked `@concurrent` because `proc_listallpids`
/// and `proc_pidinfo` are blocking system calls.
package enum ProcessTreeBuilder {
    /// Enumerate all processes and build a ``ProcessTree`` snapshot.
    @concurrent
    package static func build() async -> ProcessTree {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else {
            return ProcessTree(entries: [:])
        }

        // Allocate with headroom for processes spawned between count and list.
        var pids = [pid_t](repeating: 0, count: Int(pidCount) + 64)
        let actualBytes = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size),
        )
        guard actualBytes > 0 else {
            return ProcessTree(entries: [:])
        }
        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size

        var entries = [pid_t: ProcessInfo](minimumCapacity: actualCount)

        for i in 0 ..< actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var info = proc_bsdinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_bsdinfo>.size),
            )
            guard size > 0 else { continue }

            let parentPID = pid_t(info.pbi_ppid)
            let name = withUnsafeBytes(of: info.pbi_name) { buf in
                guard let base = buf.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }

            entries[pid] = ProcessInfo(pid: pid, parentPID: parentPID, name: name)
        }

        return ProcessTree(entries: entries)
    }
}
