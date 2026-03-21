package import Foundation
package import OICore
import Synchronization

// MARK: - CodexAppServerError

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

private struct PendingRequest: Sendable {
    let continuation: CheckedContinuation<JSONRPCResponse, any Error>
}

// MARK: - ServerInitiatedRequest

package struct ServerInitiatedRequest: Sendable {
    package let id: JSONRPCRequestID
    package let method: String
    package let params: JSONValue?
}

// MARK: - CodexAppServerClient

/// Manages the `codex app-server` child process and JSON-RPC communication.
package actor CodexAppServerClient {
    // MARK: Lifecycle

    package init(binaryPath: String = "codex") {
        self.binaryPath = binaryPath
    }

    // MARK: Package

    package func start() async throws(CodexAppServerError) {
        guard self.process == nil else { return }

        // Recreate streams — previous ones may have been finished by
        // handleProcessTermination() or stop().
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

        self.generation += 1
        let currentGeneration = self.generation
        self.readLoopTask = Task { [weak self] in
            await self?.readLoop(from: stdoutPipe, generation: currentGeneration)
        }

        do {
            try await self.performHandshake()
        } catch {
            await self.stop()
            throw .handshakeFailed("Handshake failed: \(error)")
        }
    }

    package func stop() async {
        // Cancel first so a stale loop cannot call handleProcessTermination()
        self.readLoopTask?.cancel()
        self.readLoopTask = nil

        for (_, pending) in self.pendingRequests {
            pending.continuation.resume(throwing: CodexAppServerError.processNotRunning)
        }
        self.pendingRequests.removeAll()

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

    package func sendResponse(id: JSONRPCRequestID, result: JSONValue) throws {
        let response = JSONRPCResponse(id: id, result: result)
        try writeMessage(response)
    }

    package func notifications() -> AsyncStream<JSONRPCNotification> {
        self.notificationStream
    }

    package func serverRequests() -> AsyncStream<ServerInitiatedRequest> {
        self.serverRequestStream
    }

    package func isReady() -> Bool {
        self.isInitialized && (self.process?.isRunning == true)
    }

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

    private var pendingRequests: [JSONRPCRequestID: PendingRequest] = [:]

    /// Re-created on each start() — finish() during process termination
    /// would permanently kill the stream for subsequent restarts.
    private var (notificationStream, notificationContinuation) =
        AsyncStream<JSONRPCNotification>.makeStream(bufferingPolicy: .bufferingOldest(256))

    /// Re-created on each start() — same rationale as above.
    private var (serverRequestStream, serverRequestContinuation) =
        AsyncStream<ServerInitiatedRequest>.makeStream(bufferingPolicy: .bufferingOldest(32))

    private let encoder: JSONEncoder = {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        return jsonEncoder
    }()

    private let decoder = JSONDecoder()

    private func nextRequestID() -> JSONRPCRequestID {
        self.requestCounter += 1
        return .int(self.requestCounter)
    }

    private func performHandshake() async throws {
        let response = try await sendRequest(method: .initialize)
        if let error = response.error {
            throw CodexAppServerError.serverError(error)
        }
        self.isInitialized = true
    }

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

        var lineData = data
        lineData.append(contentsOf: [UInt8(ascii: "\n")])
        pipe.fileHandleForWriting.write(lineData)
    }

    // MARK: - Message Reading

    /// `nonisolated` so blocking `FileHandle.availableData` doesn't occupy the
    /// actor's serial executor — allows sendRequest/stop to run concurrently.
    nonisolated private func readLoop(from pipe: Pipe, generation: Int) async {
        let handle = pipe.fileHandleForReading
        let jsonDecoder = JSONDecoder()
        var buffer = Data()

        while !Task.isCancelled {
            let chunk = handle.availableData
            if chunk.isEmpty { break }

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex ..< newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                guard !lineData.isEmpty else { continue }

                do {
                    let message = try jsonDecoder.decode(JSONRPCMessage.self, from: Data(lineData))
                    await self.dispatch(message)
                } catch {
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

    private func dispatch(_ message: JSONRPCMessage) {
        switch message {
        case let .response(response):
            self.handleResponse(response)
        case let .notification(notification):
            self.notificationContinuation.yield(notification)
        case let .request(request):
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

    /// The `generation` parameter ensures a stale read loop (from a previous
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
