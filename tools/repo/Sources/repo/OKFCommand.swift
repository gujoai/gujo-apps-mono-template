import Foundation
import RepoCore

extension RepoCommand {
    static let okfHelp = """
        생성 블록 (okf)

        주인 앱과 패키지의 README.md, 루트 index.md 에는 코드에서 만드는 블록이 있다.
          <!-- okf:derived id=<id> source=<생성기> -->
          ...
          <!-- /okf:derived -->
        생성기:
          version   앱 README     VERSION 값
          deps      앱, 패키지    Package.swift 의 .package(path:) 가 가리키는 README 목록
          used-by   패키지        이 패키지에 path 의존하는 앱 README 목록
          index     index.md      앱과 패키지 README 목록(머리말 title, description)
        블록 안은 손으로 고치지 않는다. 코드를 바꾼 뒤 swift run repo okf sync 로 갱신한다.
        sync 는 없는 표준 블록을 README 끝에 붙이고(앱: version, deps / 패키지: deps, used-by), index.md 가 없으면 만든다.
        okf check 와 doctor 의 okf-blocks 는 sync 가 바꿀 파일, 표시 오류, 원천 없음이 있으면 실패한다.
        bricks/, templates/ 는 보지 않는다.
        """

    static func okf(_ arguments: [String]) throws {
        let subcommand = arguments.first
        let parsed = try ParsedArguments(
            Array(arguments.dropFirst()),
            flags: subcommand == "sync" ? ["--dry-run"] : [],
            positionalCount: 0...0
        )
        guard subcommand == "sync" || subcommand == "check" else {
            throw RepoError.usage("okf 뒤에 sync 또는 check 를 주세요.")
        }
        let root = try Repository.locateOrThrow(from: currentDirectory()).root
        let plan = OKF.plan(root: root)
        for problem in plan.problems {
            writeError(problem)
        }
        guard plan.problems.isEmpty else {
            throw RepoError.failure("표시 오류나 원천 없음을 고친 뒤 다시 실행하세요.")
        }
        let paths = plan.writes.keys.sorted()
        if subcommand == "check" {
            guard paths.isEmpty else {
                throw RepoError.failure(
                    "생성 블록이 코드와 다릅니다: \(paths.joined(separator: ", ")). swift run repo okf sync 로 고치세요."
                )
            }
            write("okf check 통과")
            return
        }
        if !parsed.flags.contains("--dry-run") {
            try OKF.apply(plan, root: root)
        }
        write(paths.isEmpty ? "바꿀 파일이 없습니다." : paths.map { "  \($0)" }.joined(separator: "\n"))
    }
}
