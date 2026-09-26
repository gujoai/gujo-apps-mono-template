import Foundation

/// The repo commands that run child processes. Child processes run in the repository root and
/// share this process's standard streams. Progress lines go through `log`; failures throw `RepoError`.
public struct RepoTasks {
    public let repository: Repository
    let log: (String) -> Void

    public init(repository: Repository, log: @escaping (String) -> Void) {
        self.repository = repository
        self.log = log
    }

    /// `names` are `<slug>` for the owner's apps and `<tenant>/<slug>` for bricks. None means every app.
    public func build(_ names: [String]) throws {
        try swiftForEachApp("build", names)
    }

    public func test(_ names: [String]) throws {
        try swiftForEachApp("test", names)
    }

    /// swift-format on the selected owner's apps (plus the repo tool when no name is given), then the
    /// structure check. Bricks are the tenant's code, so they are not linted.
    public func lint(_ names: [String]) throws {
        let selected = try repository.selectAppRefs(names)
        for brick in selected where brick.tenant != nil && !names.isEmpty {
            log("블록은 lint 하지 않습니다: \(brick)")
        }
        let slugs = names.isEmpty ? [] : selected.filter { $0.tenant == nil }.map(\.slug)
        if !names.isEmpty && slugs.isEmpty {
            return
        }
        let apps = try repository.selectApps(slugs)
        let files =
            (slugs.isEmpty ? SourceFiles.tools(in: repository) : [])
            + apps.flatMap { SourceFiles.app($0, in: repository) }
        let failures = apps.map { AppStructure.check(appDirectory: repository.appDirectory($0)) }
            .filter { $0.status == .fail }
        for failure in failures {
            log("구조 FAIL \(failure.name): \(failure.detail)")
        }
        if !files.isEmpty {
            try execute(
                ["swift", "format", "lint", "--strict", "--configuration", ".swift-format"] + files,
                display: "swift format lint --strict --configuration .swift-format (파일 \(files.count)개)"
            )
        }
        guard failures.isEmpty else {
            throw RepoError.failure("lint 실패: 앱 구조 점검에서 FAIL \(failures.count)건")
        }
    }

    public func check(_ names: [String]) throws {
        try lint(names)
        try build(names)
        try test(names)
    }

    public func run(_ name: String) throws {
        let app = try repository.selectAppRefs([name])[0]
        let product = AppStructure.executableProduct(appDirectory: repository.directory(of: app), slug: app.slug)
        try execute(["swift", "run", "--package-path", app.path, product])
    }

    /// Creates the app, then formats it so that import order and line breaks match the new names.
    public func newApp(slug: String, displayName: String?) throws -> AppNames {
        try AppNames.validateSlug(slug)
        let config = try repository.loadConfig()
        let names = try AppNames(slug: slug, displayName: displayName, bundlePrefix: config.bundlePrefix)
        try AppGenerator.generate(names, in: repository)
        do {
            try execute(
                ["swift", "format", "format", "--in-place", "--configuration", ".swift-format"]
                    + SourceFiles.app(slug, in: repository),
                display: "swift format format --in-place (\(repository.appPath(slug)))"
            )
        } catch let error as RepoError {
            log("경고: 새 앱의 서식을 맞추지 못했습니다. lint 가 실패할 수 있습니다. (\(error.message))")
        }
        return names
    }

    /// Builds the GUI in release mode and wraps it in an ad-hoc signed `.app`. Returns the `.app` URL.
    public func bundle(_ name: String) throws -> URL {
        let selected = try repository.selectAppRefs([name])[0]
        let appDirectory = repository.directory(of: selected)
        let path = selected.path
        let product = AppStructure.executableProduct(appDirectory: appDirectory, slug: selected.slug)
        guard let version = AppStructure.readVersion(appDirectory: appDirectory) else {
            throw RepoError.failure("\(path)/VERSION 이 없거나 x.y.z 형식이 아닙니다.")
        }
        var info = try AppStructure.readInfoPlist(appDirectory: appDirectory)

        try execute(["swift", "build", "-c", "release", "--package-path", path, "--product", product])
        let binPath = try ProcessRunner.capture(
            ["swift", "build", "-c", "release", "--package-path", path, "--show-bin-path"],
            in: repository.root
        )
        guard binPath.succeeded else {
            throw RepoError("실행 파일 위치를 얻지 못했습니다: \(binPath.standardError)", exitCode: binPath.status)
        }
        let binDirectory = binPath.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = URL(fileURLWithPath: binDirectory, isDirectory: true).appending(path: product)

        info["CFBundleShortVersionString"] = version
        info["CFBundleVersion"] = version
        let displayName = info["CFBundleDisplayName"] as? String ?? product
        let app = appDirectory.appending(path: ".build/bundle/\(displayName).app", directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: app.path) {
                try fileManager.removeItem(at: app)
            }
            try fileManager.createDirectory(
                at: contents.appending(path: "MacOS", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: executable, to: contents.appending(path: "MacOS/\(product)"))
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appending(path: "Info.plist"))
        } catch {
            throw RepoError.failure(".app 을 만들지 못했습니다: \(error.localizedDescription)")
        }
        try execute(["codesign", "--force", "--sign", "-", app.path])
        return app
    }

    public func open(_ url: URL) throws {
        try execute(["open", url.path])
    }

    private func swiftForEachApp(_ subcommand: String, _ names: [String]) throws {
        let apps = try repository.selectAppRefs(names)
        guard !apps.isEmpty else {
            log("앱이 없습니다. swift run repo new <slug> 로 만드세요.")
            return
        }
        for app in apps {
            try execute(["swift", subcommand, "--package-path", app.path])
        }
    }

    private func execute(_ arguments: [String], display: String? = nil) throws {
        let command = display ?? arguments.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
        log("==> \(command)")
        let status = try ProcessRunner.run(arguments, in: repository.root)
        guard status == ExitCode.success else {
            throw RepoError("실패(exit \(status)): \(command)", exitCode: status)
        }
    }
}
