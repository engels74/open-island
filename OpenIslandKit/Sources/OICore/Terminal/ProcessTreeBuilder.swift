// @preconcurrency: NSRunningApplication, NSWorkspace predate Sendable annotations
@preconcurrency import AppKit
package import Darwin

// MARK: - ProcessInfo

/// Lightweight snapshot of a single process entry.
package struct ProcessInfo: Sendable, Hashable {
    package let pid: pid_t
    package let parentPID: pid_t
    /// Source: Darwin `pbi_name` field.
    package let name: String
}

// MARK: - TerminalAncestorResult

/// Result of walking a process tree from a child PID up to a terminal ancestor.
package struct TerminalAncestorResult: Sendable {
    package let terminalPID: pid_t
    package let terminalBundleID: String
    package let isTmuxSession: Bool
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
                // Process not in snapshot — fall back to direct syscall lookup.
                let directParent = Self.parentPID(of: current)
                if directParent <= 1 || directParent == current {
                    return nil
                }
                current = directParent
                continue
            }

            if !foundTmux, self.isTmuxProcess(entry.name) {
                foundTmux = true
                tmuxPID = current
            }

            if let bundleID = bundleIdentifier(for: current),
               registry.isTerminalBundleID(bundleID) {
                return TerminalAncestorResult(
                    terminalPID: current,
                    terminalBundleID: bundleID,
                    isTmuxSession: foundTmux,
                    tmuxServerPID: tmuxPID,
                )
            }

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

    private let entries: [pid_t: ProcessInfo]

    /// Returns the parent PID of the given process using `sysctl`.
    /// Used as a fallback when the process is not in the snapshot.
    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }

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
        // proc_listallpids returns a PID count (not bytes) — it wraps
        // proc_listpids and divides by sizeof(int) internally.
        let actualCount = proc_listallpids(
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size),
        )
        guard actualCount > 0 else {
            return ProcessTree(entries: [:])
        }

        var entries = [pid_t: ProcessInfo](minimumCapacity: Int(actualCount))

        for i in 0 ..< Int(actualCount) {
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
