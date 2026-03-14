import Foundation
import Testing

@Suite(.mockHTTPServer)
struct MockHTTPServerTraitTests {
    @Test
    func serverListensOnAPort() throws {
        let port = try MockHTTPServerTrait.port
        #expect(port > 0)
    }

    @Test
    func baseURLIsWellFormed() throws {
        let url = try MockHTTPServerTrait.baseURL
        #expect(url.scheme == "http")
        #expect(url.host == "127.0.0.1")
    }

    @Test
    func serverRespondsToHTTPRequest() async throws {
        let url = try MockHTTPServerTrait.baseURL
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "OK")
    }
}
