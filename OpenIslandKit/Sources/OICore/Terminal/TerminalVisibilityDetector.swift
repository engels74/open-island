// CGWindowListCopyWindowInfo predates Sendable annotations.
@preconcurrency import CoreGraphics

@preconcurrency import AppKit
import Foundation

// MARK: - TerminalVisibilityDetector

/// Queries the window server to determine whether a known terminal application
/// is visible, frontmost, or owns a specific session PID.
///
/// All methods are synchronous — they call `CGWindowListCopyWindowInfo`
/// directly. Safe to call from any isolation domain.
package enum TerminalVisibilityDetector {
    // MARK: Package

    /// Whether any known terminal has at least one on-screen window on the
    /// current desktop space.
    package static func isTerminalVisibleOnCurrentSpace() -> Bool {
        let windows = self.onScreenWindows()
        return windows.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32 else {
                return false
            }
            return self.bundleID(for: pid).map { TerminalAppRegistry.shared.isTerminalBundleID($0) } ?? false
        }
    }

    /// Whether a known terminal application is the frontmost (key) application.
    package static func isTerminalFrontmost() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return TerminalAppRegistry.shared.isTerminalBundleID(bundleID)
    }

    /// Best-effort check whether the terminal owning `sessionPID` has a window
    /// with at least 50% of its area visible on-screen.
    ///
    /// Falls back to `false` if the owning terminal cannot be determined or has
    /// no on-screen windows.
    package static func isSessionTerminalVisible(sessionPID: Int32) -> Bool {
        // Walk up the process tree to find the terminal PID that owns the
        // session. The session PID itself is typically a shell (zsh/bash)
        // parented by the terminal.
        guard let terminalPID = findTerminalAncestor(of: sessionPID) else {
            return false
        }

        let windows = self.onScreenWindows()
        let screenFrame = NSScreen.main.map(\.frame) ?? .zero

        for info in windows {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == terminalPID
            else {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"]
            else {
                continue
            }

            let windowRect = CGRect(x: x, y: y, width: width, height: height)
            let windowArea = windowRect.width * windowRect.height
            guard windowArea > 0 else { continue }

            let visibleRect = windowRect.intersection(screenFrame)
            let visibleArea = visibleRect.isNull ? 0 : visibleRect.width * visibleRect.height
            if visibleArea / windowArea >= 0.5 {
                return true
            }
        }

        return false
    }

    // MARK: Private

    // MARK: - Private Helpers

    /// Returns all on-screen window info dictionaries.
    private static func onScreenWindows() -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]]
        else {
            return []
        }
        return list
    }

    /// Resolves a PID to its bundle identifier via `NSRunningApplication`.
    private static func bundleID(for pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// Walks parent PIDs from `pid` looking for a process whose bundle ID
    /// is a known terminal. Returns the terminal's PID, or `nil`.
    private static func findTerminalAncestor(of pid: pid_t) -> pid_t? {
        var current = pid
        // Cap iterations to prevent infinite loops on unexpected process trees.
        for _ in 0 ..< 20 {
            if let bid = bundleID(for: current),
               TerminalAppRegistry.shared.isTerminalBundleID(bid) {
                return current
            }
            let parent = self.parentPID(of: current)
            // Reached init (PID 1) or self-referencing — stop.
            if parent <= 1 || parent == current {
                return nil
            }
            current = parent
        }
        return nil
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
