package import Foundation
import Network
import Synchronization

// MARK: - DiscoveredServer

/// A discovered OpenCode server instance.
package struct DiscoveredServer: Sendable, Equatable {
    // MARK: Lifecycle

    package init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    // MARK: Package

    package let host: String
    package let port: Int

    package var baseURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = self.host
        components.port = self.port
        // URLComponents handles IPv6 bracketing automatically.
        // With a valid scheme + host + port, `url` is guaranteed non-nil.
        // swiftlint:disable:next force_unwrapping
        return components.url!
    }
}

// MARK: - OpenCodeServerDiscovery

/// Discovers running OpenCode instances via multiple strategies:
///
/// 1. **User-specified port** — explicit configuration (highest priority)
/// 2. **mDNS discovery** — uses `NWBrowser` (Network framework) to find Bonjour-advertised services
/// 3. **Process argument parsing** — fallback that scans running `opencode` processes for `--port` arguments
///
/// The default OpenCode serve port is 4096 (`opencode serve --port 4096`).
package actor OpenCodeServerDiscovery {
    // MARK: Lifecycle

    package init(
        configuredPort: Int? = nil,
        defaultHost: String = "127.0.0.1",
        defaultPort: Int = 4096,
    ) {
        self.configuredPort = configuredPort
        self.defaultHost = defaultHost
        self.defaultPort = defaultPort
    }

    // MARK: Package

    /// Discover an OpenCode server using the priority chain:
    /// 1. User-configured port
    /// 2. mDNS discovery (with timeout)
    /// 3. Process argument parsing fallback
    /// 4. Default port (4096)
    package func discover(timeout: Duration = .seconds(3)) async -> DiscoveredServer {
        // 1. User-configured port takes priority
        if let port = configuredPort {
            return DiscoveredServer(host: self.defaultHost, port: port)
        }

        // 2. Try mDNS discovery
        if let server = await discoverViaMDNS(timeout: timeout) {
            return server
        }

        // 3. Try process argument parsing
        if let server = discoverViaProcessParsing() {
            return server
        }

        // 4. Fall back to default port
        return DiscoveredServer(host: self.defaultHost, port: self.defaultPort)
    }

    /// Check if a server is reachable by making a lightweight HTTP request.
    package func checkReachability(server: DiscoveredServer) async -> Bool {
        let url = server.baseURL.appendingPathComponent("config")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return (200 ... 299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    // MARK: Private

    /// The mDNS service type for OpenCode.
    private static let bonjourServiceType = "_opencode._tcp"

    private let configuredPort: Int?
    private let defaultHost: String
    private let defaultPort: Int

    /// Handle mDNS browse results by resolving the first service endpoint.
    private static func handleBrowseResults(
        _ results: Set<NWBrowser.Result>,
        resumeOnce: @escaping @Sendable (DiscoveredServer?) -> Void,
    ) {
        for result in results {
            if case .service = result.endpoint {
                let connection = NWConnection(to: result.endpoint, using: .tcp)
                connection.stateUpdateHandler = { connectionState in
                    Self.handleConnectionState(connectionState, connection: connection, resumeOnce: resumeOnce)
                }
                connection.start(queue: .global())
                return // Only try the first result
            }
        }
    }

    /// Resolve a discovered service connection to extract host and port.
    private static func handleConnectionState(
        _ connectionState: NWConnection.State,
        connection: NWConnection,
        resumeOnce: @escaping @Sendable (DiscoveredServer?) -> Void,
    ) {
        switch connectionState {
        case .ready:
            if let endpoint = connection.currentPath?.remoteEndpoint,
               case let .hostPort(host: host, port: port) = endpoint {
                let hostStr = "\(host)"
                let cleanHost = hostStr.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let server = DiscoveredServer(host: cleanHost, port: Int(port.rawValue))
                connection.cancel()
                resumeOnce(server)
            } else {
                connection.cancel()
            }
        case .failed,
             .cancelled:
            break
        default:
            break
        }
    }

    // MARK: - mDNS Discovery

    private func discoverViaMDNS(timeout: Duration) async -> DiscoveredServer? {
        await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveredServer?, Never>) in
            let browser = NWBrowser(
                for: .bonjour(type: Self.bonjourServiceType, domain: "local."),
                using: .tcp,
            )

            let state = Mutex<(hasResumed: Bool, continuation: CheckedContinuation<DiscoveredServer?, Never>?)>(
                (hasResumed: false, continuation: continuation),
            )

            @Sendable
            func resumeOnce(_ server: DiscoveredServer?) {
                let cont: CheckedContinuation<DiscoveredServer?, Never>? = state.withLock { syncState in
                    guard !syncState.hasResumed else { return nil }
                    syncState.hasResumed = true
                    let captured = syncState.continuation
                    syncState.continuation = nil
                    return captured
                }
                if let cont {
                    browser.cancel()
                    cont.resume(returning: server)
                }
            }

            browser.stateUpdateHandler = { browserState in
                switch browserState {
                case .failed,
                     .cancelled:
                    resumeOnce(nil)
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                Self.handleBrowseResults(results, resumeOnce: resumeOnce)
            }

            browser.start(queue: .global())

            Task.detached {
                try? await Task.sleep(for: timeout)
                resumeOnce(nil)
            }
        }
    }

    // MARK: - Process Argument Parsing

    /// Scan running processes for `opencode` instances and extract their `--port` argument.
    private func discoverViaProcessParsing() -> DiscoveredServer? {
        // Use `pgrep -a opencode` to find running opencode processes with arguments
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-fl", "opencode"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse each line looking for --port or serve arguments
        for line in output.components(separatedBy: "\n") {
            if let port = extractPort(from: line) {
                return DiscoveredServer(host: self.defaultHost, port: port)
            }
        }

        return nil
    }

    /// Extract a port number from a process command line.
    ///
    /// Looks for patterns like:
    /// - `--port 4096`
    /// - `--port=4096`
    /// - `serve --port 4096`
    private func extractPort(from commandLine: String) -> Int? {
        let components = commandLine.components(separatedBy: .whitespaces)

        for (index, component) in components.enumerated() {
            // --port=VALUE
            if component.hasPrefix("--port=") {
                let value = String(component.dropFirst("--port=".count))
                return Int(value)
            }

            // --port VALUE
            if component == "--port", index + 1 < components.count {
                return Int(components[index + 1])
            }

            // -p VALUE (short form)
            if component == "-p", index + 1 < components.count {
                return Int(components[index + 1])
            }
        }

        return nil
    }
}
