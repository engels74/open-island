import Foundation
import Testing

@Suite(.mockSocket)
struct MockSocketTraitTests {
    @Test
    func `provides A socket path`() throws {
        let path = try MockSocketTrait.path
        #expect(path.hasSuffix("test.sock"))
    }

    @Test
    func `socket parent directory exists`() throws {
        let path = try MockSocketTrait.path
        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        #expect(FileManager.default.fileExists(atPath: parentDir))
    }

    @Test
    func `socket path is within temp directory`() throws {
        let path = try MockSocketTrait.path
        #expect(path.contains("OICoreTests-sock-"))
    }
}
