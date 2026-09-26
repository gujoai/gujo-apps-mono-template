import Foundation

/// An edition of a tenant and the apps it offers.
public struct BrickAvailability: Encodable, Sendable {
    public let tenant: String
    public let edition: String
    public let commit: String
    /// Every edition the tenant has, oldest first.
    public let editions: [String]
    public let apps: [AppInfo]
}

/// What a brick command changed. Nothing is committed.
public struct BrickResult: Sendable {
    public let tenant: String
    /// The tenant's edition afterwards, or nil when none of its bricks are left.
    public let edition: String?
    public let previousEdition: String?
    /// Paths with changes, from `git status --porcelain`.
    public let changedPaths: [String]
    /// `.package(url:)` dependencies of the received apps and packages.
    public let externalPackages: [String]
    /// Context files (AGENTS.md, CLAUDE.md) in the tenant's code that were not copied.
    public let skippedContextFiles: [String]
}

public enum BrickUpdateOutcome: Sendable {
    /// The installed bricks already match the edition.
    case upToDate(tenant: String, edition: String)
    /// `--dry-run`: what would change. Nothing was written.
    case planned(tenant: String, from: String, to: String, changes: [TemplateChange])
    case applied(BrickResult)
}

/// `repo brick`: takes apps (bricks) from registered tenants into `bricks/<tenant>/` and records them in
/// `bricks.lock`. Every command checks first and writes nothing when a check fails, and none of them commit.
public struct BrickTasks {
    public let repository: Repository

    public init(repository: Repository) {
        self.repository = repository
    }

    var root: URL {
        repository.root
    }

    public func list() throws -> BrickLock {
        try BrickLock.load(from: root)
    }

    public func available(_ tenant: String, edition requested: String?) throws -> BrickAvailability {
        try Tenants.validateName(tenant)
        let source = try registeredSource(tenant)
        let versions = try TemplateSource.versions(of: source.resolved, workingDirectory: root)
        let version = try chooseEdition(try parseEdition(requested), from: versions, tenant: tenant, current: nil)
        return try withCheckout(of: tenant, source: source.resolved, edition: version) { checkout, commit in
            let tenantRepository = Repository(root: checkout)
            let apps = FileTree.subdirectories(of: checkout.appending(path: "apps"))
                .filter { FileTree.itemExists(checkout.appending(path: "apps/\($0)/Package.swift")) }
                .map { AppStructure.info(AppRef(slug: $0), in: tenantRepository, origin: tenant) }
            return BrickAvailability(
                tenant: tenant,
                edition: version.description,
                commit: commit,
                editions: versions.map(\.description),
                apps: apps
            )
        }
    }

