package import Foundation

// MARK: - SSEEvent

/// A parsed Server-Sent Event from the OpenCode HTTP server.
package struct SSEEvent: Sendable {
    /// The event type (from the `event:` field). Nil for unnamed events.
    package let event: String?

    /// The event data (from the `data:` field). May span multiple lines.
    package let data: String

    /// The last event ID (from the `id:` field).
    package let id: String?
}

// MARK: - SSEEndpoint

/// Which SSE endpoint to connect to.
package enum SSEEndpoint: Sendable {
    /// Project-scoped events: `GET /event?directory=<path>`.
    case project(directory: String)

    /// Cross-project events: `GET /global/event`.
    case global
}

// MARK: - OpenCodeSSEError

/// Errors specific to the SSE client.
package enum OpenCodeSSEError: Error, Sendable {
    case invalidURL(String)
    case connectionFailed(statusCode: Int)
    case unexpectedDisconnect
}

// MARK: - OpenCodeSSEClient

/// Actor wrapping `URLSession` for streaming SSE connections to OpenCode's HTTP server.
///
/// Parses the SSE wire format (`event:`, `data:`, `id:`, `retry:` fields),
/// handles reconnection with exponential backoff, and respects the SSE `retry:` field.
package actor OpenCodeSSEClient {
    // MARK: Lifecycle

    package init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Package

    /// Connect to an SSE endpoint and return a stream of parsed events.
    ///
    /// The stream automatically reconnects on disconnection using exponential backoff.
    /// The SSE `retry:` field is respected when present.
    package func connect(
        endpoint: SSEEndpoint,
        lastEventID: String? = nil,
    ) -> AsyncStream<SSEEvent> {
        let url = Self.buildURL(baseURL: self.baseURL, endpoint: endpoint)
        let capturedSession = self.session
        let capturedLastEventID = lastEventID

        return AsyncStream<SSEEvent>(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let task = Task.detached {
                var currentLastEventID = capturedLastEventID
                var backoff = ExponentialBackoff()

                while !Task.isCancelled {
                    let result = await Self.streamEvents(
                        url: url,
                        session: capturedSession,
                        lastEventID: currentLastEventID,
                        backoff: &backoff,
                        continuation: continuation,
                    )

                    switch result {
                    case let .reconnect(updatedLastEventID):
                        currentLastEventID = updatedLastEventID
                        guard !Task.isCancelled else { break }
                        let delay = backoff.nextDelay()
                        try? await Task.sleep(for: .milliseconds(delay))
                    case .finished:
                        continuation.finish()
                        return
                    case .cancelled:
                        break
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Disconnect all active SSE streams.
    package func disconnect() {
        // Streams are disconnected by cancelling the tasks via continuation.onTermination
    }

    // MARK: Fileprivate

    /// Parse a single SSE field line into (field, value).
    ///
    /// Per the SSE spec:
    /// - If the line contains ':', the field is everything before the first ':'
    ///   and the value is everything after (with one optional leading space stripped).
    /// - If the line does not contain ':', the entire line is the field name
    ///   and the value is empty.
    fileprivate static func parseSSEField(_ line: String) -> (field: String, value: String) {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return (field: line, value: "")
        }

        let field = String(line[line.startIndex ..< colonIndex])
        let afterColon = line.index(after: colonIndex)

        if afterColon < line.endIndex, line[afterColon] == " " {
            // Strip one leading space
            let valueStart = line.index(after: afterColon)
            return (field: field, value: String(line[valueStart...]))
        }

        return (field: field, value: String(line[afterColon...]))
    }

    // MARK: Private

    /// Result of a single SSE connection attempt.
    private enum StreamResult {
        case reconnect(lastEventID: String?)
        case finished
        case cancelled
    }

    private let baseURL: URL
    private let session: URLSession

    /// Build the URL for the given SSE endpoint.
    private static func buildURL(baseURL: URL, endpoint: SSEEndpoint) -> URL {
        switch endpoint {
        case let .project(directory):
            baseURL.appendingPathComponent("event")
                .appending(queryItems: [URLQueryItem(name: "directory", value: directory)])
        case .global:
            baseURL.appendingPathComponent("global/event")
        }
    }

    /// Execute a single SSE connection, yielding events to the continuation.
    private static func streamEvents(
        url: URL,
        session: URLSession,
        lastEventID: String?,
        backoff: inout ExponentialBackoff,
        continuation: AsyncStream<SSEEvent>.Continuation,
    ) async -> StreamResult {
        do {
            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 0

            if let lastID = lastEventID {
                request.setValue(lastID, forHTTPHeaderField: "Last-Event-ID")
            }

            let (bytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                // Transient errors: 5xx server errors, 408 timeout, 429 rate-limit
                if statusCode >= 500 || statusCode == 408 || statusCode == 429 {
                    return .reconnect(lastEventID: lastEventID)
                }
                return .finished
            }

            backoff.reset()
            var updatedLastEventID = lastEventID
            var parser = SSELineParser()

            for try await line in bytes.lines {
                guard !Task.isCancelled else { return .cancelled }

                if let event = parser.processLine(line, backoff: &backoff) {
                    if let eventID = event.id {
                        updatedLastEventID = eventID
                    }
                    continuation.yield(event)
                }
            }

            return .reconnect(lastEventID: updatedLastEventID)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .reconnect(lastEventID: lastEventID)
        }
    }
}

// MARK: - SSELineParser

/// Accumulates SSE field lines and dispatches events on empty lines.
private struct SSELineParser {
    // MARK: Internal

    /// Process a single line from the SSE stream.
    ///
    /// Returns an ``SSEEvent`` when an empty line triggers dispatch, or `nil` otherwise.
    mutating func processLine(_ line: String, backoff: inout ExponentialBackoff) -> SSEEvent? {
        if line.isEmpty {
            return self.dispatchEvent()
        }

        if line.hasPrefix(":") {
            return nil // Comment
        }

        let (field, value) = OpenCodeSSEClient.parseSSEField(line)
        self.applyField(field, value: value, backoff: &backoff)
        return nil
    }

    // MARK: Private

    private var eventType: String?
    private var dataLines: [String] = []
    private var eventID: String?

    private mutating func dispatchEvent() -> SSEEvent? {
        defer {
            self.eventType = nil
            self.dataLines = []
            self.eventID = nil
        }

        guard !self.dataLines.isEmpty else { return nil }

        return SSEEvent(
            event: self.eventType,
            data: self.dataLines.joined(separator: "\n"),
            id: self.eventID,
        )
    }

    private mutating func applyField(_ field: String, value: String, backoff: inout ExponentialBackoff) {
        switch field {
        case "event":
            self.eventType = value
        case "data":
            self.dataLines.append(value)
        case "id":
            if !value.contains("\0") {
                self.eventID = value
            }
        case "retry":
            if let ms = Int(value) {
                backoff.setRetryInterval(milliseconds: ms)
            }
        default:
            break
        }
    }
}

// MARK: - ExponentialBackoff

/// Manages exponential backoff delays for SSE reconnection.
private struct ExponentialBackoff: Sendable {
    // MARK: Internal

    /// Get the next delay in milliseconds and increment the attempt counter.
    mutating func nextDelay() -> Int {
        // If server specified a retry interval, use it
        if let retryMs = retryIntervalMs {
            return retryMs
        }

        // Cap shift to avoid overflow trap when attempt exceeds Int bit width
        let shift = min(self.attempt, 30)
        let baseDelay = min(initialDelayMs * (1 << shift), self.maxDelayMs)
        let jitter = Int(Double(baseDelay) * self.jitterFraction * Double.random(in: -1 ... 1))
        self.attempt += 1
        return max(100, baseDelay + jitter)
    }

    /// Reset backoff state after a successful connection.
    mutating func reset() {
        self.attempt = 0
    }

    /// Set the retry interval from an SSE `retry:` field.
    mutating func setRetryInterval(milliseconds: Int) {
        guard milliseconds > 0 else { return }
        self.retryIntervalMs = milliseconds
    }

    // MARK: Private

    private var attempt = 0
    private var retryIntervalMs: Int?

    private let initialDelayMs = 1000
    private let maxDelayMs = 30000
    private let jitterFraction = 0.25
}
