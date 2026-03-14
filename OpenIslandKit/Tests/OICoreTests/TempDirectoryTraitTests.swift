import Foundation
import Testing

@Suite(.tempDirectory)
struct TempDirectoryTraitTests {
    @Test
    func createsAUniqueTemporaryDirectory() throws {
        let url = try TempDirectoryTrait.url
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func directoryIsWritable() throws {
        let url = try TempDirectoryTrait.url
        let file = url.appendingPathComponent("test.txt")
        try Data("hello".utf8).write(to: file)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func eachTestGetsAUniqueDirectory() throws {
        let url = try TempDirectoryTrait.url
        #expect(url.lastPathComponent.hasPrefix("OICoreTests-"))
    }
}
