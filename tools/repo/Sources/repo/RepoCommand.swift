import Foundation
import RepoCore

@main
enum RepoCommand {
    static let usage = """
        사용법: swift run repo <명령> [인자]

        명령:
          help [template|brick]                  이 도움말. 주제를 주면 템플릿 업데이트나 블록을 설명한다
          doctor [--json]                        환경, 저장소 구조, 문서, 블록을 점검한다. FAIL 이 있으면 exit 1
          new <slug> [--display-name "<이름>"]   templates/macos-app 을 apps/<slug> 로 복사하고 이름을 채운다
          list [--json]                          주인 앱과 블록 앱 목록 (slug, 표시 이름, VERSION, 출처)
          build [<앱>...]                        앱마다 swift build. 인자가 없으면 주인 앱과 블록 앱 모두. 첫 실패에서 멈춘다
          test [<앱>...]                         앱마다 swift test. 규칙은 build 와 같다
          lint [<앱>...]                         swift format lint --strict 와 앱 구조 점검. 주인 앱만 본다
                                                 인자가 없으면 모든 주인 앱과 tools
          check [<앱>...]                        lint, build, test 를 이 순서로 실행한다. 하나라도 실패하면 실패
          run <앱>                               GUI 를 실행한다. 창이 앞으로 오고, 창을 닫으면 앱이 끝난다
          bundle <앱> [--open]                   릴리스 빌드로 <앱 폴더>/.build/bundle/<표시 이름>.app 을 만든다
                                                 ad-hoc 서명이므로 이 Mac 에서 쓰는 용도다. --open 이면 바로 연다
          template status [--json] [--from <출처>]
                                                 현재 템플릿 판, 출처, 출처에서 받을 수 있는 가장 새 판
          template update [--to <x.y.z>] [--from <출처>] [--dry-run]
                                                 관리 영역을 그 판으로 교체한다. 자세한 설명은 help template
          template adopt <저장소 경로> [--bundle-prefix <값>] [--dry-run]
                                                 템플릿 checkout 에서 실행해, 템플릿으로 만들지 않은 저장소에 템플릿을 들인다
          brick list [--json]                    받은 블록의 테넌트, 판, 앱, 패키지
          brick available <테넌트> [--edition <x.y.z>] [--json]
                                                 그 테넌트 판의 앱 목록. 기본은 가장 새 판
          brick add <테넌트>/<앱> [--edition <x.y.z>]
                                                 앱과 그 앱이 쓰는 테넌트 패키지를 bricks/<테넌트>/ 로 받는다
          brick update <테넌트> [--edition <x.y.z>] [--dry-run]
                                                 그 테넌트에서 받은 앱 전부를 그 판으로 교체한다. 기본은 가장 새 판
          brick remove <테넌트>/<앱>             앱을 빼고, 더 이상 쓰이지 않는 패키지를 지운다
          brick eject <테넌트>/<앱>              앱과 패키지를 apps/, packages/ 로 옮겨 주인 앱으로 만든다
                                                 블록에 대한 자세한 설명은 help brick

        <앱> 은 주인 앱이면 <slug>, 블록 앱이면 <테넌트>/<slug> 다(예: notes, acme/notes).
        slug 는 소문자로 시작하고 소문자, 숫자, 하이픈만 쓴다(예: memo-board). <Name> 은 slug 의 PascalCase 다.
        앱의 CLI 명령은 swift run repo build <앱> 뒤에 <앱 폴더>/.build/debug/<slug> help 로 확인한다.
        lint 의 서식 오류는 swift format format --in-place --configuration .swift-format <파일> 로 고친다.
        종료 코드: 성공 0, 실패 1(하위 명령이 실패하면 그 코드), 사용법 오류 64
        """

