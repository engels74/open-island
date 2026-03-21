package import Foundation
package import OICore

// MARK: - OpenCodeRESTError

package enum OpenCodeRESTError: Error, Sendable {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String?)
    case encodingFailed(any Error)
    case decodingFailed(any Error)
    case networkError(any Error)
}

// MARK: - OpenCodePermissionDecision

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

/// REST API client for the OpenCode HTTP server.
package actor OpenCodeRESTClient {
    // MARK: Lifecycle

    package init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Package

    // MARK: - Session Management

    package func createSession(
        directory: String? = nil,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        var body: [String: JSONValue] = [:]
        if let directory {
            body["directory"] = .string(directory)
        }
        return try await self.post(path: "session", body: .object(body))
    }

    package func sendPrompt(
        sessionID: String,
        message: String,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        let body: JSONValue = .object(["message": .string(message)])
        return try await self.post(path: "session/\(sessionID)/prompt", body: body)
    }

    package func abortSession(
        sessionID: String,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        try await self.post(path: "session/\(sessionID)/abort", body: nil)
    }

    package func listMessages(
        sessionID: String,
    ) async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "session/\(sessionID)/message")
    }

    // MARK: - Permission Response

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

    package func getConfig() async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "config")
    }

    package func getProvider() async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "provider")
    }

    package func getDoc() async throws(OpenCodeRESTError) -> JSONValue {
        try await self.get(path: "doc")
    }

    // MARK: - Health Check

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