    @discardableResult
    public func add(_ app: AppRef, edition requested: String?) throws -> BrickResult {
        let tenant = try brickTenant(of: app, command: "add")
        let source = try registeredSource(tenant)
        var lock = try BrickLock.load(from: root)
        let existing = lock.tenants[tenant]
        if let existing, existing.apps.contains(app.slug) {
            throw RepoError.failure("이미 받은 블록입니다: \(app). 새 판은 swift run repo brick update \(tenant) 로 받습니다.")
        }
        let requestedVersion = try parseEdition(requested)
        if let existing, let requestedVersion, requestedVersion.description != existing.edition {
            throw RepoError.failure(
                "테넌트 \(tenant) 의 블록은 판 \(existing.edition) 에서 받았습니다. 한 테넌트의 블록은 한 판에서만 받습니다. "
                    + "판을 바꾸려면 swift run repo brick update \(tenant) --edition \(requestedVersion) 을 먼저 실행하세요."
            )
        }
        try requireWorkTree()
        let versions = try TemplateSource.versions(of: source.resolved, workingDirectory: root)
        let version: SemanticVersion
        if let existing {
            version = try recordedEdition(existing, tenant: tenant)
            guard versions.contains(version) else {
                throw RepoError.failure("테넌트 \(tenant) 에 기록된 판 v\(version) 태그가 더 이상 없습니다.")
            }
        } else {
            version = try chooseEdition(requestedVersion, from: versions, tenant: tenant, current: nil)
        }

        return try withCheckout(of: tenant, source: source.resolved, edition: version) { checkout, commit in
            if let existing {
                try requireSameCommit(existing, commit, tenant: tenant)
            }
            let appPath = "apps/\(app.slug)"
            guard FileTree.itemExists(checkout.appending(path: "\(appPath)/Package.swift")) else {
                throw RepoError.failure("테넌트 \(tenant) 의 판 \(version) 에 앱 \(app.slug) 가 없습니다.")
            }
            let dependencies = try PackageDependencies.closure(of: appPath, in: checkout)
            let installedPackages = Set(existing?.packages ?? [])
            let newPackages = dependencies.packages.filter {
                !installedPackages.contains($0)
                    || !FileTree.itemExists(tenantDirectory(tenant).appending(path: "packages/\($0)"))
            }
            let units = [appPath] + newPackages.map { "packages/\($0)" }
            // Only the paths this add writes must be clean, so several adds can be committed together.
            try requireCommitted(units.map { "\(Tenants.path(tenant))/\($0)" })
            let skipped = units.flatMap { contextFiles(in: checkout, unit: $0, tenant: tenant) }
            try write {
                for unit in units {
                    try install(unit, from: checkout, tenant: tenant)
                }
                lock.tenants[tenant] = BrickLock.Entry(
                    source: source.raw,
                    edition: version.description,
                    commit: commit,
                    apps: (existing?.apps ?? []) + [app.slug],
                    packages: (existing?.packages ?? []) + dependencies.packages
                )
                try lock.write(to: root)
            }
            return BrickResult(
                tenant: tenant,
                edition: version.description,
                previousEdition: existing?.edition,
                changedPaths: try changedPaths(tenant),
                externalPackages: dependencies.urls,
                skippedContextFiles: skipped
            )
        }
    }

    public func update(_ tenant: String, edition requested: String?, dryRun: Bool) throws -> BrickUpdateOutcome {
        try Tenants.validateName(tenant)
        let source = try registeredSource(tenant)
        var lock = try BrickLock.load(from: root)
        guard let existing = lock.tenants[tenant] else {
            throw RepoError.failure("테넌트 \(tenant) 에서 받은 블록이 없습니다. swift run repo brick add \(tenant)/<앱> 으로 받으세요.")
        }
        let requestedVersion = try parseEdition(requested)
        try requireCommitted([Tenants.path(tenant)])
        let current = try recordedEdition(existing, tenant: tenant)
        let versions = try TemplateSource.versions(of: source.resolved, workingDirectory: root)
        let version = try chooseEdition(requestedVersion, from: versions, tenant: tenant, current: current)

        return try withCheckout(of: tenant, source: source.resolved, edition: version) { checkout, commit in
            if version == current {
                try requireSameCommit(existing, commit, tenant: tenant)
            }
            for app in existing.apps where !FileTree.itemExists(checkout.appending(path: "apps/\(app)/Package.swift")) {
                throw RepoError.failure(
                    "테넌트 \(tenant) 의 판 \(version) 에 앱 \(app) 가 없습니다. 먼저 swift run repo brick remove \(tenant)/\(app) 으로 빼세요."
                )
            }
            var packages = Set<String>()
            var urls = Set<String>()
            for app in existing.apps {
                let dependencies = try PackageDependencies.closure(of: "apps/\(app)", in: checkout)
                packages.formUnion(dependencies.packages)
                urls.formUnion(dependencies.urls)
            }
            let units = existing.apps.map { "apps/\($0)" } + packages.sorted().map { "packages/\($0)" }
            var target: [String: FileTree.Entry] = [:]
            for unit in units {
                for (path, entry) in try FileTree.snapshot(unit, in: checkout, skip: Self.skipReceived) {
                    target["\(Tenants.path(tenant))/\(path)"] = entry
                }
            }
            let installed = try FileTree.snapshot(Tenants.path(tenant), in: root, skip: Self.skipInstalled)
            let changes = FileTree.compare(installed, target).sorted { $0.path < $1.path }
            if changes.isEmpty && version == current {
                return .upToDate(tenant: tenant, edition: version.description)
            }
            if dryRun {
                return .planned(tenant: tenant, from: existing.edition, to: version.description, changes: changes)
            }

            let changedUnits = units.filter { unit in
                let prefix = "\(Tenants.path(tenant))/\(unit)/"
                return changes.contains { $0.path.hasPrefix(prefix) }
            }
            let skipped = units.flatMap { contextFiles(in: checkout, unit: $0, tenant: tenant) }
            try write {
                try removeEntries(of: tenant, keeping: existing.apps, packages: packages.sorted())
                for unit in changedUnits {
                    try install(unit, from: checkout, tenant: tenant)
                }
                lock.tenants[tenant] = BrickLock.Entry(
                    source: source.raw,
                    edition: version.description,
                    commit: commit,
                    apps: existing.apps,
                    packages: packages.sorted()
                )
                try lock.write(to: root)
            }
            return .applied(
                BrickResult(
                    tenant: tenant,
                    edition: version.description,
                    previousEdition: existing.edition,
                    changedPaths: try changedPaths(tenant),
                    externalPackages: urls.sorted(),
                    skippedContextFiles: skipped
                )
            )
        }
    }