    static let templateHelp = """
        템플릿 업데이트

        이 저장소의 일부는 템플릿이 관리한다.
          template.json 의 managedPaths    업데이트 때 통째로 교체되는 파일과 디렉터리
          template.json 의 managedBlocks   <!-- template:begin --> 과 <!-- template:end --> 사이만 교체되는 파일
        목록에 없는 파일과 표시 밖의 글은 저장소 주인의 것이며, 업데이트가 건드리지 않는다.

        판은 템플릿 저장소의 vX.Y.Z 태그다. 출처는 --from 이 없으면 repo.json 의 templateSource 다.
        출처에는 git 주소나 로컬 경로를 쓴다.

        순서:
          1. swift run repo template status             현재 판과 가장 새 판을 본다
          2. swift run repo template update --dry-run   추가, 수정, 삭제될 경로를 본다. 아무것도 쓰지 않는다
          3. swift run repo template update             관리 영역을 교체한다. 커밋은 하지 않는다
          4. swift run repo check                       통과하면 3 이 출력한 git add ... && git commit 으로 커밋한다

        --to <x.y.z> 가 없으면 가장 새 판을 받는다. 가장 새 판이 현재 판보다 낮으면 멈춘다.
        관리 영역에 커밋하지 않은 변경이 있으면 아무것도 쓰지 않고 exit 1 로 멈춘다.
        병합하지 않고 교체하므로, 관리 영역에 커밋해 둔 수정은 덮어써진다.
        관리 영역을 고친 곳은 현재 판을 그대로 주고 찾는다: swift run repo template update --to <현재 판> --dry-run
        받아 온 판의 template.json 버전이 태그와 다르면 그 판을 거부한다.

        템플릿 들이기 (template adopt)

        템플릿으로 만들지 않은, 이미 운영하던 저장소에 템플릿을 처음 들인다. 대상에는 아직 이 도구가 없으므로
        템플릿 checkout 에서 실행하고, 그 checkout 의 작업 트리를 그대로 들인다.
          swift run repo template adopt <저장소 경로> --dry-run   추가, 수정될 경로를 본다. 아무것도 쓰지 않는다
          swift run repo template adopt <저장소 경로> [--bundle-prefix <값>]

        다음 가운데 하나라도 걸리면 아무것도 쓰지 않고 exit 1 로 멈춘다.
          대상이 git 작업 트리가 아니다, 대상에 커밋하지 않은 변경이 있다, 대상에 이미 template.json 이 있다,
          관리 경로(managedPaths)가 대상에 이미 있는데 내용이 다르다(다른 경로를 모두 보여 준다)
        들이는 방법:
          managedPaths      없으면 복사한다. 이미 있고 내용이 같으면 넘어간다
          managedBlocks     없으면 템플릿 파일을 복사한다. 구역 표시가 없는 기존 파일은 템플릿 구역과 주인 절 제목 아래에
                            기존 내용을 그대로 옮긴다. 옮긴 내용은 저장소 주인이 정리한다. 구역 표시가 있으면 구역 안만 바꾼다
          repo.json         없으면 만든다(bundlePrefix 는 --bundle-prefix 나 com.example, templateSource 는 이 checkout 의 값)
          .gitignore        템플릿에만 있는 줄을 끝에 더한다
          README.md, LICENSE, apps/, packages/, bricks/ 는 건드리지 않는다
        커밋은 하지 않는다. 대상에서 swift run repo doctor 로 확인한 뒤, 출력된 git add ... && git commit 으로 커밋한다.
        """

    static func main() {
        do {
            try dispatch(Array(CommandLine.arguments.dropFirst()))
        } catch let error as RepoError {
            writeError(error.message)
            if error.exitCode == ExitCode.usage {
                writeError("\n" + usage)
            }
            exit(error.exitCode)
        } catch {
            writeError(error.localizedDescription)
            exit(ExitCode.failure)
        }
    }

