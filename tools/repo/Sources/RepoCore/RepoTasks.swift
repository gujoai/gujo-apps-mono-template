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

    public func build(_ slugs: [String]) throws {
        try swiftForEachApp("build", slugs)
    }

    public func test(_ slugs: [String]) throws {
        try swiftForEachApp("test", slugs)
    }

    /// swift-format on the selected apps (plus the repo tool when no slug is given), then the structure check.
    public func lint(_ slugs: [String]) throws {
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

    public func check(_ slugs: [String]) throws {
        try lint(slugs)
        try build(slugs)
        try test(slugs)
    }

    public func run(_ slug: String) throws {
        _ = try repository.selectApps([slug])
        try execute(["swift", "run", "--package-path", repository.appPath(slug), "\(AppNames.pascalCase(slug))App"])
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
    public func bundle(_ slug: String) throws -> URL {
        _ = try repository.selectApps([slug])
        let appDirectory = repository.appDirectory(slug)
        let path = repository.appPath(slug)
        let product = "\(AppNames.pascalCase(slug))App"
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

    private func swiftForEachApp(_ subcommand: String, _ slugs: [String]) throws {
        let apps = try repository.selectApps(slugs)
        guard !apps.isEmpty else {
            log("앱이 없습니다. swift run repo new <slug> 로 만드세요.")
            return
        }
        for slug in apps {
            try execute(["swift", subcommand, "--package-path", repository.appPath(slug)])
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
