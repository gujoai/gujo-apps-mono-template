import Foundation

public struct RepoConfig: Codable, Equatable, Sendable {
    public static let placeholderPrefix = "com.example"

    public var bundlePrefix: String
    /// Git URL or local path of the template this repository updates from. Empty until the template is published.
    public var templateSource: String?

    public init(bundlePrefix: String, templateSource: String? = nil) {
        self.bundlePrefix = bundlePrefix
        self.templateSource = templateSource
    }

    /// Reverse-DNS form such as `com.mycompany`: letters, digits, hyphens, and dots between parts.
    public var hasValidBundlePrefix: Bool {
        let parts = bundlePrefix.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty
            && parts.allSatisfy { part in
                !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            }
    }
}

/// The repository root: the nearest directory, from the working directory upward, that holds `repo.json`.
public struct Repository: Sendable {
    public static let configFileName = "repo.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func locate(from directory: URL) -> Repository? {
        var current = directory.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appending(path: configFileName).path) {
                return Repository(root: current)
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    public static func locateOrThrow(from directory: URL) throws -> Repository {
        guard let repository = locate(from: directory) else {
            throw RepoError.failure("현재 디렉터리와 그 위에서 \(configFileName) 을 찾지 못했습니다. 저장소 안에서 실행하세요.")
        }
        return repository
    }

    public var appsDirectory: URL {
        root.appending(path: "apps", directoryHint: .isDirectory)
    }

    public var templateDirectory: URL {
        root.appending(path: "templates/macos-app", directoryHint: .isDirectory)
    }

    public func appDirectory(_ slug: String) -> URL {
        appsDirectory.appending(path: slug, directoryHint: .isDirectory)
    }

    /// Path of an app relative to the root, as passed to child processes (which run in the root).
    public func appPath(_ slug: String) -> String {
        "apps/\(slug)"
    }

    public func loadConfig() throws -> RepoConfig {
        let url = root.appending(path: Self.configFileName)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RepoError.failure("\(Self.configFileName) 을 읽을 수 없습니다.")
        }
        do {
            return try JSONDecoder().decode(RepoConfig.self, from: data)
        } catch {
            throw RepoError.failure(
                "\(Self.configFileName) 을 해석할 수 없습니다. {\"bundlePrefix\": \"com.mycompany\"} 형식이어야 합니다."
            )
        }
    }

    /// Directory names under `apps/`, sorted. Hidden entries and files are skipped.
    public func appSlugs() throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: appsDirectory.path) else {
            return []
        }
        return try fileManager.contentsOfDirectory(atPath: appsDirectory.path)
            .filter { name in
                var isDirectory: ObjCBool = false
                let path = appsDirectory.appending(path: name).path
                return !name.hasPrefix(".") && fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            .sorted()
    }

    /// The apps a command works on: the given slugs, or every app when none are given.
    public func selectApps(_ slugs: [String]) throws -> [String] {
        guard !slugs.isEmpty else {
            return try appSlugs()
        }
        let existing = Set(try appSlugs())
        for slug in slugs {
            try AppNames.validateSlug(slug)
            guard existing.contains(slug) else {
                throw RepoError.failure("앱이 없습니다: \(appPath(slug)). `swift run repo list` 로 목록을 보세요.")
            }
        }
        return slugs
    }
}
