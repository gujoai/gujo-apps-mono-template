import Foundation

/// The dependencies a `Package.swift` declares, read from its string literals, and the tenant packages
/// an app needs through them.
public enum PackageDependencies {
    public struct Declared: Equatable, Sendable {
        public var paths: [String] = []
        public var urls: [String] = []
    }

    /// `.package(path: "…")` and `.package(url: "…", …)` in a manifest. Line comments are ignored.
    public static func declared(in manifest: String) -> Declared {
        let code = withoutLineComments(manifest)
        var declared = Declared()
        var rest = code[...]
        while let start = rest.range(of: ".package(") {
            let call = argumentList(startingAt: start.upperBound, in: rest)
            if let path = stringArgument("path", in: call) {
                declared.paths.append(path)
            } else if let url = stringArgument("url", in: call) {
                declared.urls.append(url)
            }
            rest = rest[call.endIndex...]
        }
        return declared
    }

    /// Packages that the package at `start` (a directory relative to `root`) needs, directly or through
    /// other packages, as names under `packages/`. A path dependency that resolves anywhere else, such as
    /// outside the repository or to another app, makes the brick unpublishable and throws.
    public static func closure(of start: String, in root: URL) throws -> (packages: [String], urls: [String]) {
        var packages: [String] = []
        var urls: [String] = []
        var queue = [start]
        var visited = Set<String>()
        while let directory = queue.first {
            queue.removeFirst()
            guard visited.insert(directory).inserted else {
                continue
            }
            let manifestURL = root.appending(path: "\(directory)/Package.swift")
            guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
                throw RepoError.failure("\(directory)/Package.swift 가 없습니다.")
            }
            let declared = self.declared(in: manifest)
            urls += declared.urls
            for path in declared.paths {
                guard let name = packageName(resolving: path, from: directory) else {
                    throw RepoError.failure(
                        "\(directory)/Package.swift 의 path 의존 '\(path)' 가 packages/<이름> 을 가리키지 않습니다. 이 블록은 받을 수 없습니다."
                    )
                }
                if !packages.contains(name) {
                    packages.append(name)
                }
                queue.append("packages/\(name)")
            }
        }
        return (packages.sorted(), Array(Set(urls)).sorted())
    }

    /// The package name when `path`, relative to `directory`, resolves to `packages/<name>`.
    static func packageName(resolving path: String, from directory: String) -> String? {
        guard !path.hasPrefix("/") else {
            return nil
        }
        var components = directory.split(separator: "/").map(String.init)
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    return nil
                }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        guard components.count == 2, components[0] == "packages", !components[1].hasPrefix(".") else {
            return nil
        }
        return components[1]
    }

    /// The text between `.package(` and its closing parenthesis.
    private static func argumentList(startingAt start: Substring.Index, in text: Substring) -> Substring {
        var depth = 1
        var inString = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if character == "\\" {
                    index = text.index(after: index)
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return text[start..<index]
                }
            }
            if index < text.endIndex {
                index = text.index(after: index)
            }
        }
        return text[start..<text.endIndex]
    }

    /// The string literal after `label:` in an argument list.
    private static func stringArgument(_ label: String, in arguments: Substring) -> String? {
        var rest = arguments
        while let found = rest.range(of: "\(label):") {
            let before =
                found.lowerBound == arguments.startIndex ? nil : arguments[arguments.index(before: found.lowerBound)]
            rest = rest[found.upperBound...]
            if let before, before.isLetter || before.isNumber || before == "_" {
                continue
            }
            let value = rest.drop { $0.isWhitespace }
            guard value.first == "\"" else {
                continue
            }
            let literal = value.dropFirst().prefix { $0 != "\"" }
            return String(literal)
        }
        return nil
    }

    private static func withoutLineComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var inString = false
            var previous: Character?
            for index in line.indices {
                let character = line[index]
                if character == "\"" && previous != "\\" {
                    inString.toggle()
                } else if !inString && character == "/" && previous == "/" {
                    return line[..<line.index(before: index)]
                }
                previous = character
            }
            return line
        }
        .joined(separator: "\n")
    }
}
