import Foundation

/// Lean OKF: `okf:derived` blocks in the owner's app and package READMEs and in the root index.md hold text
/// generated from the code. `okf sync` rewrites them and `okf check` reports what sync would change, so both
/// run the same generators.
public enum OKF {
    /// What `okf sync` would write, by path relative to the root, and what stops it.
    public struct Plan: Sendable {
        public var writes: [String: String] = [:]
        public var problems: [String] = []
    }

    enum Kind {
        case app
        case package
        case index
    }

    static let generators: Set<String> = ["version", "deps", "used-by", "index"]
    static let indexFile = "index.md"

    /// `only` limits the documents, as `repo new` does for its new app and the index.
    public static func plan(root: URL, only: Set<String>? = nil) -> Plan {
        var plan = Plan()
        for (document, kind) in documents(in: root) where only?.contains(document) ?? true {
            let existing = try? String(contentsOf: root.appending(path: document), encoding: .utf8)
            let text = existing ?? "# 앱과 패키지 목록\n"
            let (updated, problems) = sync(text, document: document, kind: kind, root: root)
            plan.problems += problems.map { "\(document): \($0)" }
            if let updated, updated != existing {
                plan.writes[document] = updated
            }
        }
        return plan
    }

    public static func apply(_ plan: Plan, root: URL) throws {
        for (document, text) in plan.writes {
            try Data(text.utf8).write(to: root.appending(path: document), options: .atomic)
        }
    }

    /// Owner app and package READMEs that exist, and the root index.md, which sync creates when missing.
    static func documents(in root: URL) -> [(String, Kind)] {
        let readmes = [("apps", Kind.app), ("packages", Kind.package)].flatMap { group, kind in
            FileTree.subdirectories(of: root.appending(path: group)).map { ("\(group)/\($0)/README.md", kind) }
                .filter { FileTree.itemExists(root.appending(path: $0.0)) }
        }
        return readmes + [(indexFile, .index)]
    }

