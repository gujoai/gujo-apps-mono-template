import Foundation

/// `template.json`: which edition of the template this is, and which parts of the repository the template owns.
/// Everything not listed belongs to the repository's owner and is never touched by `template update`.
public struct TemplateManifest: Codable, Equatable, Sendable {
    public static let fileName = "template.json"

    public var version: String
    /// Files and directories an update replaces as a whole.
    public var managedPaths: [String]
    /// Files in which an update replaces only the text between the template markers.
    public var managedBlocks: [String]

    public init(version: String, managedPaths: [String], managedBlocks: [String]) {
        self.version = version
        self.managedPaths = managedPaths
        self.managedBlocks = managedBlocks
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(version)
    }

    /// Reads and checks `template.json` in `directory`.
    public static func load(from directory: URL) throws -> TemplateManifest {
        guard let data = try? Data(contentsOf: directory.appending(path: fileName)) else {
            throw RepoError.failure("\(fileName) 이 없습니다.")
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> TemplateManifest {
        let manifest: TemplateManifest
        do {
            manifest = try JSONDecoder().decode(TemplateManifest.self, from: data)
        } catch {
            throw RepoError.failure(
                "\(fileName) 을 해석할 수 없습니다. {\"version\": \"x.y.z\", \"managedPaths\": [...], \"managedBlocks\": [...]} 형식이어야 합니다."
            )
        }
        guard manifest.semanticVersion != nil else {
            throw RepoError.failure("\(fileName) 의 version '\(manifest.version)' 이 x.y.z 형식이 아닙니다.")
        }
        try manifest.validatePaths()
        return manifest
    }

    /// Every listed path must stay inside the repository and away from the apps and git metadata,
    /// because an update deletes and rewrites these paths.
    public func validatePaths() throws {
        for path in managedPaths + managedBlocks where !Self.isSafePath(path) {
            throw RepoError.failure("\(Self.fileName) 에 템플릿이 관리할 수 없는 경로가 있습니다: '\(path)'")
        }
    }

    /// A relative path without `.`/`..`/empty components that does not start with `apps/` or `.git`.
    public static func isSafePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = components.first,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return false
        }
        return first != "apps" && first != ".git"
    }
}