    @discardableResult
    public func remove(_ app: AppRef) throws -> BrickResult {
        let tenant = try brickTenant(of: app, command: "remove")
        var lock = try BrickLock.load(from: root)
        let entry = try installedEntry(of: app, in: lock)
        try requireCommitted([Tenants.path(tenant)])
        try write {
            try detach(app, entry: entry, lock: &lock)
        }
        return BrickResult(
            tenant: tenant,
            edition: lock.tenants[tenant]?.edition,
            previousEdition: entry.edition,
            changedPaths: try changedPaths(tenant),
            externalPackages: [],
            skippedContextFiles: []
        )
    }

    /// Copies a brick app and its packages into `apps/` and `packages/`, where the owner can change them,
    /// then removes the brick.
    @discardableResult
    public func eject(_ app: AppRef) throws -> BrickResult {
        let tenant = try brickTenant(of: app, command: "eject")
        var lock = try BrickLock.load(from: root)
        let entry = try installedEntry(of: app, in: lock)
        let tenantRoot = tenantDirectory(tenant)
        let packages = try PackageDependencies.closure(of: "apps/\(app.slug)", in: tenantRoot).packages
        let targets = ["apps/\(app.slug)"] + packages.map { "packages/\($0)" }
        for target in targets where FileTree.itemExists(root.appending(path: target)) {
            throw RepoError.failure("\(target) 가 이미 있습니다. 같은 이름이 있으면 블록을 옮길 수 없습니다.")
        }
        try requireCommitted([Tenants.path(tenant)] + targets)
        try write {
            for target in targets {
                let destination = root.appending(path: target)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileTree.copy(tenantRoot.appending(path: target), to: destination, skip: Self.skipInstalled)
            }
            try detach(app, entry: entry, lock: &lock)
        }
        return BrickResult(
            tenant: tenant,
            edition: lock.tenants[tenant]?.edition,
            previousEdition: entry.edition,
            changedPaths: try changedPaths(tenant, alsoChecking: targets),
            externalPackages: [],
            skippedContextFiles: []
        )
    }

    // MARK: - Checks

    /// Build output, git data, and Finder files are never received or compared.
    static func skipInstalled(_ name: String) -> Bool {
        FileTree.buildOutput.contains(name) || name == ".git"
    }

    /// Context files carry rules for agents. This repository keeps its rules in one root file, so a
    /// tenant's context files are not received.
    static func skipReceived(_ name: String) -> Bool {
        skipInstalled(name) || DocumentChecks.contextFileNames.contains(name.lowercased())
    }

    private func brickTenant(of app: AppRef, command: String) throws -> String {
        guard let tenant = app.tenant else {
            throw RepoError.usage("brick \(command) 는 <테넌트>/<앱> 을 받습니다: '\(app)'")
        }
        return tenant
    }

