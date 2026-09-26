import Foundation

/// What adopting the template into an existing repository adds or changes. Built by
/// `TemplateAdopter.plan`, which writes nothing.
public struct AdoptPlan: Sendable {
    /// The template edition being adopted.
    public let version: String
    /// File-level changes in the target, sorted by path.
    public let changes: [TemplateChange]
    /// Managed-block files whose existing text was moved below the owner's section.
    public let movedOwnerContent: [String]
    /// Managed paths the target does not have yet.
    let pathsToCopy: [String]
    /// New contents for managed-block files, `repo.json`, and `.gitignore`.
    let fileContents: [String: String]
}

/// Brings the template into a repository that was not made from it. The template checkout this tool runs
/// in is the source. Nothing the target already has is overwritten: managed paths must be absent or equal,
/// and existing rules documents move below the owner's section.
public enum TemplateAdopter {
    public static func plan(source: Repository, target: URL, bundlePrefix: String?) throws -> AdoptPlan {
        let target = target.standardizedFileURL
        guard target.path != source.root.standardizedFileURL.path else {
            throw RepoError.usage("대상이 이 템플릿 checkout 자신입니다. 템플릿을 들일 다른 저장소의 경로를 주세요.")
        }
        if let bundlePrefix, !RepoConfig(bundlePrefix: bundlePrefix).hasValidBundlePrefix {
            throw RepoError.usage("--bundle-prefix 는 도메인을 뒤집은 형식이어야 합니다(예: com.mycompany): '\(bundlePrefix)'")
        }
        guard Git.isWorkTree(target) else {
            throw RepoError.failure("대상이 git 작업 트리가 아닙니다: \(target.path)")
        }
        let uncommitted = try Git.changedPaths(["."], in: target)
        guard uncommitted.isEmpty else {
            throw RepoError.failure(
                "대상에 커밋하지 않은 변경이 있습니다. 커밋하거나 되돌린 뒤 다시 실행하세요:\n"
                    + uncommitted.prefix(20).map { "  \($0)" }.joined(separator: "\n")
            )
        }
        guard !FileTree.itemExists(target.appending(path: TemplateManifest.fileName)) else {
            throw RepoError.failure(
                "이미 들였습니다(\(TemplateManifest.fileName) 가 있습니다). swift run repo template update 를 쓰세요.")
        }
        let manifest = try TemplateManifest.load(from: source.root)

        var changes: [TemplateChange] = []
        var pathsToCopy: [String] = []
        var conflicts: [String] = []
        for path in manifest.managedPaths {
            let templateFiles = try FileTree.snapshot(path, in: source.root, skip: FileTree.buildOutput.contains)
            guard !templateFiles.isEmpty else {
                throw RepoError.failure("템플릿 checkout 에 관리 경로 '\(path)' 가 없습니다.")
            }
            let existing = try FileTree.snapshot(path, in: target, skip: FileTree.buildOutput.contains)
            if existing.isEmpty {
                pathsToCopy.append(path)
                changes += templateFiles.keys.map { TemplateChange(.added, $0) }
            } else {
                conflicts += FileTree.compare(existing, templateFiles).map(\.path)
            }
        }
        guard conflicts.isEmpty else {
            throw RepoError.failure(
                "관리 경로에 템플릿과 내용이 다른 파일이 있습니다. 옮기거나 지운 뒤 다시 실행하세요:\n"
                    + conflicts.sorted().map { "  \($0)" }.joined(separator: "\n")
            )
        }

        var fileContents: [String: String] = [:]
        var moved: [String] = []
        for file in manifest.managedBlocks {
            let templateText = try readText(file, in: source.root, missing: "템플릿 checkout 에 \(file) 이 없습니다.")
            _ = try ManagedBlock.innerRange(of: templateText, file: file)
            let url = target.appending(path: file)
            guard FileTree.itemExists(url) else {
                fileContents[file] = templateText
                changes.append(TemplateChange(.added, file))
                continue
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw RepoError.failure("\(file) 이 심볼릭 링크입니다. 실제 파일로 바꾼 뒤 다시 실행하세요.")
            }
            let existing = try readText(file, in: target, missing: "\(file) 을 읽을 수 없습니다.")
            let updated: String
            if ManagedBlock.hasMarkers(existing) {
                updated = try ManagedBlock.replacingBlock(in: existing, with: templateText, file: file)
            } else {
                updated = (templateText.hasSuffix("\n") ? templateText : templateText + "\n") + "\n" + existing
                moved.append(file)
            }
            if updated != existing {
                fileContents[file] = updated
                changes.append(TemplateChange(.modified, file))
            }
        }

        if !FileTree.itemExists(target.appending(path: Repository.configFileName)) {
            let templateSource = (try? source.loadConfig())?.templateSource ?? ""
            fileContents[Repository.configFileName] = try repoConfigText(
                bundlePrefix: bundlePrefix ?? RepoConfig.placeholderPrefix,
                templateSource: templateSource
            )
            changes.append(TemplateChange(.added, Repository.configFileName))
        }

        let templateIgnore = (try? readText(".gitignore", in: source.root, missing: "")) ?? ""
        let ignoreURL = target.appending(path: ".gitignore")
        var existingIgnore: String?
        if FileTree.itemExists(ignoreURL) {
            existingIgnore = try readText(".gitignore", in: target, missing: ".gitignore 를 읽을 수 없습니다.")
        }
        let present = Set(
            (existingIgnore ?? "").split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces)
            })
        let missingLines = templateIgnore.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
                && !present.contains($0.trimmingCharacters(in: .whitespaces))
        }
        if !missingLines.isEmpty {
            var text = existingIgnore ?? ""
            if !text.isEmpty && !text.hasSuffix("\n") {
                text += "\n"
            }
            fileContents[".gitignore"] = text + missingLines.joined(separator: "\n") + "\n"
            changes.append(TemplateChange(existingIgnore == nil ? .added : .modified, ".gitignore"))
        }

        return AdoptPlan(
            version: manifest.version,
            changes: changes.sorted { $0.path < $1.path },
            movedOwnerContent: moved,
            pathsToCopy: pathsToCopy,
            fileContents: fileContents
        )
    }

    /// Writes a plan made by `plan(source:target:bundlePrefix:)` from the same source.
    public static func apply(_ plan: AdoptPlan, source: Repository, target: URL) throws {
        let fileManager = FileManager.default
        do {
            for path in plan.pathsToCopy {
                let destination = target.appending(path: path)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileTree.copy(
                    source.root.appending(path: path), to: destination, skip: FileTree.buildOutput.contains)
            }
            for (file, text) in plan.fileContents.sorted(by: { $0.key < $1.key }) {
                try Data(text.utf8).write(to: target.appending(path: file), options: .atomic)
            }
        } catch {
            throw RepoError.failure(
                "템플릿을 들이다 실패했습니다: \(error.localizedDescription)\n"
                    + "일부만 바뀌었을 수 있습니다. 대상에서 git status 로 확인하고 git restore 와 git clean 으로 되돌리세요."
            )
        }
    }

    /// `repo.json` for a repository that has none, in the same layout as the template's.
    static func repoConfigText(bundlePrefix: String, templateSource: String) throws -> String {
        func quoted(_ value: String) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        return """
            {
              "bundlePrefix": \(try quoted(bundlePrefix)),
              "templateSource": \(try quoted(templateSource)),
              "tenants": {}
            }

            """
    }

    private static func readText(_ file: String, in root: URL, missing message: String) throws -> String {
        guard let text = try? String(contentsOf: root.appending(path: file), encoding: .utf8) else {
            throw RepoError.failure(message)
        }
        return text
    }
}
