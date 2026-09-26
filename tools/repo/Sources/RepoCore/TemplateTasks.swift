import Foundation

public struct TemplateStatus: Encodable, Equatable, Sendable {
    public let current: String
    public let source: String
    /// Every edition the source has, oldest first.
    public let versions: [String]
    public let latest: String?
    public let updateAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case current
        case source
        case versions
        case latest
        case updateAvailable
    }

    // `latest` is written as null when the source has no editions, so the keys never change.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(current, forKey: .current)
        try container.encode(source, forKey: .source)
        try container.encode(versions, forKey: .versions)
        try container.encode(latest, forKey: .latest)
        try container.encode(updateAvailable, forKey: .updateAvailable)
    }
}

public enum TemplateUpdateOutcome: Sendable {
    /// The repository already matches the edition.
    case upToDate(String)
    /// `--dry-run`: what would change. Nothing was written.
    case planned(TemplatePlan)
    /// The managed parts were replaced. `changedPaths` come from `git status --porcelain`.
    case applied(TemplatePlan, changedPaths: [String])
}

public enum TemplateAdoptOutcome: Sendable {
    /// `--dry-run`: what would change. Nothing was written.
    case planned(AdoptPlan)
    /// The template was brought in. `changedPaths` come from `git status --porcelain` in the target.
    case applied(AdoptPlan, target: URL, changedPaths: [String])
}

/// `repo template status` and `repo template update`.
public struct TemplateTasks {
    public let repository: Repository
    /// Base for a relative `--from` path; a relative `templateSource` in repo.json is relative to the repository root.
    let workingDirectory: URL

    public init(repository: Repository, workingDirectory: URL) {
        self.repository = repository
        self.workingDirectory = workingDirectory
    }

    public func status(from source: String?) throws -> TemplateStatus {
        let current = try TemplateManifest.load(from: repository.root)
        let source = try resolveSource(source)
        let versions = try TemplateSource.versions(of: source, workingDirectory: repository.root)
        let latest = versions.last
        var updateAvailable = false
        if let latest, let currentVersion = current.semanticVersion {
            updateAvailable = latest > currentVersion
        }
        return TemplateStatus(
            current: current.version,
            source: source,
            versions: versions.map(\.description),
            latest: latest?.description,
            updateAvailable: updateAvailable
        )
    }

    public func update(to requested: String?, from source: String?, dryRun: Bool) throws -> TemplateUpdateOutcome {
        let requestedVersion = try requested.map { text in
            guard let version = SemanticVersion(text) else {
                throw RepoError.usage("--to 는 x.y.z 형식이어야 합니다: '\(text)'")
            }
            return version
        }
        let current = try TemplateManifest.load(from: repository.root)
        let source = try resolveSource(source)
        let versions = try TemplateSource.versions(of: source, workingDirectory: repository.root)
        let version: SemanticVersion
        if let requestedVersion {
            guard versions.contains(requestedVersion) else {
                throw RepoError.failure("출처에 v\(requestedVersion) 태그가 없습니다. 있는 판: \(describe(versions))")
            }
            version = requestedVersion
        } else {
            guard let latest = versions.last else {
                throw RepoError.failure("출처에 vX.Y.Z 형식의 태그가 없습니다: \(source)")
            }
            if let currentVersion = current.semanticVersion, latest < currentVersion {
                throw RepoError.failure(
                    "출처의 가장 새 판(\(latest))이 현재 판(\(currentVersion))보다 낮습니다. 그 판으로 되돌리려면 --to \(latest) 를 주세요."
                )
            }
            version = latest
        }

        let checkout = FileManager.default.temporaryDirectory
            .appending(path: "repo-template-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: checkout) }
        try TemplateSource.fetch(source, version: version, into: checkout, workingDirectory: repository.root)
        let fetched = try TemplateManifest.load(from: checkout)
        guard fetched.semanticVersion == version else {
            throw RepoError.failure("태그와 template.json 버전이 다릅니다: 태그 v\(version), template.json \(fetched.version)")
        }

        let plan = try TemplateUpdater.plan(repository: repository, templateTree: checkout)
        if plan.changes.isEmpty && plan.current.version == plan.target.version {
            return .upToDate(plan.target.version)
        }
        if dryRun {
            return .planned(plan)
        }
        try TemplateUpdater.apply(plan, repository: repository, templateTree: checkout)
        let changed = try Git.changedPaths(
            TemplateUpdater.targets(current: plan.current, target: plan.target),
            in: repository.root
        )
        return .applied(plan, changedPaths: changed)
    }

    /// Brings this checkout's template into the repository at `target`, which was not made from it.
    public func adopt(target: String, bundlePrefix: String?, dryRun: Bool) throws -> TemplateAdoptOutcome {
        let url =
            target.hasPrefix("/")
            ? URL(fileURLWithPath: target, isDirectory: true) : workingDirectory.appending(path: target)
        let plan = try TemplateAdopter.plan(source: repository, target: url, bundlePrefix: bundlePrefix)
        if dryRun {
            return .planned(plan)
        }
        try TemplateAdopter.apply(plan, source: repository, target: url)
        return .applied(plan, target: url.standardizedFileURL, changedPaths: try Git.changedPaths(["."], in: url))
    }

    /// `--from` when given, otherwise `templateSource` from repo.json.
    func resolveSource(_ option: String?) throws -> String {
        if let option, !option.isEmpty {
            return TemplateSource.resolve(option, relativeTo: workingDirectory)
        }
        let configured = try repository.loadConfig().templateSource ?? ""
        guard !configured.isEmpty else {
            throw RepoError.usage(
                "템플릿 출처가 없습니다. --from <git 주소 또는 경로> 를 주거나 repo.json 의 templateSource 를 채우세요."
            )
        }
        return TemplateSource.resolve(configured, relativeTo: repository.root)
    }

    private func describe(_ versions: [SemanticVersion]) -> String {
        versions.isEmpty ? "(없음)" : versions.map(\.description).joined(separator: ", ")
    }
}