    /// The document with every derived block regenerated and missing standard blocks appended, or nil with
    /// the problems that stop it.
    static func sync(_ text: String, document: String, kind: Kind, root: URL) -> (String?, [String]) {
        var lines = text.components(separatedBy: "\n")
        let (blocks, errors) = scan(lines)
        var problems = errors
        let directory = document.split(separator: "/").dropLast().joined(separator: "/")
        var generated: [String: String] = [:]
        let standard: [String] =
            switch kind {
            case .app: ["version", "deps"]
            case .package: ["deps", "used-by"]
            case .index: ["index"]
            }
        for source in blocks.map(\.source) + standard where generated[source] == nil {
            guard generators.contains(source) else {
                problems.append("모르는 source '\(source)'")
                continue
            }
            do {
                generated[source] = try generate(source, directory: directory, root: root)
            } catch let error as RepoError {
                problems.append(error.message)
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        guard problems.isEmpty else {
            return (nil, problems)
        }
        for block in blocks.reversed() {
            let content = generated[block.source] ?? ""
            let current = lines[(block.open + 1)..<block.close].joined(separator: "\n")
            if canonical(current) != canonical(content) {
                lines.replaceSubrange((block.open + 1)..<block.close, with: contentLines(content))
            }
        }
        for id in standard where !blocks.contains(where: { $0.id == id }) {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            if !lines.isEmpty {
                lines.append("")
            }
            lines += ["<!-- okf:derived id=\(id) source=\(id) -->"] + contentLines(generated[id] ?? "")
            lines += ["<!-- /okf:derived -->", ""]
        }
        return (lines.joined(separator: "\n"), [])
    }

    struct Block {
        var id: String
        var source: String
        var open: Int
        var close: Int
    }

    /// Derived blocks and marker errors. Markers inside code fences are ignored, and `okf:block` markers are
    /// left as ordinary text.
    static func scan(_ lines: [String]) -> ([Block], [String]) {
        var blocks: [Block] = []
        var errors: [String] = []
        var open: Block?
        var inFence = false
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if open == nil, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence, trimmed.hasPrefix("<!--"), trimmed.hasSuffix("-->"), trimmed.count >= 7 else {
                continue
            }
            let tokens = trimmed.dropFirst(4).dropLast(3).split(whereSeparator: \.isWhitespace).map(String.init)
            let line = index + 1
            if tokens.first == "/okf:derived" {
                if let block = open {
                    blocks.append(Block(id: block.id, source: block.source, open: block.open, close: index))
                    open = nil
                } else {
                    errors.append("\(line)행: 짝 없는 닫는 표시")
                }
            } else if tokens.first == "okf:derived" {
                var attributes: [String: String] = [:]
                for token in tokens.dropFirst() {
                    let pair = token.split(separator: "=", maxSplits: 1).map(String.init)
                    if pair.count == 2 {
                        attributes[pair[0]] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
                if let block = open {
                    errors.append("\(line)행: 블록 \(block.id) 안에 다른 블록이 열림")
                } else if let id = attributes["id"], !id.isEmpty, let source = attributes["source"], !source.isEmpty {
                    if blocks.contains(where: { $0.id == id }) {
                        errors.append("\(line)행: 블록 id \(id) 가 겹침")
                    }
                    open = Block(id: id, source: source, open: index, close: index)
                } else {
                    errors.append("\(line)행: 블록에 id 나 source 가 없음")
                }
            }
        }
        if let block = open {
            errors.append("\(block.open + 1)행: 블록 \(block.id) 이 닫히지 않음")
        }
        return (blocks, errors)
    }

    static func generate(_ source: String, directory: String, root: URL) throws -> String {
        let from = directory.split(separator: "/").map(String.init)
        switch source {
        case "version":
            return "Version: "
                + (try read("\(directory)/VERSION", root: root)).trimmingCharacters(in: .whitespacesAndNewlines)
        case "deps":
            let declared = PackageDependencies.declared(in: try read("\(directory)/Package.swift", root: root))
            let entries = zip(declared.paths, declared.traits).map { path, traits in
                let target = PackageDependencies.resolve(path, from: directory)
                let name = target?.last ?? String(path.split(separator: "/").last ?? "")
                let link = target.map { relative(from: from, to: $0 + ["README.md"]) } ?? "\(path)/README.md"
                return (
                    name,
                    "* [\(name)](\(link))" + (traits.isEmpty ? "" : " (traits: \(traits.joined(separator: ", ")))")
                )
            }
            return section("Dependencies", entries.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.1))
        case "used-by":
            let items = FileTree.subdirectories(of: root.appending(path: "apps")).filter { app in
                let manifest = try? String(
                    contentsOf: root.appending(path: "apps/\(app)/Package.swift"), encoding: .utf8)
                return PackageDependencies.declared(in: manifest ?? "").paths.contains {
                    PackageDependencies.resolve($0, from: "apps/\(app)") == from
                }
            }
            .map { "* [\($0)](\(relative(from: from, to: ["apps", $0, "README.md"])))" }
            return section("Used by", items)
        default:
            let sections = [("Apps", "apps"), ("Packages", "packages")].map { title, group in
                let items = FileTree.subdirectories(of: root.appending(path: group)).compactMap { name -> String? in
                    let path = "\(group)/\(name)/README.md"
                    guard let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else {
                        return nil
                    }
                    let lines = text.components(separatedBy: "\n")
                    let body = lines.dropFirst(frontmatterEnd(lines).map { $0 + 1 } ?? 0)
                    let heading = body.first { $0.hasPrefix("# ") }.map {
                        $0.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    }
                    let title = frontmatter("title", in: lines) ?? heading ?? name
                    return "* [\(title)](\(path))" + (frontmatter("description", in: lines).map { " - \($0)" } ?? "")
                }
                return section(title, items)
            }
            return sections.joined(separator: "\n\n")
        }
    }

    static func section(_ title: String, _ items: [String]) -> String {
        "## \(title)\n\n" + (items.isEmpty ? "_none_" : items.joined(separator: "\n"))
    }

    static func relative(from directory: [String], to target: [String]) -> String {
        var common = 0
        while common < directory.count, common < target.count, directory[common] == target[common] {
            common += 1
        }
        return (Array(repeating: "..", count: directory.count - common) + target[common...]).joined(separator: "/")
    }

    /// A top-level `key: value` of the front matter between the first two `---` lines, unquoted.
    static func frontmatter(_ key: String, in lines: [String]) -> String? {
        guard let end = frontmatterEnd(lines) else {
            return nil
        }
        for line in lines[1..<end] where !line.hasPrefix(" ") && !line.hasPrefix("\t") {
            let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2, pair[0] == key else {
                continue
            }
            var value = pair[1]
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            } else if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// The index of the closing `---` when the document starts with front matter.
    static func frontmatterEnd(_ lines: [String]) -> Int? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        return lines.dropFirst().firstIndex { $0.trimmingCharacters(in: .whitespaces) == "---" }
    }

    /// Only trailing spaces on each line and blank lines around the block are ignored.
    static func canonical(_ content: String) -> String {
        content.components(separatedBy: "\n")
            .map { line in String(line.reversed().drop { $0.isWhitespace }.reversed()) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contentLines(_ content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? [] : trimmed.components(separatedBy: "\n")
    }

    static func read(_ path: String, root: URL) throws -> String {
        guard let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else {
            throw RepoError.failure("원천 \(path) 이 없습니다.")
        }
        return text
    }
}
