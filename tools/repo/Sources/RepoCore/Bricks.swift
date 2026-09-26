import Foundation

/// Names and places for bricks: apps received from other repositories (tenants) made from this template.
public enum Tenants {
    /// `bricks/<tenant>/` mirrors the tenant repository, so `apps/<app>` and `packages/<name>` keep their paths.
    public static let directory = "bricks"
    public static let lockFileName = "bricks.lock"

    public static func isValidName(_ name: String) -> Bool {
        AppNames.isValidSlug(name)
    }

    public static func validateName(_ name: String) throws {
        guard isValidName(name) else {
            throw RepoError.usage("테넌트 이름 형식이 틀렸습니다: '\(name)'. 소문자로 시작하고 소문자·숫자·하이픈만 씁니다.")
        }
    }

    /// Path of a tenant's brick area, relative to the repository root.
    public static func path(_ tenant: String) -> String {
        "\(directory)/\(tenant)"
    }
}

/// `bricks.lock`: the edition and commit each tenant's bricks came from, and what was taken.
public struct BrickLock: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var source: String
        public var edition: String
        public var commit: String
        public var apps: [String]
        public var packages: [String]

        public init(source: String, edition: String, commit: String, apps: [String], packages: [String]) {
            self.source = source
            self.edition = edition
            self.commit = commit
            self.apps = apps
            self.packages = packages
        }
    }

    public var tenants: [String: Entry]

    public init(tenants: [String: Entry] = [:]) {
        self.tenants = tenants
    }

    /// The lock in `root`, or an empty lock when the file does not exist.
    public static func load(from root: URL) throws -> BrickLock {
        let url = root.appending(path: Tenants.lockFileName)
        guard FileTree.itemExists(url) else {
            return BrickLock()
        }
        do {
            return try JSONDecoder().decode(BrickLock.self, from: Data(contentsOf: url))
        } catch {
            throw RepoError.failure("\(Tenants.lockFileName) 을 해석할 수 없습니다: \(error.localizedDescription)")
        }
    }

    /// Writes the lock with sorted lists, or deletes the file when no tenant is left.
    public func write(to root: URL) throws {
        let url = root.appending(path: Tenants.lockFileName)
        guard !tenants.isEmpty else {
            if FileTree.itemExists(url) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        var sorted = self
        for (tenant, entry) in tenants {
            sorted.tenants[tenant]?.apps = Array(Set(entry.apps)).sorted()
            sorted.tenants[tenant]?.packages = Array(Set(entry.packages)).sorted()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(sorted) + Data("\n".utf8)).write(to: url, options: .atomic)
    }
}
