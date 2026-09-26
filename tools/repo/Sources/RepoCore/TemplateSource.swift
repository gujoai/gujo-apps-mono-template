import Foundation

/// Where template editions come from: a git repository whose `vX.Y.Z` tags are the editions.
public enum TemplateSource {
    /// URLs (`https://…`, `file://…`) and scp-style addresses (`git@host:org/repo.git`) are kept as they are.
    /// Anything else is a local path and is made absolute against `base`.
    public static func resolve(_ source: String, relativeTo base: URL) -> String {
        if isRemote(source) {
            return source
        }
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source).standardizedFileURL.path
        }
        if source == "~" || source.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appending(path: String(source.dropFirst(2))).standardizedFileURL.path
        }
        return base.appending(path: source).standardizedFileURL.path
    }

    static func isRemote(_ source: String) -> Bool {
        if source.contains("://") {
            return true
        }
        guard let colon = source.firstIndex(of: ":") else {
            return false
        }
        return !source[..<colon].contains("/")
    }

    /// Template editions in `git ls-remote --tags --refs` output, oldest first.
    /// Tags that are not exactly `vX.Y.Z` are ignored.
    public static func parseTags(_ lsRemoteOutput: String) -> [SemanticVersion] {
        let prefix = "refs/tags/v"
        let versions = lsRemoteOutput.split(whereSeparator: \.isNewline).compactMap { line -> SemanticVersion? in
            guard let ref = line.split(separator: "\t").last, ref.hasPrefix(prefix) else {
                return nil
            }
            return SemanticVersion(String(ref.dropFirst(prefix.count)))
        }
        return Array(Set(versions)).sorted()
    }

    public static func versions(of source: String, workingDirectory: URL) throws -> [SemanticVersion] {
        let output = try Git.output(["ls-remote", "--tags", "--refs", source], in: workingDirectory)
        return parseTags(output)
    }

    /// Shallow-clones tag `v<version>` into `destination`, which must not exist yet.
    /// Local paths become `file://` URLs so that `--depth` applies.
    public static func fetch(
        _ source: String,
        version: SemanticVersion,
        into destination: URL,
        workingDirectory: URL
    ) throws {
        let url = source.hasPrefix("/") ? URL(fileURLWithPath: source).absoluteString : source
        _ = try Git.output(
            [
                "-c", "advice.detachedHead=false", "clone", "--quiet", "--depth", "1", "--branch", "v\(version)",
                url, destination.path,
            ],
            in: workingDirectory
        )
    }
}
