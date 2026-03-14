import Foundation
import Testing

@Suite(.mockHTTPServer)
struct MockHTTPServerTraitTests {
    @Test
    func `server listens on A port`() throws {
        let port = try MockHTTPServerTrait.port
        #expect(port > 0)
    }

    @Test
    func `base URL is well formed`() throws {
        let url = try MockHTTPServerTrait.baseURL
        #expect(url.scheme == "http")
        #expect(url.host == "127.0.0.1")
    }

    @Test
    func `server responds to HTTP request`() async throws {
        let url = try MockHTTPServerTrait.baseURL
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "OK")
    }
}
