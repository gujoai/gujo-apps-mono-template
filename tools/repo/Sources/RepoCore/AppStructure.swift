import Foundation

public struct AppInfo: Encodable, Equatable, Sendable {
    public let slug: String
    public let displayName: String?
    public let version: String?
    /// `owner` for the owner's app, otherwise the tenant the brick came from.
    public let origin: String

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName
        case version
        case origin
    }

    public init(slug: String, displayName: String?, version: String?, origin: String = AppRef.ownerOrigin) {
        self.slug = slug
        self.displayName = displayName
        self.version = version
        self.origin = origin
    }

    // Missing values are written as null so every entry has the same keys.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(version, forKey: .version)
        try container.encode(origin, forKey: .origin)
    }
}

/// What every app under `apps/` must contain. `doctor` and `lint` share this check.
public enum AppStructure {
    /// `name` defaults to `app <folder name>`.
    public static func check(appDirectory: URL, name: String? = nil) -> DoctorCheck {
        let slug = appDirectory.lastPathComponent
        let fileManager = FileManager.default
        var problems: [String] = []
        if !AppNames.isValidSlug(slug) {
            problems.append("폴더 이름이 slug 형식이 아님")
        }
        for file in ["Package.swift", "README.md"]
        where !fileManager.fileExists(atPath: appDirectory.appending(path: file).path) {
            problems.append("\(file) 없음")
        }
        let versionURL = appDirectory.appending(path: "VERSION")
        if let text = try? String(contentsOf: versionURL, encoding: .utf8) {
            let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !isValidVersion(version) {
                problems.append("VERSION 형식 오류('\(version)', x.y.z 여야 함)")
            }
        } else {
            problems.append("VERSION 없음")
        }
        var isDirectory: ObjCBool = false
        let testsPath = appDirectory.appending(path: "Tests").path
        if !fileManager.fileExists(atPath: testsPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            problems.append("Tests/ 없음")
        }
        let name = name ?? "app \(slug)"
        guard problems.isEmpty else {
            return DoctorCheck(name: name, status: .fail, detail: problems.joined(separator: ", "))
        }
        return DoctorCheck(name: name, status: .ok, detail: "VERSION \(readVersion(appDirectory: appDirectory) ?? "")")
    }

    /// `x.y.z` with decimal numbers.
    public static func isValidVersion(_ text: String) -> Bool {
        SemanticVersion(text) != nil
    }

    /// The trimmed VERSION value, or nil when it is missing or not `x.y.z`.
    public static func readVersion(appDirectory: URL) -> String? {
        guard let text = try? String(contentsOf: appDirectory.appending(path: "VERSION"), encoding: .utf8) else {
            return nil
        }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidVersion(version) ? version : nil
    }

    public static func infoPlistURL(appDirectory: URL) -> URL {
        appDirectory.appending(path: "Packaging/Info.plist")
    }

    public static func readInfoPlist(appDirectory: URL) throws -> [String: Any] {
        let url = infoPlistURL(appDirectory: appDirectory)
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw RepoError.failure("Info.plist 를 읽을 수 없습니다: \(url.path)")
        }
        return plist
    }

    /// The GUI product that `run` and `bundle` use: `CFBundleExecutable` in `Packaging/Info.plist` when it is
    /// set, otherwise `<Name>App`. Apps made from the template write `<Name>App` there, so both agree.
    public static func executableProduct(appDirectory: URL, slug: String) -> String {
        let plist = try? readInfoPlist(appDirectory: appDirectory)
        if let name = plist?["CFBundleExecutable"] as? String,
            !name.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return name
        }
        return "\(AppNames.pascalCase(slug))App"
    }

    public static func info(_ app: AppRef, in repository: Repository, origin: String? = nil) -> AppInfo {
        let directory = repository.directory(of: app)
        let plist = try? readInfoPlist(appDirectory: directory)
        return AppInfo(
            slug: app.slug,
            displayName: plist?["CFBundleDisplayName"] as? String,
            version: readVersion(appDirectory: directory),
            origin: origin ?? app.origin
        )
    }
}
