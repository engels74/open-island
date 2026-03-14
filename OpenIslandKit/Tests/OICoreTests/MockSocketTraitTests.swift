import Foundation
import Testing

@Suite(.mockSocket)
struct MockSocketTraitTests {
    @Test
    func providesASocketPath() throws {
        let path = try MockSocketTrait.path
        #expect(path.hasSuffix("test.sock"))
    }

    @Test
    func socketParentDirectoryExists() throws {
        let path = try MockSocketTrait.path
        let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        #expect(FileManager.default.fileExists(atPath: parentDir))
    }

    @Test
    func socketPathIsWithinTempDirectory() throws {
        let path = try MockSocketTrait.path
        #expect(path.contains("OICoreTests-sock-"))
    }
}
