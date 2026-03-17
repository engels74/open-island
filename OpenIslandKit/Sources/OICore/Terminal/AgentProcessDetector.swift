import CoreServices
import Darwin
import Foundation

// MARK: - DetectedAgentProcess

/// A detected running agent process.
package struct DetectedAgentProcess: Sendable, Equatable, Hashable {
    package let pid: Int32
    package let providerID: ProviderID
    package let processName: String
}

// MARK: - SessionDirectoryEvent

/// An event from monitoring session directories via FSEvents.
package struct SessionDirectoryEvent: Sendable {
    package let path: String
    package let providerID: ProviderID
    package let eventFlags: UInt32
}

// MARK: - AgentProcessDetector

/// Detects running CLI agent processes via `proc_*` polling and monitors
/// session directories for new files via FSEvents.
///
/// Uses `proc_listallpids` / `proc_pidinfo` to scan for known agent binaries
/// every few seconds. Wraps results in `AsyncStream` for structured concurrency.
/// FSEvents monitoring watches each provider's session log directory for
/// filesystem changes.
package enum AgentProcessDetector {
    // MARK: Package

    /// Default interval between process polls, in seconds.
    package static let defaultPollInterval: UInt64 = 3

    // MARK: - Process Detection

    /// Returns an `AsyncStream` that emits the current set of detected agent
    /// processes every `pollInterval` seconds. Uses `.bufferingNewest(1)` so
    /// consumers always see the latest snapshot.
    package static func detectedProcesses(
        pollInterval: UInt64 = defaultPollInterval,
    ) -> AsyncStream<Set<DetectedAgentProcess>> {
        let (stream, continuation) = AsyncStream<Set<DetectedAgentProcess>>.makeStream(
            bufferingPolicy: .bufferingNewest(1),
        )

        continuation.onTermination = { _ in
            // No resources to clean up for the polling stream; the Task
            // cancellation handles stopping the loop.
        }

        let task = Task {
            while !Task.isCancelled {
                let processes = await scanForAgentProcesses()
                continuation.yield(processes)
                try? await Task.sleep(for: .seconds(pollInterval))
            }
            continuation.finish()
        }

        // If the consumer drops the stream, cancel the polling task.
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        return stream
    }

    // MARK: - FSEvents Monitoring

    /// Returns an `AsyncStream` of filesystem events from all known session
    /// directories. Uses `.bufferingOldest(64)` to preserve event ordering.
    ///
    /// Directories that don't exist are silently skipped.
    package static func sessionDirectoryEvents() -> AsyncStream<SessionDirectoryEvent> {
        let (stream, continuation) = AsyncStream<SessionDirectoryEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(64),
        )

        let pathToProvider = self.sessionDirectoryMap()
        let existingPaths = pathToProvider.keys.filter { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }

        guard !existingPaths.isEmpty else {
            continuation.finish()
            return stream
        }

        self.startFSEventStream(
            paths: existingPaths,
            pathToProvider: pathToProvider,
            continuation: continuation,
        )

        return stream
    }

    // MARK: Private

    /// Creates and starts an FSEventStream, wiring events into the given continuation.
    private static func startFSEventStream(
        paths: some Collection<String>,
        pathToProvider: [String: ProviderID],
        continuation: AsyncStream<SessionDirectoryEvent>.Continuation,
    ) {
        let cfPaths = Array(paths) as CFArray
        let context = FSEventsContext(
            continuation: continuation,
            pathToProvider: pathToProvider,
        )
        let unmanagedContext = Unmanaged.passRetained(context)

        var streamContext = FSEventStreamContext(
            version: 0,
            info: unmanagedContext.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil,
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let ctx = Unmanaged<FSEventsContext>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                return
            }
            for i in 0 ..< numEvents {
                let path = paths[i]
                let provider = ctx.pathToProvider.first { dir, _ in path.hasPrefix(dir) }?.value
                guard let provider else { continue }
                ctx.continuation.yield(SessionDirectoryEvent(
                    path: path,
                    providerID: provider,
                    eventFlags: eventFlags[i],
                ))
            }
        }

        guard let eventStream = FSEventStreamCreate(
            nil,
            callback,
            &streamContext,
            cfPaths,
            // swiftformat:disable:next acronyms
            FSEventsGetCurrentEventId(),
            1.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes),
        )
        else {
            unmanagedContext.release()
            continuation.finish()
            return
        }

        let queue = DispatchQueue(label: "com.open-island.fsevents", qos: .utility)
        FSEventStreamSetDispatchQueue(eventStream, queue)
        FSEventStreamStart(eventStream)

        let streamRef = SendableStreamRef(eventStream)
        continuation.onTermination = { @Sendable _ in
            FSEventStreamStop(streamRef.value)
            FSEventStreamInvalidate(streamRef.value)
            FSEventStreamRelease(streamRef.value)
            unmanagedContext.release()
        }
    }

    /// Scans the system process list for known agent binaries.
    /// Runs on the global concurrent executor to avoid blocking the caller's actor.
    @concurrent
    private static func scanForAgentProcesses() async -> Set<DetectedAgentProcess> {
        let pids = self.allPIDs()
        var detected = Set<DetectedAgentProcess>()

        for pid in pids {
            guard let name = processName(for: pid) else { continue }

            if let provider = directBinaryMatch(name) {
                detected.insert(DetectedAgentProcess(
                    pid: pid,
                    providerID: provider,
                    processName: name,
                ))
            } else if name == "node" {
                // Gemini CLI runs as a Node.js process — check the executable path.
                if self.isGeminiNodeProcess(pid: pid) {
                    detected.insert(DetectedAgentProcess(
                        pid: pid,
                        providerID: .geminiCLI,
                        processName: "node (gemini)",
                    ))
                }
            } else if name == "sandbox-exec" {
                // Codex CLI may be wrapped in sandbox-exec.
                if self.isSandboxedCodexProcess(pid: pid) {
                    detected.insert(DetectedAgentProcess(
                        pid: pid,
                        providerID: .codex,
                        processName: "sandbox-exec (codex)",
                    ))
                }
            }
        }

        return detected
    }

    // MARK: - Private Helpers — Process Scanning

    /// Returns all PIDs on the system.
    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        let actualBytes = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * Int(count)))
        guard actualBytes > 0 else { return [] }
        let actualCount = Int(actualBytes) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(actualCount))
    }

    /// Returns the short process name for a PID using `proc_pidinfo`.
    private static func processName(for pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size),
        )
        guard size > 0 else { return nil }
        return withUnsafeBytes(of: info.pbi_name) { buf in
            guard let baseAddress = buf.baseAddress else { return nil }
            return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
        }
    }

    /// Returns the executable path for a PID using `proc_pidpath`.
    private static func executablePath(for pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN; the macro is unavailable
        // in Swift so we use the equivalent constant directly.
        let maxSize = 4 * Int(MAXPATHLEN)
        var pathBuffer = [CChar](repeating: 0, count: maxSize)
        let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(maxSize))
        guard pathLen > 0 else { return nil }
        pathBuffer[min(Int(pathLen), maxSize - 1)] = 0
        return pathBuffer.withUnsafeBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return nil }
            return String(validatingCString: baseAddress)
        }
    }

    /// Maps a process name directly to a provider ID for non-ambiguous binaries.
    private static func directBinaryMatch(_ name: String) -> ProviderID? {
        switch name {
        case "claude": .claude
        case "codex": .codex
        case "gemini": .geminiCLI
        case "opencode": .openCode
        default: nil
        }
    }

    /// Checks whether a `node` process at the given PID is running Gemini CLI
    /// by inspecting the process arguments for "gemini".
    private static func isGeminiNodeProcess(pid: pid_t) -> Bool {
        self.processArgs(for: pid).contains { arg in
            arg.contains("gemini")
        }
    }

    /// Checks whether a `sandbox-exec` process at the given PID wraps a Codex
    /// process by inspecting the process arguments.
    private static func isSandboxedCodexProcess(pid: pid_t) -> Bool {
        self.processArgs(for: pid).contains { arg in
            arg.contains("codex")
        }
    }

    /// Retrieves the command-line arguments for a process using `sysctl`.
    private static func processArgs(for pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0

        // First call to get the required buffer size.
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else {
            return []
        }

        // The buffer starts with argc (Int32), followed by the exec path,
        // then NUL-separated arguments.
        guard size > MemoryLayout<Int32>.size else { return [] }

        var argc: Int32 = 0
        memcpy(&argc, buffer, MemoryLayout<Int32>.size)

        // Skip past argc.
        var offset = MemoryLayout<Int32>.size

        // Skip the exec path (NUL-terminated).
        while offset < size, buffer[offset] != 0 {
            offset += 1
        }

        // Skip trailing NULs between exec path and first argument.
        while offset < size, buffer[offset] == 0 {
            offset += 1
        }

        // Read `argc` NUL-terminated strings.
        var args: [String] = []
        for _ in 0 ..< argc {
            guard offset < size else { break }
            let start = offset
            while offset < size, buffer[offset] != 0 {
                offset += 1
            }
            if offset > start {
                let arg = buffer[start ..< offset].withUnsafeBufferPointer { buf in
                    String(bytes: buf, encoding: .utf8) ?? ""
                }
                args.append(arg)
            }
            offset += 1 // skip NUL
        }

        return args
    }

    // MARK: - Private Helpers — Session Directories

    /// Builds a mapping from expanded session directory paths to their provider IDs.
    private static func sessionDirectoryMap() -> [String: ProviderID] {
        var map: [String: ProviderID] = [:]
        for providerID in [ProviderID.claude, .codex, .geminiCLI, .openCode] {
            let metadata = ProviderMetadata.metadata(for: providerID)
            let expanded = (metadata.sessionLogDirectoryPath as NSString).expandingTildeInPath
            map[expanded] = providerID
        }
        return map
    }
}

// MARK: - SendableStreamRef

/// Sendable wrapper for `FSEventStreamRef` (`OpaquePointer`) so it can be
/// captured in `@Sendable` closures. The wrapped pointer is immutable after init.
private struct SendableStreamRef: @unchecked Sendable {
    // MARK: Lifecycle

    init(_ ref: FSEventStreamRef) {
        self.value = ref
    }

    // MARK: Internal

    let value: FSEventStreamRef
}

// MARK: - FSEventsContext

/// Bridges the AsyncStream continuation into the C-function-pointer-based
/// FSEvents callback via `Unmanaged`.
private final class FSEventsContext: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        continuation: AsyncStream<SessionDirectoryEvent>.Continuation,
        pathToProvider: [String: ProviderID],
    ) {
        self.continuation = continuation
        self.pathToProvider = pathToProvider
    }

    // MARK: Internal

    let continuation: AsyncStream<SessionDirectoryEvent>.Continuation
    let pathToProvider: [String: ProviderID]
}
