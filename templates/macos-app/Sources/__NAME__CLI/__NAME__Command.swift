import Foundation
import __NAME__Core

@main
enum __NAME__Command {
    static let usage = """
        사용법: __name__ <명령>

        명령:
          list [--json]        항목 목록. --json 이면 JSON 배열
          add <제목>           항목 추가. 인자 여러 개는 공백으로 이어 제목 하나가 된다
          done <id 앞자리>     완료로 표시
          undo <id 앞자리>     완료 표시 해제
          remove <id 앞자리>   항목 삭제
          help                 이 도움말

        id 앞자리: list 가 보여 주는 8글자나 그보다 짧은 앞부분. 대소문자는 가리지 않고, 여러 항목과 맞으면 오류다.
        데이터: items.json 을 $__DATA_ENV__ 가 있으면 그 디렉터리에, 없으면 ~/Library/Application Support/__BUNDLE_ID__/ 에 둔다.
        종료 코드: 성공 0, 사용법 오류 64, 그 밖의 오류 1
        """

    static func main() {
        exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    static func run(_ arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            return usageError("명령이 없습니다.")
        }
        let rest = Array(arguments.dropFirst())
        do {
            switch command {
            case "help", "-h", "--help":
                print(usage)
            case "list":
                guard rest.isEmpty || rest == ["--json"] else {
                    return usageError("list 는 --json 만 받습니다.")
                }
                let items = try AppDataLocation.makeStore().list()
                if rest.isEmpty {
                    for item in items {
                        print(line(for: item))
                    }
                } else {
                    print(String(decoding: try ItemStore.encode(items), as: UTF8.self))
                }
            case "add":
                guard !rest.isEmpty else {
                    return usageError("제목이 없습니다.")
                }
                print(line(for: try AppDataLocation.makeStore().add(title: rest.joined(separator: " "))))
            case "done", "undo":
                guard rest.count == 1 else {
                    return usageError("\(command) 는 id 앞자리 하나를 받습니다.")
                }
                let store = try AppDataLocation.makeStore()
                var item = try store.item(matchingIDPrefix: rest[0])
                item.isDone = command == "done"
                try store.setDone(id: item.id, item.isDone)
                print(line(for: item))
            case "remove":
                guard rest.count == 1 else {
                    return usageError("remove 는 id 앞자리 하나를 받습니다.")
                }
                let store = try AppDataLocation.makeStore()
                let item = try store.item(matchingIDPrefix: rest[0])
                try store.remove(id: item.id)
                print("삭제했습니다: \(line(for: item))")
            default:
                return usageError("알 수 없는 명령: \(command)")
            }
            return 0
        } catch {
            printError(error.localizedDescription)
            return 1
        }
    }

    static func line(for item: Item) -> String {
        "\(item.shortID)  [\(item.isDone ? "x" : " ")] \(item.title)"
    }

    static func usageError(_ message: String) -> Int32 {
        printError(message + "\n\n" + usage)
        return 64
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