    static func dispatch(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            throw RepoError.usage("명령이 없습니다.")
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "help", "-h", "--help":
            let topic = try ParsedArguments(rest, positionalCount: 0...1).positional.first
            switch topic {
            case nil:
                write(usage)
            case "template":
                write(templateHelp)
            case "brick":
                write(brickHelp)
            default:
                throw RepoError.usage("알 수 없는 도움말 주제: \(topic ?? "")")
            }
        case "doctor":
            let parsed = try ParsedArguments(rest, flags: ["--json"], positionalCount: 0...0)
            try doctor(json: parsed.flags.contains("--json"))
        case "new":
            let parsed = try ParsedArguments(rest, options: ["--display-name"], positionalCount: 1...1)
            try newApp(slug: parsed.positional[0], displayName: parsed.options["--display-name"])
        case "list":
            let parsed = try ParsedArguments(rest, flags: ["--json"], positionalCount: 0...0)
            try list(json: parsed.flags.contains("--json"))
        case "build":
            let slugs = try ParsedArguments(rest).positional
            try tasks().build(slugs)
        case "test":
            let slugs = try ParsedArguments(rest).positional
            try tasks().test(slugs)
        case "lint":
            let slugs = try ParsedArguments(rest).positional
            try tasks().lint(slugs)
            write("lint 통과")
        case "check":
            let slugs = try ParsedArguments(rest).positional
            try tasks().check(slugs)
            write("check 통과")
        case "run":
            let slug = try ParsedArguments(rest, positionalCount: 1...1).positional[0]
            try tasks().run(slug)
        case "bundle":
            let parsed = try ParsedArguments(rest, flags: ["--open"], positionalCount: 1...1)
            let tasks = try tasks()
            let app = try tasks.bundle(parsed.positional[0])
            write(app.path)
            if parsed.flags.contains("--open") {
                try tasks.open(app)
            }
        case "template":
            try template(rest)
        case "brick":
            try brick(rest)
        default:
            throw RepoError.usage("알 수 없는 명령: \(command)")
        }
    }

    static func template(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw RepoError.usage("template 뒤에 status, update, adopt 가운데 하나를 주세요.")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "status":
            let parsed = try ParsedArguments(rest, flags: ["--json"], options: ["--from"], positionalCount: 0...0)
            let status = try templateTasks().status(from: parsed.options["--from"])
            if parsed.flags.contains("--json") {
                write(try encodeJSON(status))
                return
            }
            write("현재 판: \(status.current)")
            write("출처: \(status.source)")
            write("출처의 판: \(status.versions.isEmpty ? "(없음)" : status.versions.joined(separator: ", "))")
            if let latest = status.latest, status.updateAvailable {
                write("가장 새 판: \(latest) (swift run repo template update 로 받을 수 있습니다)")
            } else {
                write("가장 새 판: \(status.latest ?? "(없음)") (업데이트할 판 없음)")
            }
        case "update":
            let parsed = try ParsedArguments(
                rest,
                flags: ["--dry-run"],
                options: ["--to", "--from"],
                positionalCount: 0...0
            )
            let outcome = try templateTasks().update(
                to: parsed.options["--to"],
                from: parsed.options["--from"],
                dryRun: parsed.flags.contains("--dry-run")
            )
            report(outcome)
        case "adopt":
            let parsed = try ParsedArguments(
                rest,
                flags: ["--dry-run"],
                options: ["--bundle-prefix"],
                positionalCount: 1...1
            )
            let outcome = try templateTasks().adopt(
                target: parsed.positional[0],
                bundlePrefix: parsed.options["--bundle-prefix"],
                dryRun: parsed.flags.contains("--dry-run")
            )
            report(outcome)
        default:
            throw RepoError.usage("알 수 없는 template 명령: \(subcommand)")
        }
    }

    static func report(_ outcome: TemplateAdoptOutcome) {
        switch outcome {
        case .planned(let plan):
            write("템플릿 판 \(plan.version) 을 들입니다 (--dry-run: 아무것도 쓰지 않았습니다)")
            for change in plan.changes {
                write("  \(label(change.kind))  \(change.path)")
            }
            for file in plan.movedOwnerContent {
                write("\(file): 기존 내용은 템플릿 구역과 주인 절 제목 아래로 옮겨집니다.")
            }
        case .applied(let plan, let target, let changedPaths):
            write("템플릿 판 \(plan.version) 을 들였습니다: \(target.path)")
            for file in plan.movedOwnerContent {
                write("\(file): 주인 절에 옮긴 기존 내용을 정리하세요. 템플릿 구역과 겹치는 규칙은 지웁니다.")
            }
            write("바뀐 경로(git status --porcelain):")
            for path in changedPaths {
                write("  \(path)")
            }
            let quoted = changedPaths.map(shellQuoted).joined(separator: " ")
            write(
                """

                다음 단계(대상 저장소에서):
                  swift run repo doctor
                  git add \(quoted) && git commit -m "Adopt template \(plan.version)"
                """
            )
        }
    }

    static func report(_ outcome: TemplateUpdateOutcome) {
        switch outcome {
        case .upToDate(let version):
            write("이미 최신입니다: 관리 영역이 판 \(version) 과 같습니다.")
        case .planned(let plan):
            write("\(plan.current.version) → \(plan.target.version) (--dry-run: 아무것도 쓰지 않았습니다)")
            for change in plan.changes {
                write("  \(label(change.kind))  \(change.path)")
            }
            write("추가 \(count(.added, in: plan)) · 수정 \(count(.modified, in: plan)) · 삭제 \(count(.deleted, in: plan))")
        case .applied(let plan, let changedPaths):
            write("\(plan.current.version) → \(plan.target.version)")
            write("바뀐 경로(git status --porcelain):")
            for path in changedPaths {
                write("  \(path)")
            }
            guard !changedPaths.isEmpty else {
                write("  (git 이 보는 변경 없음)")
                return
            }
            let quoted = changedPaths.map(shellQuoted).joined(separator: " ")
            write(
                """

                다음 단계:
                  swift run repo check
                  git add \(quoted) && git commit -m "Update template to \(plan.target.version)"
                """
            )
        }
    }

    static func label(_ kind: TemplateChange.Kind) -> String {
        switch kind {
        case .added: "추가"
        case .modified: "수정"
        case .deleted: "삭제"
        }
    }

    static func count(_ kind: TemplateChange.Kind, in plan: TemplatePlan) -> Int {
        plan.changes.filter { $0.kind == kind }.count
    }

    static func shellQuoted(_ path: String) -> String {
        let plain = path.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-/+".contains($0)) }
        return plain ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func templateTasks() throws -> TemplateTasks {
        let workingDirectory = currentDirectory()
        return TemplateTasks(
            repository: try Repository.locateOrThrow(from: workingDirectory),
            workingDirectory: workingDirectory
        )
    }

    static func doctor(json: Bool) throws {
        let workingDirectory = currentDirectory()
        let repository = Repository.locate(from: workingDirectory)
        let report = Doctor.run(repository: repository, workingDirectory: workingDirectory)
        if json {
            write(try encodeJSON(report))
        } else {
            let width = report.checks.map(\.name.count).max() ?? 0
            for check in report.checks {
                let status = check.status.rawValue.uppercased().padding(toLength: 4, withPad: " ", startingAt: 0)
                let name = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
                write("\(status)  \(name)  \(check.detail)")
            }
            let failures = report.checks.filter { $0.status == .fail }.count
            let warnings = report.checks.filter { $0.status == .warn }.count
            write("\nFAIL \(failures) · WARN \(warnings)")
        }
        if !report.ok {
            exit(ExitCode.failure)
        }
    }

    static func newApp(slug: String, displayName: String?) throws {
        let tasks = try tasks()
        let names = try tasks.newApp(slug: slug, displayName: displayName)
        let path = tasks.repository.appPath(slug)
        write(
            """
            만들었습니다: \(path) (\(names.displayName), \(names.bundleIdentifier))

            다음 단계:
              swift run repo check \(slug)
              swift run repo run \(slug)
              \(path)/README.md 에 앱 설명과 사용법을 채우세요.
            """
        )
    }

    static func list(json: Bool) throws {
        let repository = try Repository.locateOrThrow(from: currentDirectory())
        let refs = try repository.ownerApps() + repository.brickApps()
        let apps = refs.map { AppStructure.info($0, in: repository) }
        if json {
            write(try encodeJSON(apps))
            return
        }
        guard !apps.isEmpty else {
            write("앱이 없습니다. swift run repo new <slug> 로 만드세요.")
            return
        }
        let width = refs.map(\.description.count).max() ?? 0
        for (title, isBrick) in [("주인 앱", false), ("블록 앱", true)] {
            let rows = zip(refs, apps).filter { ($0.0.tenant != nil) == isBrick }
            guard !rows.isEmpty else {
                continue
            }
            write(title)
            for (ref, app) in rows {
                let name = ref.description.padding(toLength: width, withPad: " ", startingAt: 0)
                write("  \(name)  \(app.version ?? "-")  \(app.displayName ?? "-")")
            }
        }
    }

    static func tasks() throws -> RepoTasks {
        RepoTasks(repository: try Repository.locateOrThrow(from: currentDirectory()), log: write)
    }

    static func currentDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    static func encodeJSON(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // Unbuffered writes keep our lines in order with the output of child processes.
    static func write(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Positional arguments, boolean flags, and options that take a value.
struct ParsedArguments {
    var positional: [String] = []
    var flags: Set<String> = []
    var options: [String: String] = [:]

    init(
        _ arguments: [String],
        flags allowedFlags: Set<String> = [],
        options allowedOptions: Set<String> = [],
        positionalCount: ClosedRange<Int> = 0...Int.max
    ) throws {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if allowedFlags.contains(argument) {
                flags.insert(argument)
            } else if allowedOptions.contains(argument) {
                guard let value = remaining.popFirst() else {
                    throw RepoError.usage("\(argument) 에 값이 없습니다.")
                }
                options[argument] = value
            } else if argument.hasPrefix("-") {
                throw RepoError.usage("알 수 없는 옵션: \(argument)")
            } else {
                positional.append(argument)
            }
        }
        guard positionalCount.contains(positional.count) else {
            throw RepoError.usage("인자 개수가 맞지 않습니다(받은 인자 \(positional.count)개).")
        }
    }
}
