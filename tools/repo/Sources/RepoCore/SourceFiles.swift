import Foundation

/// The files handed to swift-format, relative to the repository root. Only package manifests and
/// sources are listed, and anything under a hidden directory (such as `.build/`) is left out.
public enum SourceFiles {
    public static func app(_ slug: String, in repository: Repository) -> [String] {
        let base = repository.appPath(slug)
        return existing(["\(base)/Package.swift"], in: repository)
            + swiftFiles(under: "\(base)/Sources", in: repository)
            + swiftFiles(under: "\(base)/Tests", in: repository)
    }

    public static func tools(in repository: Repository) -> [String] {
        existing(["Package.swift"], in: repository) + swiftFiles(under: "tools/repo", in: repository)
    }

    private static func existing(_ paths: [String], in repository: Repository) -> [String] {
        paths.filter { FileManager.default.fileExists(atPath: repository.root.appending(path: $0).path) }
    }

    private static func swiftFiles(under relativeDirectory: String, in repository: Repository) -> [String] {
        let directory = repository.root.appending(path: relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            return []
        }
        var files: [String] = []
        while let path = enumerator.nextObject() as? String {
            if path.split(separator: "/").last?.hasPrefix(".") == true {
                enumerator.skipDescendants()
                continue
            }
            if path.hasSuffix(".swift") {
                files.append("\(relativeDirectory)/\(path)")
            }
        }
        return files.sorted()
    }
}
