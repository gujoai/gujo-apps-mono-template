import Foundation
import RepoCore

extension RepoCommand {
    static let brickHelp = """
        블록

        블록은 이 템플릿으로 만든 다른 저장소(테넌트)의 앱 하나다. 받은 블록은 테넌트 저장소와 같은 모양으로
        bricks/<테넌트>/apps/<앱> 에 들어가고, 그 앱이 쓰는 테넌트 패키지는 bricks/<테넌트>/packages/<이름> 에 함께 들어간다.
        어느 판의 어느 커밋에서 받았는지는 bricks.lock 에 기록된다.

        책임: 이 템플릿은 틀만 제공하고 블록의 내용을 보증하지 않는다. 블록의 내용은 그 테넌트가, 무엇을 받아 쓸지는
        저장소 주인이 책임진다. 주인이 그 책임을 질 수 있도록 받기 전에 다음 세 가지를 거친다.
          테넌트 등록   repo.json 의 "tenants": {"<테넌트>": "<git 주소 또는 경로>"} 에 적힌 테넌트에서만 받는다
          커밋 고정     판의 태그가 가리킨 커밋을 bricks.lock 에 적고, 같은 판의 태그가 다른 커밋으로 옮겨지면 거부한다
          미리 보기     update --dry-run 으로 바뀔 경로를 먼저 본다. 어떤 brick 명령도 커밋하지 않는다

        판은 테넌트 저장소의 vX.Y.Z 태그다. 한 테넌트의 블록은 한 판에서만 받는다. 판을 바꾸려면 update --edition 으로 모두 바꾼다.
        앱이 .package(path: "../../packages/<이름>") 로 쓰는 테넌트 패키지는 함께 받고, .package(url:) 의존은 알리기만 한다.
        테넌트 코드의 AGENTS.md, CLAUDE.md 는 받지 않는다. 에이전트 규칙은 이 저장소 루트의 AGENTS.md 에만 둔다.

        순서:
          1. repo.json 의 tenants 에 테넌트를 적고 커밋한다
          2. swift run repo brick available <테넌트>      받을 수 있는 앱을 본다
          3. swift run repo brick add <테넌트>/<앱>       받는다
          4. swift run repo check                         통과하면 3 이 출력한 git add ... && git commit 으로 커밋한다

        bricks/<테넌트>/ 나 bricks.lock 에 커밋하지 않은 변경이 있으면 아무것도 쓰지 않고 exit 1 로 멈춘다.
        블록을 고쳐 쓰려면 brick eject 로 주인 앱으로 옮긴다. 같은 이름의 apps/<앱> 이나 packages/<이름> 이 있으면 거부한다.
        블록을 고친 곳은 현재 판을 그대로 주고 찾는다: swift run repo brick update <테넌트> --edition <현재 판> --dry-run
        lint 는 블록을 보지 않는다. build, test, check, run, bundle 은 <테넌트>/<앱> 도 받는다.
        """

    static let brickNotice =
        "이 템플릿은 블록의 내용을 보증하지 않습니다. 받은 코드는 저장소 주인이 검토하고 씁니다."

