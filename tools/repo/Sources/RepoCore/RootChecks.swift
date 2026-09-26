import Foundation

/// doctor checks for what sits at the root and how apps and packages are named.
public enum RootChecks {
    static let allowedEntries: Set<String> = [
        "README.md", "AGENTS.md", "CLAUDE.md", "ARCHITECTURE.md", "LICENSE", "index.md", "Package.swift",
        "Package.resolved", "repo.json", "template.json", "bricks.lock", ".gitignore", ".gitattributes",
        ".git-blame-ignore-revs", ".swift-format", ".editorconfig", ".gitlab-ci.yml",
        "apps", "packages", "bricks", "templates", "tools", "decisions", ".github",
    ]
    static let deicticWords: Set<String> = [
        "my", "mine", "temp", "tmp", "new", "old", "final", "latest", "current", "misc", "wip",
    ]

    static func checks(_ repository: Repository) -> [DoctorCheck] {
        let unexpected = unexpectedRootEntries(in: repository.root)
        let badNames = [("apps", "app"), ("packages", "package")].flatMap { group, kind in
            FileTree.subdirectories(of: repository.root.appending(path: group)).compactMap { name -> String? in
                let problems = itemNameProblems(name, kind: kind)
                return problems.isEmpty ? nil : "\(group)/\(name)(\(problems.joined(separator: ", ")))"
            }
        }
        return [
            unexpected.isEmpty
                ? DoctorCheck(name: "root-entries", status: .ok, detail: "루트 항목이 모두 허용 목록 안에 있음")
                : DoctorCheck(
                    name: "root-entries",
                    status: .fail,
                    detail: "허용 목록 밖의 루트 항목: \(unexpected.joined(separator: ", "))"
                ),
            badNames.isEmpty
                ? DoctorCheck(name: "item-names", status: .ok, detail: "apps/, packages/ 의 이름이 규칙에 맞음")
                : DoctorCheck(name: "item-names", status: .fail, detail: badNames.joined(separator: ", ")),
        ]
    }

    /// First path components git sees (tracked, or untracked and not ignored) that are not allowed at the root.
    /// Outside git the root itself is listed.
    static func unexpectedRootEntries(in root: URL) -> [String] {
        let names: [String]
        if Git.isWorkTree(root),
            let listed = try? Git.output(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: root)
        {
            names = listed.split(separator: "\0").compactMap { $0.split(separator: "/").first.map(String.init) }
        } else {
            let skipped: Set<String> = [".git", ".build", ".swiftpm", ".DS_Store"]
            names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter {
                !skipped.contains($0)
            }
        }
        return Set(names).subtracting(allowedEntries).sorted()
    }

    /// Why a folder name under `apps/` or `packages/` is not allowed. `kind` is `app` or `package`.
    public static func itemNameProblems(_ name: String, kind: String) -> [String] {
        guard AppNames.isValidSlug(name) else {
            return ["kebab-case slug 가 아님"]
        }
        let words = name.split(separator: "-").map(String.init)
        var problems = words.filter(deicticWords.contains).map { "사람과 시점에 따라 뜻이 바뀌는 단어 '\($0)'" }
        problems += words.filter { $0 == kind || $0 == kind + "s" }.map { "종류 단어 '\($0)'" }
        if name.range(of: #"\d{6,}"#, options: .regularExpression) != nil
            || words.contains(where: { $0.range(of: #"^(19|20)\d{2}$"#, options: .regularExpression) != nil })
        {
            problems.append("날짜 숫자")
        }
        return problems
    }
}
