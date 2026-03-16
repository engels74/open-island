package import Foundation
package import OICore

// MARK: - OpenCodeRESTError

/// Errors specific to the OpenCode REST client.
package enum OpenCodeRESTError: Error, Sendable {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String?)
    case encodingFailed(any Error)
    case decodingFailed(any Error)
    case networkError(any Error)
}

// MARK: - OpenCodePermissionDecision

/// The decision payload sent to OpenCode's permission endpoint.
package struct OpenCodePermissionDecision: Sendable, Encodable {
    // MARK: Lifecycle

    package init(allow: Bool, reason: String? = nil) {
        self.allow = allow
        self.reason = reason
    }

    // MARK: Package

    package let allow: Bool
    package let reason: String?
}

// MARK: - OpenCodeRESTClient

/// Actor wrapping `URLSession` for REST API calls to the OpenCode HTTP server.
///
/// Covers all REST endpoints:
/// - Session management: create, prompt, abort, list messages
/// - Permission response: approve/deny tool actions
/// - Configuration: get config, provider info, OpenAPI doc
package actor OpenCodeRESTClient {
    // MARK: Lifecycle

    package init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Package

    // MARK: - Session Management

    /// Create a new session.
    ///
    /// `POST /session`
    package func createSession(
        directory: String? = nil,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        var body: [String: JSONValue] = [:]
        if let directory {
            body["directory"] = .string(directory)
        }
        return try await self.post(path: "session", body: .object(body))
    }

    /// Send a prompt to an existing session.
    ///
    /// `POST /session/{id}/prompt`
    package func sendPrompt(
        sessionID: String,
        message: String,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        let body: JSONValue = .object(["message": .string(message)])
        return try await self.post(path: "session/\(sessionID)/prompt", body: body)
    }

    /// Abort the current processing in a session.
    ///
    /// `POST /session/{id}/abort`
    package func abortSession(
        sessionID: String,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        try await self.post(path: "session/\(sessionID)/abort", body: nil)
    }

    /// List messages in a session (for chat history).
    ///
    /// `GET /session/{id}/message`
    package func listMessages(
        sessionID: String,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "session/\(sessionID)/message")
    }

    // MARK: - Permission Response

    /// Respond to a permission request.
    ///
    /// `POST /session/{id}/permissions/{permId}`
    package func respondToPermission(
        sessionID: String,
        permissionID: String,
        decision: OpenCodePermissionDecision,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        let body: JSONValue = .object([
            "allow": .bool(decision.allow),
            "reason": decision.reason.map { .string($0) } ?? .null,
        ])
        return try await self.post(
            path: "session/\(sessionID)/permissions/\(permissionID)",
            body: body,
        )
    }

    // MARK: - Configuration

    /// Get the OpenCode configuration.
    ///
    /// `GET /config`
    package func getConfig() async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "config")
    }

    /// Get provider information.
    ///
    /// `GET /provider`
    package func getProvider() async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "provider")
    }

    /// Get the OpenAPI documentation spec.
    ///
    /// `GET /doc`
    package func getDoc() async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "doc")
    }

    // MARK: - Health Check

    /// Check if a session is alive by attempting to list its messages.
    ///
    /// Returns `true` if the server responds with 200, `false` otherwise.
    package func isSessionAlive(sessionID: String) async -> Bool {
        do {
            _ = try await self.listMessages(sessionID: sessionID)
            return true
        } catch {
            return false
        }
    }

    // MARK: Private

    private let baseURL: URL
    private let session: URLSession

    private let encoder: JSONEncoder = {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        return jsonEncoder
    }()

    private let decoder = JSONDecoder()

    // MARK: - HTTP Helpers

    private func get(path: String) async throws(OpenCodeRESTError) -> JSONValue {
        let url = self.baseURL.appendingPathComponent(path)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(from: url)
        } catch {
            throw .networkError(error)
        }

        try self.validateResponse(response, data: data)
        return try self.decodeJSON(data)
    }

    private func post(path: String, body: JSONValue?) async throws(OpenCodeRESTError) -> JSONValue {
        let url = self.baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            do {
                request.httpBody = try self.encoder.encode(body)
            } catch {
                throw .encodingFailed(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw .networkError(error)
        }

        try self.validateResponse(response, data: data)
        return try self.decodeJSON(data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws(OpenCodeRESTError) {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw .httpError(statusCode: 0, body: nil)
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw .httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }

    private func decodeJSON(_ data: Data) throws(OpenCodeRESTError) -> JSONValue {
        // Handle empty responses
        if data.isEmpty {
            return .null
        }

        do {
            return try self.decoder.decode(JSONValue.self, from: data)
        } catch {
            throw .decodingFailed(error)
        }
    }
}