    /// The tenant's source as written in repo.json, and resolved against the repository root.
    private func registeredSource(_ tenant: String) throws -> (raw: String, resolved: String) {
        let tenants = try repository.loadConfig().tenants ?? [:]
        guard let raw = tenants[tenant], !raw.isEmpty else {
            throw RepoError.failure(
                "테넌트 \(tenant) 가 등록되어 있지 않습니다. 이 테넌트의 블록을 쓰기로 했다면 repo.json 의 tenants 에 "
                    + "\"\(tenant)\": \"<git 주소 또는 경로>\" 를 적고 커밋한 뒤 다시 실행하세요. 어느 테넌트를 믿을지는 저장소 주인이 정합니다."
            )
        }
        return (raw, TemplateSource.resolve(raw, relativeTo: root))
    }

    private func installedEntry(of app: AppRef, in lock: BrickLock) throws -> BrickLock.Entry {
        guard let tenant = app.tenant, let entry = lock.tenants[tenant], entry.apps.contains(app.slug) else {
            throw RepoError.failure("받은 블록이 아닙니다: \(app). swift run repo brick list 로 목록을 보세요.")
        }
        return entry
    }

    private func parseEdition(_ text: String?) throws -> SemanticVersion? {
        try text.map { text in
            guard let version = SemanticVersion(text) else {
                throw RepoError.usage("--edition 은 x.y.z 형식이어야 합니다: '\(text)'")
            }
            return version
        }
    }

    private func recordedEdition(_ entry: BrickLock.Entry, tenant: String) throws -> SemanticVersion {
        guard let version = SemanticVersion(entry.edition) else {
            throw RepoError.failure(
                "\(Tenants.lockFileName) 에 적힌 테넌트 \(tenant) 의 판 '\(entry.edition)' 이 x.y.z 형식이 아닙니다.")
        }
        return version
    }

    /// The requested edition, or the newest one. Without a request, an edition older than `current` is refused.
    private func chooseEdition(
        _ requested: SemanticVersion?,
        from versions: [SemanticVersion],
        tenant: String,
        current: SemanticVersion?
    ) throws -> SemanticVersion {
        if let requested {
            guard versions.contains(requested) else {
                let list = versions.isEmpty ? "(없음)" : versions.map(\.description).joined(separator: ", ")
                throw RepoError.failure("테넌트 \(tenant) 에 v\(requested) 태그가 없습니다. 있는 판: \(list)")
            }
            return requested
        }
        guard let latest = versions.last else {
            throw RepoError.failure("테넌트 \(tenant) 에 vX.Y.Z 형식의 태그가 없습니다.")
        }
        if let current, latest < current {
            throw RepoError.failure(
                "테넌트 \(tenant) 의 가장 새 판(\(latest))이 받은 판(\(current))보다 낮습니다. 그 판으로 되돌리려면 --edition \(latest) 를 주세요."
            )
        }
        return latest
    }

    private func requireSameCommit(_ entry: BrickLock.Entry, _ commit: String, tenant: String) throws {
        guard entry.commit == commit else {
            throw RepoError.failure(
                "테넌트 \(tenant) 의 판 \(entry.edition) 이 다른 커밋을 가리킵니다(기록 \(entry.commit), 지금 \(commit)). 테넌트가 태그를 옮겼습니다."
            )
        }
    }

    /// The paths a command replaces or deletes must have no uncommitted changes. `bricks.lock` is not among
    /// them: commands rewrite only their own tenant's entry and keep the rest as it is.
    private func requireCommitted(_ paths: [String]) throws {
        try Git.requireCommitted(paths, in: root, area: "블록")
    }

    private func requireWorkTree() throws {
        guard Git.isWorkTree(root) else {
            throw RepoError.failure("저장소 루트가 git 작업 트리가 아닙니다. 바뀌기 전과 후를 비교할 수 있도록 git 저장소에서 실행하세요.")
        }
    }

    private func changedPaths(_ tenant: String, alsoChecking extra: [String] = []) throws -> [String] {
        try Git.changedPaths([Tenants.path(tenant), Tenants.lockFileName] + extra, in: root)
    }

    // MARK: - Writing

    private func tenantDirectory(_ tenant: String) -> URL {
        root.appending(path: Tenants.path(tenant), directoryHint: .isDirectory)
    }

