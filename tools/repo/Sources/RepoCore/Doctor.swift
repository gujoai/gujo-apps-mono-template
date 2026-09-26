import Foundation

public struct DoctorCheck: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok
        case warn
        case fail
    }

    public let name: String
    public let status: Status
    public let detail: String

    public init(name: String, status: Status, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public let ok: Bool
    public let checks: [DoctorCheck]

    public init(checks: [DoctorCheck]) {
        self.ok = !checks.contains { $0.status == .fail }
        self.checks = checks
    }
}

public enum Doctor {
    public static let minimumSwift = SemanticVersion(major: 6, minor: 1)
    public static let minimumMacOSMajor = 15
    static let installXcode =
        "Xcode 16.3 이상을 설치하세요. 이미 있다면 sudo xcode-select -s /Applications/Xcode.app 으로 선택하세요."

    /// Runs every check. `repository` is nil when no `repo.json` was found above `workingDirectory`.
    public static func run(repository: Repository?, workingDirectory: URL) -> DoctorReport {
        var checks = [
            swiftCheck(try? ProcessRunner.capture(["swift", "--version"], in: workingDirectory)),
            macOSCheck(ProcessInfo.processInfo.operatingSystemVersion),
            swiftFormatCheck(try? ProcessRunner.capture(["swift", "format", "--version"], in: workingDirectory)),
            gitCheck(
                try? ProcessRunner.capture(
                    ["git", "rev-parse", "--is-inside-work-tree"],
                    in: repository?.root ?? workingDirectory
                )
            ),
        ]
        guard let repository else {
            checks.append(
                DoctorCheck(
                    name: Repository.configFileName,
                    status: .fail,
                    detail: "현재 디렉터리와 그 위에서 \(Repository.configFileName) 을 찾지 못했습니다. 저장소 안에서 실행하세요."
                )
            )
            return DoctorReport(checks: checks)
        }
        checks.append(configCheck(repository))
        checks.append(templateCheck(repository))
        checks.append(contentsOf: DocumentChecks.checks(repository))
        checks.append(contentsOf: appChecks(repository))
        checks.append(DependencyChecks.check(repository))
        checks.append(contentsOf: BrickChecks.checks(repository))
        return DoctorReport(checks: checks)
    }

    static func swiftCheck(_ result: ProcessResult?) -> DoctorCheck {
        let name = "swift"
        guard let result, result.succeeded else {
            return DoctorCheck(name: name, status: .fail, detail: "swift 를 실행할 수 없습니다. \(installXcode)")
        }
        guard let version = SemanticVersion.parseSwiftVersion(result.standardOutput + result.standardError) else {
            return DoctorCheck(name: name, status: .fail, detail: "swift --version 출력을 해석할 수 없습니다. \(installXcode)")
        }
        guard version >= minimumSwift else {
            return DoctorCheck(
                name: name,
                status: .fail,
                detail: "Swift \(version) 입니다. \(minimumSwift) 이상이 필요합니다. \(installXcode)"
            )
        }
        return DoctorCheck(name: name, status: .ok, detail: "Swift \(version)")
    }

    static func macOSCheck(_ version: OperatingSystemVersion) -> DoctorCheck {
        let text = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        guard version.majorVersion >= minimumMacOSMajor else {
            return DoctorCheck(
                name: "macos",
                status: .fail,
                detail: "macOS \(text) 입니다. macOS \(minimumMacOSMajor) 이상이 필요합니다."
            )
        }
        return DoctorCheck(name: "macos", status: .ok, detail: "macOS \(text)")
    }

    static func swiftFormatCheck(_ result: ProcessResult?) -> DoctorCheck {
        guard let result, result.succeeded else {
            return DoctorCheck(
                name: "swift-format",
                status: .fail,
                detail: "swift format 을 실행할 수 없습니다(lint 에 필요). \(installXcode)"
            )
        }
        let version = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return DoctorCheck(name: "swift-format", status: .ok, detail: "swift format \(version)")
    }

    static func gitCheck(_ result: ProcessResult?) -> DoctorCheck {
        guard let result, result.succeeded,
            result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else {
            return DoctorCheck(
                name: "git",
                status: .warn,
                detail: "git 작업 트리가 아닙니다. 변경을 기록하려면 git clone 한 저장소에서 작업하세요."
            )
        }
        return DoctorCheck(name: "git", status: .ok, detail: "git 작업 트리")
    }

    public static func configCheck(_ repository: Repository) -> DoctorCheck {
        let name = Repository.configFileName
        let config: RepoConfig
        do {
            config = try repository.loadConfig()
        } catch let error as RepoError {
            return DoctorCheck(name: name, status: .fail, detail: error.message)
        } catch {
            return DoctorCheck(name: name, status: .fail, detail: error.localizedDescription)
        }
        guard config.hasValidBundlePrefix else {
            return DoctorCheck(
                name: name,
                status: .fail,
                detail: "bundlePrefix '\(config.bundlePrefix)' 가 도메인을 뒤집은 형식이 아닙니다. 예: com.mycompany"
            )
        }
        guard config.bundlePrefix != RepoConfig.placeholderPrefix else {
            return DoctorCheck(
                name: name,
                status: .warn,
                detail: "bundlePrefix 가 \(RepoConfig.placeholderPrefix) 입니다. 자기 도메인을 뒤집은 값으로 바꾸세요. 예: com.mycompany"
            )
        }
        return DoctorCheck(name: name, status: .ok, detail: "bundlePrefix \(config.bundlePrefix)")
    }

    /// template.json must be readable. An empty templateSource is normal before the template is published.
    public static func templateCheck(_ repository: Repository) -> DoctorCheck {
        let name = TemplateManifest.fileName
        let manifest: TemplateManifest
        do {
            manifest = try TemplateManifest.load(from: repository.root)
        } catch let error as RepoError {
            return DoctorCheck(name: name, status: .fail, detail: error.message)
        } catch {
            return DoctorCheck(name: name, status: .fail, detail: error.localizedDescription)
        }
        let source = (try? repository.loadConfig())?.templateSource ?? ""
        let sourceText = source.isEmpty ? "비어 있음(template 명령에는 --from 이 필요함)" : source
        return DoctorCheck(name: name, status: .ok, detail: "템플릿 판 \(manifest.version), 출처 \(sourceText)")
    }

    public static func appChecks(_ repository: Repository) -> [DoctorCheck] {
        let slugs: [String]
        do {
            slugs = try repository.appSlugs()
        } catch {
            return [
                DoctorCheck(name: "apps", status: .fail, detail: "apps/ 를 읽을 수 없습니다: \(error.localizedDescription)")
            ]
        }
        guard !slugs.isEmpty else {
            return [
                DoctorCheck(
                    name: "apps",
                    status: .ok,
                    detail: "앱이 아직 없습니다. swift run repo new <slug> 로 만드세요."
                )
            ]
        }
        return slugs.map { AppStructure.check(appDirectory: repository.appDirectory($0)) }
    }
}
