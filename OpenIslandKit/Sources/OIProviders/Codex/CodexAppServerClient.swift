package import Foundation
package import OICore
import Synchronization

// MARK: - CodexAppServerError

/// Errors specific to the Codex app-server client.
package enum CodexAppServerError: Error, Sendable {
    case processNotRunning
    case handshakeFailed(String)
    case requestTimedOut(JSONRPCRequestID)
    case serverError(JSONRPCError)
    case encodingFailed
    case unexpectedResponse
    case stdinUnavailable
}

// MARK: - PendingRequest

/// A pending JSON-RPC request awaiting a response.
private struct PendingRequest: Sendable {
    let continuation: CheckedContinuation<JSONRPCResponse, any Error>
}

// MARK: - ServerInitiatedRequest

/// A server-initiated request (approval interception) awaiting a client response.
package struct ServerInitiatedRequest: Sendable {
    package let id: JSONRPCRequestID
    package let method: String
    package let params: JSONValue?
}

// MARK: - CodexAppServerClient

/// Actor managing the `codex app-server` child process lifecycle and JSON-RPC communication.
///
/// Responsibilities:
/// - Spawning `codex app-server` as a child process
/// - Writing JSON-RPC requests to the process's stdin (JSONL format)
/// - Reading JSON-RPC messages from stdout (JSONL format)
/// - Correlating request/response pairs via JSON-RPC IDs
/// - Performing the initialize/initialized handshake
/// - Forwarding server-initiated requests (approval interception) to the adapter
/// - Forwarding notifications to the event stream
package actor CodexAppServerClient {
    // MARK: Lifecycle

    package init(binaryPath: String = "codex") {
        self.binaryPath = binaryPath
    }

    // MARK: Package

    /// Start the app-server process and perform the JSON-RPC handshake.
    ///
    /// - Throws: `CodexAppServerError` if the process fails to launch or handshake fails.
    package func start() async throws(CodexAppServerError) {
        guard self.process == nil else { return }

        // Recreate streams so callers get fresh AsyncStreams after a restart.
        // Previous streams may have been finished by handleProcessTermination() or stop().
        (self.notificationStream, self.notificationContinuation) =
            AsyncStream<JSONRPCNotification>.makeStream(bufferingPolicy: .bufferingOldest(256))
        (self.serverRequestStream, self.serverRequestContinuation) =
            AsyncStream<ServerInitiatedRequest>.makeStream(bufferingPolicy: .bufferingOldest(32))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [self.binaryPath, "app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw .handshakeFailed("Failed to launch codex app-server: \(error)")
        }

        self.process = proc
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        // Start the read loop for stdout JSONL
        self.generation += 1
        let currentGeneration = self.generation
        self.readLoopTask = Task { [weak self] in
            await self?.readLoop(from: stdoutPipe, generation: currentGeneration)
        }

        // Perform initialize handshake
        do {
            try await self.performHandshake()
        } catch {
            await self.stop()
            throw .handshakeFailed("Handshake failed: \(error)")
        }
    }

    /// Stop the app-server process.
    package func stop() async {
        // Cancel the read loop so a stale loop cannot call handleProcessTermination()
        self.readLoopTask?.cancel()
        self.readLoopTask = nil

        // Cancel all pending requests
        for (_, pending) in self.pendingRequests {
            pending.continuation.resume(throwing: CodexAppServerError.processNotRunning)
        }
        self.pendingRequests.removeAll()

        // Finish current streams so consumers see termination
        self.notificationContinuation.finish()
        self.serverRequestContinuation.finish()

        if let proc = process, proc.isRunning {
            proc.terminate()
        }

        self.stdinPipe = nil
        self.stdoutPipe = nil
        self.process = nil
        self.isInitialized = false
    }

    /// Send a JSON-RPC request and await the response.
    ///
    /// - Parameters:
    ///   - method: The Codex method to call.
    ///   - params: Optional parameters.
    /// - Returns: The server's JSON-RPC response.
    package func sendRequest(
        method: CodexClientMethod,
        params: JSONValue? = nil,
    ) async throws -> JSONRPCResponse {
        guard self.process?.isRunning == true else {
            throw CodexAppServerError.processNotRunning
        }

        let id = self.nextRequestID()
        let request = JSONRPCRequest(id: id, method: method.rawValue, params: params)

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = PendingRequest(continuation: continuation)

            do {
                try self.writeMessage(request)
            } catch {
                self.pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Send a JSON-RPC response to a server-initiated request (approval interception).
    ///
    /// - Parameters:
    ///   - id: The request ID from the server-initiated request.
    ///   - result: The result payload (e.g., approval decision).
    package func sendResponse(id: JSONRPCRequestID, result: JSONValue) throws {
        let response = JSONRPCResponse(id: id, result: result)
        try writeMessage(response)
    }

    /// Stream of JSON-RPC notifications from the server.
    package func notifications() -> AsyncStream<JSONRPCNotification> {
        self.notificationStream
    }

    /// Stream of server-initiated requests (approval interception).
    package func serverRequests() -> AsyncStream<ServerInitiatedRequest> {
        self.serverRequestStream
    }

    /// Whether the handshake has completed and the client is ready.
    package func isReady() -> Bool {
        self.isInitialized && (self.process?.isRunning == true)
    }

    /// Check if the underlying process is still running.
    package func isProcessAlive() -> Bool {
        self.process?.isRunning == true
    }

    // MARK: Private

    private let binaryPath: String

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?

    private var isInitialized = false
    private var requestCounter = 0
    private var readLoopTask: Task<Void, Never>?
    private var generation = 0

    /// Pending requests awaiting responses, keyed by request ID.
    private var pendingRequests: [JSONRPCRequestID: PendingRequest] = [:]

    /// Notification stream for server→client notifications.
    /// Re-created on each `start()` so that `finish()` during process termination
    /// does not permanently kill the stream for subsequent restarts.
    private var (notificationStream, notificationContinuation) =
        AsyncStream<JSONRPCNotification>.makeStream(bufferingPolicy: .bufferingOldest(256))

    /// Stream for server-initiated requests (approval interception).
    /// Re-created on each `start()` so that `finish()` during process termination
    /// does not permanently kill the stream for subsequent restarts.
    private var (serverRequestStream, serverRequestContinuation) =
        AsyncStream<ServerInitiatedRequest>.makeStream(bufferingPolicy: .bufferingOldest(32))

    private let encoder: JSONEncoder = {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        return jsonEncoder
    }()

    private let decoder = JSONDecoder()

    // MARK: - Request ID Generation

    private func nextRequestID() -> JSONRPCRequestID {
        self.requestCounter += 1
        return .int(self.requestCounter)
    }

    // MARK: - Handshake

    /// Perform the initialize/initialized handshake.
    private func performHandshake() async throws {
        let response = try await sendRequest(method: .initialize)
        if let error = response.error {
            throw CodexAppServerError.serverError(error)
        }
        self.isInitialized = true
    }

    // MARK: - Message Writing

    /// Encode and write a JSON-RPC message to stdin as a single JSONL line.
    private func writeMessage(_ message: some Encodable) throws {
        guard let pipe = stdinPipe else {
            throw CodexAppServerError.stdinUnavailable
        }

        let data: Data
        do {
            data = try self.encoder.encode(message)
        } catch {
            throw CodexAppServerError.encodingFailed
        }

        // Write as JSONL: JSON object followed by newline
        var lineData = data
        lineData.append(contentsOf: [UInt8(ascii: "\n")])
        pipe.fileHandleForWriting.write(lineData)
    }

    // MARK: - Message Reading

    /// Continuously read JSONL lines from stdout and dispatch them.
    ///
    /// This method is `nonisolated` so that the blocking `FileHandle.availableData` call
    /// does not occupy the actor's serial executor — allowing `sendRequest`, `stop`, etc.
    /// to run concurrently while waiting for stdout data.
    nonisolated private func readLoop(from pipe: Pipe, generation: Int) async {
        let handle = pipe.fileHandleForReading
        let jsonDecoder = JSONDecoder()
        var buffer = Data()

        while !Task.isCancelled {
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF — process terminated
                break
            }

            buffer.append(chunk)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex ..< newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                guard !lineData.isEmpty else { continue }

                do {
                    let message = try jsonDecoder.decode(JSONRPCMessage.self, from: Data(lineData))
                    await self.dispatch(message)
                } catch {
                    // Malformed JSONL line — skip
                    NSLog("[CodexAppServerClient] Failed to decode JSONL line: \(error)")
                }
            }
        }

        // Only clean up if this read loop is still the current one.
        // A stale loop (from a previous start/stop cycle) must not
        // corrupt the newly started client state.
        guard !Task.isCancelled else { return }
        await self.handleProcessTermination(generation: generation)
    }

    /// Dispatch a decoded JSON-RPC message to the appropriate handler.
    private func dispatch(_ message: JSONRPCMessage) {
        switch message {
        case let .response(response):
            self.handleResponse(response)
        case let .notification(notification):
            self.notificationContinuation.yield(notification)
        case let .request(request):
            // Server-initiated request (approval interception)
            let yieldResult = self.serverRequestContinuation.yield(
                ServerInitiatedRequest(
                    id: request.id,
                    method: request.method,
                    params: request.params,
                ),
            )
            if case .dropped = yieldResult {
                NSLog("[CodexAppServerClient] Dropped server request (buffer full): method=%@, id=%@", request.method, "\(request.id)")
                let errorResponse = JSONRPCResponse(
                    id: request.id,
                    error: JSONRPCError(
                        code: JSONRPCErrorCode.internalError,
                        message: "Request dropped: server request buffer is full",
                    ),
                )
                do {
                    try self.writeMessage(errorResponse)
                } catch {
                    NSLog("[CodexAppServerClient] Failed to send error response for dropped request: %@", "\(error)")
                }
            }
        }
    }

    /// Match a response to its pending request and resume the continuation.
    private func handleResponse(_ response: JSONRPCResponse) {
        guard let pending = pendingRequests.removeValue(forKey: response.id) else {
            NSLog("[CodexAppServerClient] Received response for unknown request ID: \(response.id)")
            return
        }

        if let error = response.error {
            pending.continuation.resume(throwing: CodexAppServerError.serverError(error))
        } else {
            pending.continuation.resume(returning: response)
        }
    }

    /// Handle process termination: clear process state, fail pending requests, finish streams.
    ///
    /// Clears `process` and pipes so that `start()` can relaunch the child process
    /// without requiring an explicit `stop()` call first.
    ///
    /// The `generation` parameter ensures that a stale read loop (from a previous
    /// start/stop cycle) does not corrupt the current client state.
    private func handleProcessTermination(generation: Int) {
        guard generation == self.generation else { return }
        for (_, pending) in self.pendingRequests {
            pending.continuation.resume(throwing: CodexAppServerError.processNotRunning)
        }
        self.pendingRequests.removeAll()
        self.notificationContinuation.finish()
        self.serverRequestContinuation.finish()
        self.process = nil
        self.stdinPipe = nil
        self.stdoutPipe = nil
        self.isInitialized = false
    }
}
