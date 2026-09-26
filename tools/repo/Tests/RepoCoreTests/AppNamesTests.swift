import Testing

@testable import RepoCore

struct AppNamesTests {
    @Test(arguments: ["notes", "memo-board", "a", "app2", "app-2d", "a-b-c"])
    func acceptsValidSlugs(_ slug: String) {
        #expect(AppNames.isValidSlug(slug))
    }

    @Test(arguments: ["", "Notes", "1notes", "memo_board", "memo--board", "-memo", "memo-", "memo board", "메모", "é"])
    func rejectsInvalidSlugs(_ slug: String) {
        #expect(!AppNames.isValidSlug(slug))
    }

    @Test func invalidSlugIsUsageError() {
        let error = #expect(throws: RepoError.self) {
            try AppNames(slug: "Memo", bundlePrefix: "com.example")
        }
        #expect(error?.exitCode == ExitCode.usage)
    }

    @Test func derivesNamesFromSlug() throws {
        let names = try AppNames(slug: "memo-board", bundlePrefix: "com.mycompany")
        #expect(names.name == "MemoBoard")
        #expect(names.displayName == "Memo Board")
        #expect(names.bundleIdentifier == "com.mycompany.memo-board")
        #expect(names.dataEnvironmentKey == "MEMO_BOARD_DATA_DIR")
    }

    @Test func derivesNamesFromSingleWordSlug() throws {
        let names = try AppNames(slug: "notes", bundlePrefix: "com.example")
        #expect(names.name == "Notes")
        #expect(names.displayName == "Notes")
        #expect(names.dataEnvironmentKey == "NOTES_DATA_DIR")
    }

    @Test func pascalCaseKeepsDigits() {
        #expect(AppNames.pascalCase("app-2d") == "App2d")
        #expect(AppNames.defaultDisplayName("app-2d") == "App 2d")
    }

    @Test func usesGivenDisplayName() throws {
        let names = try AppNames(slug: "memo-board", displayName: "  메모 보드 ", bundlePrefix: "com.example")
        #expect(names.displayName == "메모 보드")
    }

    @Test(arguments: ["", "   ", "Memo \"Board\"", "a/b", "a\\b", "a<b", "a&b", "a:b", "line\nbreak"])
    func rejectsUnsafeDisplayNames(_ displayName: String) {
        #expect(throws: RepoError.self) {
            try AppNames.validateDisplayName(displayName)
        }
    }
}
