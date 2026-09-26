import Foundation

/// Mechanical checks of the repository documents. What they cover, and what a person must check,
/// is in the check status section of ARCHITECTURE.md.
public enum DocumentChecks {
    static let contextFileNames: Set<String> = ["agents.md", "claude.md"]
    /// The app template may hold context files of its own; they are not rules for this repository.
    static let skippedRootDirectory = "templates"
    static let linkedDocuments = ["README.md", "ARCHITECTURE.md", "AGENTS.md"]
    static let architectureFile = "ARCHITECTURE.md"
    static let architectureHeadings = [
        "## 목적", "## 폴더 배치", "## 의존 방향", "## 주요 흐름", "## 경계", "## 변경 규칙", "### 독자", "### 다시 읽기",
        "### 점검 상태",
    ]

    public static func checks(_ repository: Repository) -> [DoctorCheck] {
        [
            contextFileCheck(repository),
            architectureCheck(repository),
            linkCheck(repository),
            templateBlockCheck(repository),
        ]
    }

    /// Rules live in one context file at the root, so a context file anywhere else is an error.
    static func contextFileCheck(_ repository: Repository) -> DoctorCheck {
        let misplaced = misplacedContextFiles(in: repository.root)
        guard misplaced.isEmpty else {
            return DoctorCheck(
                name: "context-files",
                status: .fail,
                detail: "컨텍스트 파일은 루트에만 둡니다. 규칙을 루트 AGENTS.md 로 옮기세요: \(misplaced.joined(separator: ", "))"
            )
        }
        return DoctorCheck(name: "context-files", status: .ok, detail: "AGENTS.md, CLAUDE.md 가 루트에만 있음")
    }

    static func architectureCheck(_ repository: Repository) -> DoctorCheck {
        guard let text = read(architectureFile, in: repository) else {
            return DoctorCheck(name: architectureFile, status: .fail, detail: "\(architectureFile) 이 없습니다.")
        }
        let missing = missingHeadings(in: text, required: architectureHeadings)
        guard missing.isEmpty else {
            return DoctorCheck(
                name: architectureFile,
                status: .fail,
                detail: "필수 제목이 없습니다: \(missing.joined(separator: ", "))"
            )
        }
        return DoctorCheck(name: architectureFile, status: .ok, detail: "필수 제목 \(architectureHeadings.count)개")
    }

    static func linkCheck(_ repository: Repository) -> DoctorCheck {
        var broken: [String] = []
        for document in linkedDocuments {
            guard let text = read(document, in: repository) else {
                broken.append("\(document) 없음")
                continue
            }
            broken += brokenLinks(in: text, relativeTo: repository.root).map { "\(document) → \($0)" }
        }
        guard broken.isEmpty else {
            return DoctorCheck(
                name: "doc-links",
                status: .fail,
                detail: "가리키는 파일이 없는 상대 링크: \(broken.joined(separator: ", "))"
            )
        }
        return DoctorCheck(
            name: "doc-links",
            status: .ok,
            detail: "\(linkedDocuments.joined(separator: ", ")) 의 상대 링크가 모두 있음"
        )
    }

    /// Reuses the marker check of `template update`, so a file that doctor accepts can also be updated.
    static func templateBlockCheck(_ repository: Repository) -> DoctorCheck {
        guard let manifest = try? TemplateManifest.load(from: repository.root) else {
            return DoctorCheck(name: "template-blocks", status: .fail, detail: "template.json 을 읽을 수 없어 확인하지 못했습니다.")
        }
        var problems: [String] = []
        for file in manifest.managedBlocks {
            guard let text = read(file, in: repository) else {
                problems.append("\(file) 없음")
                continue
            }
            do {
                _ = try ManagedBlock.innerRange(of: text, file: file)
            } catch let error as RepoError {
                problems.append(error.message)
            } catch {
                problems.append("\(file): \(error.localizedDescription)")
            }
        }
        guard problems.isEmpty else {
            return DoctorCheck(name: "template-blocks", status: .fail, detail: problems.joined(separator: " "))
        }
        return DoctorCheck(
            name: "template-blocks",
            status: .ok,
            detail: "\(manifest.managedBlocks.joined(separator: ", ")) 의 템플릿 구역 표시가 짝이 맞음"
        )
    }

    /// Paths, relative to `root`, of AGENTS.md and CLAUDE.md files below the root. In a git work tree the
    /// files git sees are checked (tracked, or untracked and not ignored), so ignored folders such as
    /// `.worktrees/` do not count. Elsewhere the folders are walked, skipping hidden ones.
    static func misplacedContextFiles(in root: URL) -> [String] {
        if Git.isWorkTree(root),
            let listed = try? Git.output(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: root)
        {
            return Array(Set(listed.split(separator: "\0").map(String.init).filter(isMisplacedContextFile))).sorted()
        }
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else {
            return []
        }
        var misplaced: [String] = []
        while let path = enumerator.nextObject() as? String {
            let components = path.split(separator: "/")
            if let name = components.last,
                name.hasPrefix(".")
                    || (components.count == 1 && name == skippedRootDirectory)
            {
                enumerator.skipDescendants()
            } else if isMisplacedContextFile(path) {
                misplaced.append(path)
            }
        }
        return misplaced.sorted()
    }

    static func isMisplacedContextFile(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard components.count > 1, let name = components.last, contextFileNames.contains(name.lowercased()) else {
            return false
        }
        return components.first != Substring(skippedRootDirectory)
    }

    static func missingHeadings(in text: String, required: [String]) -> [String] {
        let headings = Set(
            text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
        )
        return required.filter { !headings.contains($0) }
    }

    /// Targets of inline Markdown links (`[text](target)`) outside code, without web, mail, and in-page links.
    static func relativeLinks(in text: String) -> [String] {
        var links: [String] = []
        var inFence = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else {
                continue
            }
            let prose = line.split(separator: "`", omittingEmptySubsequences: false).enumerated()
                .filter { $0.offset.isMultiple(of: 2) }
                .map(\.element)
                .joined(separator: " ")
            var rest = prose[...]
            while let open = rest.range(of: "](") {
                let target = rest[open.upperBound...].prefix { $0 != ")" && !$0.isWhitespace }
                rest = rest[target.endIndex...]
                guard !target.isEmpty, rest.contains(")") else {
                    continue
                }
                if target.hasPrefix("#") || target.contains("://") || target.hasPrefix("mailto:") {
                    continue
                }
                links.append(String(target))
            }
        }
        return links
    }

    /// Relative link targets that do not exist, resolved against `directory`. Fragments and queries are ignored.
    static func brokenLinks(in text: String, relativeTo directory: URL) -> [String] {
        relativeLinks(in: text).filter { target in
            let path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
            let file = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
            let decoded = file.removingPercentEncoding ?? file
            return !FileManager.default.fileExists(atPath: directory.appending(path: decoded).path)
        }
    }

    private static func read(_ file: String, in repository: Repository) -> String? {
        try? String(contentsOf: repository.root.appending(path: file), encoding: .utf8)
    }
}
