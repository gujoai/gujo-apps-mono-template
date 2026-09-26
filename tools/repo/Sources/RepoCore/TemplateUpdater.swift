import Foundation

public struct TemplateChange: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case added
        case modified
        case deleted
    }

    public let kind: Kind
    public let path: String

    public init(_ kind: Kind, _ path: String) {
        self.kind = kind
        self.path = path
    }
}

/// What an update from `current` to `target` changes. Built by `TemplateUpdater.plan`, which writes nothing.
public struct TemplatePlan: Sendable {
    public let current: TemplateManifest
    public let target: TemplateManifest
    /// File-level changes, sorted by path.
    public let changes: [TemplateChange]
    /// Managed paths that differ from the target edition and are replaced as a whole.
    let pathsToReplace: [String]
    /// Managed paths only the current edition lists, which are deleted.
    let pathsToRemove: [String]
    /// New contents for managed-block files whose template block changes.
    let blockContents: [String: String]
}

/// Replaces the template-owned parts of a repository with another edition of the template.
/// Nothing is merged: managed paths are replaced whole, and in managed-block files only the text
/// between the markers is replaced.
public enum TemplateUpdater {
    /// Ignored build and Finder files are not compared, so they do not count as local changes.
    static let ignoredNames: Set<String> = [".DS_Store", ".build", ".swiftpm"]

    /// Everything an update may touch: the managed paths of both editions and the managed-block files.
    public static func targets(current: TemplateManifest, target: TemplateManifest) -> [String] {
        var seen = Set<String>()
        return (current.managedPaths + target.managedPaths + current.managedBlocks + target.managedBlocks)
            .filter { seen.insert($0).inserted }
    }

    /// Managed paths the current edition lists and the target edition no longer does.
    public static func removedPaths(current: TemplateManifest, target: TemplateManifest) -> [String] {
        current.managedPaths.filter { !target.managedPaths.contains($0) }
    }

    /// Checks that the update is safe and works out every change, without writing anything.
    /// `templateTree` is a checkout of the target edition.
    public static func plan(repository: Repository, templateTree: URL) throws -> TemplatePlan {
        let root = repository.root
        let current = try TemplateManifest.load(from: root)
        let target: TemplateManifest
        do {
            target = try TemplateManifest.load(from: templateTree)
        } catch let error as RepoError {
            throw RepoError.failure("받아 온 판: \(error.message)")
        }

        guard Git.isWorkTree(root) else {
            throw RepoError.failure("저장소 루트가 git 작업 트리가 아닙니다. 업데이트 전후를 비교할 수 있도록 git 저장소에서 실행하세요.")
        }
        let uncommitted = try Git.changedPaths(targets(current: current, target: target), in: root)
        guard uncommitted.isEmpty else {
            throw RepoError.failure(
                "관리 영역에 커밋하지 않은 변경이 있습니다. 커밋하거나 되돌린 뒤 다시 실행하세요:\n"
                    + uncommitted.map { "  \($0)" }.joined(separator: "\n")
            )
        }
        for path in target.managedPaths where !itemExists(templateTree.appending(path: path)) {
            throw RepoError.failure("받아 온 판에 managedPaths 의 '\(path)' 가 없습니다.")
        }

        var blockContents: [String: String] = [:]
        var changes: [TemplateChange] = []
        for file in target.managedBlocks {
            guard let text = try? String(contentsOf: root.appending(path: file), encoding: .utf8) else {
                throw RepoError.failure("\(file) 이 없습니다. 템플릿 구역을 교체할 수 없습니다.")
            }
            guard let templateText = try? String(contentsOf: templateTree.appending(path: file), encoding: .utf8)
            else {
                throw RepoError.failure("받아 온 판에 \(file) 이 없습니다.")
            }
            let updated = try ManagedBlock.replacingBlock(in: text, with: templateText, file: file)
            if updated != text {
                blockContents[file] = updated
                changes.append(TemplateChange(.modified, file))
            }
        }

        var pathsToReplace: [String] = []
        for path in target.managedPaths {
            let pathChanges = try compare(
                snapshot(path, in: root),
                snapshot(path, in: templateTree)
            )
            if !pathChanges.isEmpty {
                pathsToReplace.append(path)
                changes += pathChanges
            }
        }
        var pathsToRemove: [String] = []
        for path in removedPaths(current: current, target: target) where itemExists(root.appending(path: path)) {
            pathsToRemove.append(path)
            changes += try snapshot(path, in: root).keys.map { TemplateChange(.deleted, $0) }
        }

        return TemplatePlan(
            current: current,
            target: target,
            changes: changes.sorted { $0.path < $1.path },
            pathsToReplace: pathsToReplace,
            pathsToRemove: pathsToRemove,
            blockContents: blockContents
        )
    }

    /// Writes a plan made by `plan(repository:templateTree:)` from the same `templateTree`.
    public static func apply(_ plan: TemplatePlan, repository: Repository, templateTree: URL) throws {
        let fileManager = FileManager.default
        let root = repository.root
        do {
            for path in plan.pathsToRemove {
                try fileManager.removeItem(at: root.appending(path: path))
            }
            for path in plan.pathsToReplace {
                let destination = root.appending(path: path)
                if itemExists(destination) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try copyItem(templateTree.appending(path: path), to: destination)
            }
            for (file, text) in plan.blockContents.sorted(by: { $0.key < $1.key }) {
                try Data(text.utf8).write(to: root.appending(path: file), options: .atomic)
            }
        } catch {
            throw RepoError.failure(
                "관리 영역을 교체하다 실패했습니다: \(error.localizedDescription)\n"
                    + "일부만 바뀌었을 수 있습니다. git status 로 확인하고 git restore 와 git clean 으로 되돌리세요."
            )
        }
    }

    enum Entry: Equatable {
        case file(Data)
        case link(String)
    }

    /// Files and symbolic links at or under `path`, keyed by their path relative to `root`.
    static func snapshot(_ path: String, in root: URL) throws -> [String: Entry] {
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
            for name in try fileManager.contentsOfDirectory(atPath: url.path) where !ignoredNames.contains(name) {
                entries.merge(try snapshot("\(path)/\(name)", in: root)) { _, new in new }
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

    /// Copies a file or directory tree, recreating symbolic links as links.
    static func copyItem(_ source: URL, to destination: URL) throws {
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
            for name in try fileManager.contentsOfDirectory(atPath: source.path) {
                try copyItem(source.appending(path: name), to: destination.appending(path: name))
            }
        default:
            try fileManager.copyItem(at: source, to: destination)
        }
    }
}