    /// Clones the tenant's edition into a temporary directory, checks that the tenant is a repository made
    /// from this template, and removes the clone afterwards.
    private func withCheckout<T>(
        of tenant: String,
        source: String,
        edition: SemanticVersion,
        _ body: (URL, String) throws -> T
    ) throws -> T {
        let checkout = FileManager.default.temporaryDirectory
            .appending(path: "repo-brick-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: checkout) }
        try TemplateSource.fetch(source, version: edition, into: checkout, workingDirectory: root)
        guard FileTree.itemExists(checkout.appending(path: TemplateManifest.fileName)) else {
            throw RepoError.failure("테넌트 \(tenant) 는 템플릿으로 만든 저장소가 아닙니다(\(TemplateManifest.fileName) 없음).")
        }
        return try body(checkout, try Git.headCommit(of: checkout))
    }

    /// Replaces `bricks/<tenant>/<unit>` with the tenant's `<unit>` from the checkout.
    private func install(_ unit: String, from checkout: URL, tenant: String) throws {
        let destination = tenantDirectory(tenant).appending(path: unit)
        let fileManager = FileManager.default
        if FileTree.itemExists(destination) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileTree.copy(checkout.appending(path: unit), to: destination, skip: Self.skipReceived)
    }

    /// Deletes everything in `bricks/<tenant>/` except the listed apps and packages.
    private func removeEntries(of tenant: String, keeping apps: [String], packages: [String]) throws {
        let fileManager = FileManager.default
        let directory = tenantDirectory(tenant)
        let keep = ["apps": Set(apps), "packages": Set(packages)]
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        where !FileTree.buildOutput.contains(name) {
            guard let kept = keep[name] else {
                try fileManager.removeItem(at: directory.appending(path: name))
                continue
            }
            let group = directory.appending(path: name)
            for child in try fileManager.contentsOfDirectory(atPath: group.path)
            where !kept.contains(child) && !FileTree.buildOutput.contains(child) {
                try fileManager.removeItem(at: group.appending(path: child))
            }
        }
    }

    /// Removes an app from the tenant's bricks, then the packages no remaining app needs. Without apps
    /// left, the tenant's directory and lock entry go too.
    private func detach(_ app: AppRef, entry: BrickLock.Entry, lock: inout BrickLock) throws {
        guard let tenant = app.tenant else {
            return
        }
        let remaining = entry.apps.filter { $0 != app.slug }
        let fileManager = FileManager.default
        if remaining.isEmpty {
            if FileTree.itemExists(tenantDirectory(tenant)) {
                try fileManager.removeItem(at: tenantDirectory(tenant))
            }
            lock.tenants[tenant] = nil
        } else {
            var packages = Set<String>()
            for other in remaining {
                packages.formUnion(
                    try PackageDependencies.closure(of: "apps/\(other)", in: tenantDirectory(tenant)).packages)
            }
            try removeEntries(of: tenant, keeping: remaining, packages: packages.sorted())
            lock.tenants[tenant]?.apps = remaining
            lock.tenants[tenant]?.packages = packages.sorted()
        }
        if FileTree.subdirectories(of: repository.bricksDirectory).isEmpty,
            let leftovers = try? fileManager.contentsOfDirectory(atPath: repository.bricksDirectory.path),
            leftovers.allSatisfy(FileTree.buildOutput.contains)
        {
            try fileManager.removeItem(at: repository.bricksDirectory)
        }
        try lock.write(to: root)
    }

    /// Paths of context files inside a unit of the checkout, as they would appear under `bricks/<tenant>/`.
    private func contextFiles(in checkout: URL, unit: String, tenant: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: checkout.appending(path: unit).path) else {
            return []
        }
        var found: [String] = []
        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if Self.skipInstalled(name) {
                enumerator.skipDescendants()
            } else if DocumentChecks.contextFileNames.contains(name.lowercased()) {
                found.append("\(Tenants.path(tenant))/\(unit)/\(path)")
            }
        }
        return found
    }

    /// Runs the writes. A failure part-way is reported with how to undo what was written.
    private func write(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as RepoError {
            throw error
        } catch {
            throw RepoError.failure(
                "블록을 쓰다 실패했습니다: \(error.localizedDescription)\n"
                    + "일부만 바뀌었을 수 있습니다. git status 로 확인하고 git restore 와 git clean 으로 되돌리세요."
            )
        }
    }
}
