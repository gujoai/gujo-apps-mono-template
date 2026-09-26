import Foundation

/// The git commands the template update needs. Output is captured; git never prompts for credentials.
enum Git {
    static func run(_ arguments: [String], in directory: URL) throws -> ProcessResult {
        try ProcessRunner.capture(["git"] + arguments, in: directory, environment: ["GIT_TERMINAL_PROMPT": "0"])
    }

    /// Runs git and returns its standard output, or throws with git's own message.
    static func output(_ arguments: [String], in directory: URL) throws -> String {
        let result = try run(arguments, in: directory)
        guard result.succeeded else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = arguments.first { !$0.hasPrefix("-") && !$0.contains("=") } ?? ""
            throw RepoError.failure("git \(command) 실패: \(message)")
        }
        return result.standardOutput
    }

    static func isWorkTree(_ directory: URL) -> Bool {
        let result = try? run(["rev-parse", "--is-inside-work-tree"], in: directory)
        return result?.succeeded == true
            && result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Paths with uncommitted changes (including untracked files) under the given paths.
    static func changedPaths(_ paths: [String], in directory: URL) throws -> [String] {
        let output = try output(
            ["--literal-pathspecs", "status", "--porcelain", "-z", "--untracked-files=all", "--"] + paths,
            in: directory
        )
        return parsePorcelain(output)
    }

    /// Paths from `git status --porcelain -z`: entries are `XY path`, and renames and copies
    /// carry their original path in the entry that follows.
    static func parsePorcelain(_ output: String) -> [String] {
        var paths: [String] = []
        var entries = output.split(separator: "\0", omittingEmptySubsequences: true)[...]
        while let entry = entries.popFirst() {
            guard entry.count > 3 else {
                continue
            }
            paths.append(String(entry.dropFirst(3)))
            if let status = entry.first, status == "R" || status == "C" {
                _ = entries.popFirst()
            }
        }
        return paths
    }
}
