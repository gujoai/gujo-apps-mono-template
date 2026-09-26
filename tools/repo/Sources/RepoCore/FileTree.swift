import Foundation

/// File-tree helpers shared by `template update` and `brick`: compare two trees and copy one into place.
enum FileTree {
    enum Entry: Equatable {
        case file(Data)
        case link(String)
    }

    /// Build output and Finder files. They are ignored by git, so they never count as changes.
    static let buildOutput: Set<String> = [".DS_Store", ".build", ".swiftpm"]

    /// Files and symbolic links at or under `path`, keyed by their path relative to `root`.
    /// Entries whose name `skip` accepts are left out, along with everything below them.
    static func snapshot(_ path: String, in root: URL, skip: (String) -> Bool) throws -> [String: Entry] {
        let fileManager = FileManager.default
        let url = root.appending(path: path)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return [:]
        }
        switch attributes[.type] as? FileAttributeType {
        case .typeSymbolicLink:
            return [path: .link(try fileManager.destinationOfSymbolicLink(atPath: url.path))]
        case .typeDirectory:
            var entries: [String: Entry] = [:]
            for name in try fileManager.contentsOfDirectory(atPath: url.path) where !skip(name) {
                entries.merge(try snapshot("\(path)/\(name)", in: root, skip: skip)) { _, new in new }
            }
            return entries
        default:
            return [path: .file(try Data(contentsOf: url))]
        }
    }

    static func compare(_ current: [String: Entry], _ target: [String: Entry]) -> [TemplateChange] {
        var changes: [TemplateChange] = []
        for (path, entry) in target {
            if let existing = current[path] {
                if existing != entry {
                    changes.append(TemplateChange(.modified, path))
                }
            } else {
                changes.append(TemplateChange(.added, path))
            }
        }
        for path in current.keys where target[path] == nil {
            changes.append(TemplateChange(.deleted, path))
        }
        return changes
    }

    /// Like `FileManager.fileExists`, but a symbolic link counts even when its target is missing.
    static func itemExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Copies a file or directory tree, recreating symbolic links as links and leaving out names `skip` accepts.
    static func copy(_ source: URL, to destination: URL, skip: (String) -> Bool) throws {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        switch attributes[.type] as? FileAttributeType {
        case .typeSymbolicLink:
            try fileManager.createSymbolicLink(
                atPath: destination.path,
                withDestinationPath: fileManager.destinationOfSymbolicLink(atPath: source.path)
            )
        case .typeDirectory:
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in try fileManager.contentsOfDirectory(atPath: source.path) where !skip(name) {
                try copy(source.appending(path: name), to: destination.appending(path: name), skip: skip)
            }
        default:
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    /// Names of the directories directly inside `url`, sorted. Hidden entries and files are left out.
    static func subdirectories(of url: URL) -> [String] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return []
        }
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return !name.hasPrefix(".")
                && fileManager.fileExists(atPath: url.appending(path: name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        .sorted()
    }
}