    static func brick(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw RepoError.usage("brick 뒤에 list, available, add, update, remove, eject 가운데 하나를 주세요.")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "list":
            let parsed = try ParsedArguments(rest, flags: ["--json"], positionalCount: 0...0)
            try brickList(json: parsed.flags.contains("--json"))
        case "available":
            let parsed = try ParsedArguments(rest, flags: ["--json"], options: ["--edition"], positionalCount: 1...1)
            let availability = try brickTasks().available(parsed.positional[0], edition: parsed.options["--edition"])
            if parsed.flags.contains("--json") {
                write(try encodeJSON(availability))
                return
            }
            write("테넌트 \(availability.tenant) 판 \(availability.edition) (커밋 \(availability.commit))")
            write("테넌트의 판: \(availability.editions.joined(separator: ", "))")
            write(availability.apps.isEmpty ? "앱: (없음)" : "앱:")
            let width = availability.apps.map(\.slug.count).max() ?? 0
            for app in availability.apps {
                let slug = app.slug.padding(toLength: width, withPad: " ", startingAt: 0)
                write("  \(slug)  \(app.version ?? "-")  \(app.displayName ?? "-")")
            }
        case "add":
            let parsed = try ParsedArguments(rest, options: ["--edition"], positionalCount: 1...1)
            let app = try AppRef.parse(parsed.positional[0])
            let result = try brickTasks().add(app, edition: parsed.options["--edition"])
            report(
                result,
                headline: "\(app) 를 테넌트 \(result.tenant) 의 판 \(result.edition ?? "-") 에서 받았습니다.",
                commitMessage: "Add brick \(app) \(result.edition ?? "")",
                notice: true
            )
        case "update":
            let parsed = try ParsedArguments(
                rest,
                flags: ["--dry-run"],
                options: ["--edition"],
                positionalCount: 1...1
            )
            let outcome = try brickTasks().update(
                parsed.positional[0],
                edition: parsed.options["--edition"],
                dryRun: parsed.flags.contains("--dry-run")
            )
            report(outcome)
        case "remove":
            let app = try AppRef.parse(try ParsedArguments(rest, positionalCount: 1...1).positional[0])
            let result = try brickTasks().remove(app)
            report(result, headline: "\(app) 를 뺐습니다.", commitMessage: "Remove brick \(app)", notice: false)
        case "eject":
            let app = try AppRef.parse(try ParsedArguments(rest, positionalCount: 1...1).positional[0])
            let result = try brickTasks().eject(app)
            report(
                result,
                headline: "\(app) 를 apps/\(app.slug) 로 옮겼습니다. 이제 주인 앱이며, 번들 ID 는 테넌트의 값 그대로입니다.",
                commitMessage: "Eject brick \(app)",
                notice: false,
                checkTarget: app.slug
            )
        default:
            throw RepoError.usage("알 수 없는 brick 명령: \(subcommand)")
        }
    }

    static func brickList(json: Bool) throws {
        let lock = try brickTasks().list()
        if json {
            write(try encodeJSON(lock))
            return
        }
        guard !lock.tenants.isEmpty else {
            write("받은 블록이 없습니다. 받는 방법은 swift run repo help brick 에 있습니다.")
            return
        }
        for (tenant, entry) in lock.tenants.sorted(by: { $0.key < $1.key }) {
            write("\(tenant)  판 \(entry.edition)  커밋 \(entry.commit.prefix(12))  출처 \(entry.source)")
            write("  앱: \(entry.apps.joined(separator: ", "))")
            write("  패키지: \(entry.packages.isEmpty ? "(없음)" : entry.packages.joined(separator: ", "))")
        }
    }

    static func report(_ outcome: BrickUpdateOutcome) {
        switch outcome {
        case .upToDate(let tenant, let edition):
            write("이미 최신입니다: 테넌트 \(tenant) 의 블록이 판 \(edition) 과 같습니다.")
        case .planned(let tenant, let from, let to, let changes):
            write("테넌트 \(tenant): \(from) → \(to) (--dry-run: 아무것도 쓰지 않았습니다)")
            for change in changes {
                write("  \(label(change.kind))  \(change.path)")
            }
            let counts = [TemplateChange.Kind.added, .modified, .deleted].map { kind in
                "\(label(kind)) \(changes.filter { $0.kind == kind }.count)"
            }
            write(counts.joined(separator: " · "))
        case .applied(let result):
            report(
                result,
                headline: "테넌트 \(result.tenant) 의 블록: \(result.previousEdition ?? "-") → \(result.edition ?? "-")",
                commitMessage: "Update brick \(result.tenant) to \(result.edition ?? "")",
                notice: true
            )
        }
    }

    static func report(
        _ result: BrickResult,
        headline: String,
        commitMessage: String,
        notice: Bool,
        checkTarget: String? = nil
    ) {
        write(headline)
        for url in result.externalPackages {
            write("외부 패키지: \(url)")
        }
        for path in result.skippedContextFiles {
            write("받지 않은 컨텍스트 파일: \(path)")
        }
        write("바뀐 경로(git status --porcelain):")
        for path in result.changedPaths {
            write("  \(path)")
        }
        if result.changedPaths.isEmpty {
            write("  (git 이 보는 변경 없음)")
        }
        if notice {
            write("\n블록은 테넌트 \(result.tenant) 가 제공합니다. \(brickNotice)")
        }
        guard !result.changedPaths.isEmpty else {
            return
        }
        let quoted = result.changedPaths.map(shellQuoted).joined(separator: " ")
        let check = checkTarget.map { "swift run repo check \($0)" } ?? "swift run repo check"
        write(
            """

            다음 단계:
              \(check)
              git add \(quoted) && git commit -m "\(commitMessage)"
            """
        )
    }

    static func brickTasks() throws -> BrickTasks {
        BrickTasks(repository: try Repository.locateOrThrow(from: currentDirectory()))
    }
}
