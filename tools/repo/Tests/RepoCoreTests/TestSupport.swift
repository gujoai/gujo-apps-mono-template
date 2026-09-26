import Foundation

@testable import RepoCore

enum TestSupport {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "repo-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The repository this test file lives in, found the same way the repo tool finds it.
    static func realRepository() throws -> Repository {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Repository.locateOrThrow(from: here)
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
