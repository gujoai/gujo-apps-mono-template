import Foundation
import Testing

@testable import __NAME__Core

struct ItemStoreTests {
    func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "__name__-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func addListDoneRemove() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ItemStore(directory: directory)
        #expect(try store.list().isEmpty)

        let first = try store.add(title: "  first  ")
        let second = try store.add(title: "second")
        #expect(try store.list() == [first, second])
        #expect(first.title == "first")

        try store.setDone(id: first.id, true)
        #expect(try store.list().map(\.isDone) == [true, false])
        try store.setDone(id: first.id, false)
        #expect(try store.list().map(\.isDone) == [false, false])

        try store.remove(id: first.id)
        #expect(try store.list() == [second])
    }

    @Test func reopenedStoreKeepsItems() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = try ItemStore(directory: directory).add(title: "kept")
        try ItemStore(directory: directory).setDone(id: item.id, true)

        let reopened = try ItemStore(directory: directory).list()

        #expect(reopened.map(\.id) == [item.id])
        #expect(reopened.first?.title == "kept")
        #expect(reopened.first?.isDone == true)
        #expect(reopened.first?.createdAt == item.createdAt)
    }

    @Test(arguments: ["", "   ", "\n"])
    func emptyTitleIsAnError(_ title: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ItemStore(directory: directory)

        #expect(throws: ItemStoreError.emptyTitle) {
            try store.add(title: title)
        }
        #expect(try store.list().isEmpty)
    }

    @Test func missingItemIsAnError() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ItemStore(directory: directory)
        let id = UUID()

        #expect(throws: ItemStoreError.notFound(id)) {
            try store.setDone(id: id, true)
        }
        #expect(throws: ItemStoreError.notFound(id)) {
            try store.remove(id: id)
        }
    }

    @Test func findsItemByIDPrefix() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ItemStore(directory: directory)
        let item = try store.add(title: "only")

        #expect(try store.item(matchingIDPrefix: item.shortID) == item)
        #expect(try store.item(matchingIDPrefix: item.shortID.uppercased()) == item)
        #expect(throws: ItemStoreError.noMatch("")) {
            try store.item(matchingIDPrefix: "")
        }
    }

    @Test func sharedIDPrefixIsAmbiguous() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ItemStore(directory: directory)
        var items: [Item] = []
        // With 17 items, two of them are bound to share their first hex digit.
        for index in 0..<17 {
            items.append(try store.add(title: "item \(index)"))
        }
        let prefixes = items.map { String($0.shortID.prefix(1)) }
        let shared = try #require(prefixes.first { prefix in prefixes.filter { $0 == prefix }.count > 1 })
        let count = prefixes.filter { $0 == shared }.count

        #expect(throws: ItemStoreError.ambiguous(shared, count: count)) {
            try store.item(matchingIDPrefix: shared)
        }
    }

    @Test func dataDirectoryComesFromEnvironment() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "data", directoryHint: .isDirectory)

        let resolved = try AppDataLocation.directory(environment: [AppDataLocation.environmentKey: target.path])

        #expect(resolved.standardizedFileURL.path == target.standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }
}
