import Foundation

/// Creates `apps/<slug>` from `templates/macos-app`, replacing placeholders in file names and contents.
public enum AppGenerator {
    static let skippedNames: Set<String> = [".build", ".swiftpm", ".DS_Store"]

    @discardableResult
    public static func generate(_ names: AppNames, in repository: Repository) throws -> URL {
        let fileManager = FileManager.default
        let template = repository.templateDirectory
        guard fileManager.fileExists(atPath: template.path) else {
            throw RepoError.failure("템플릿이 없습니다: templates/macos-app")
        }
        let destination = repository.appDirectory(names.slug)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw RepoError.failure("이미 있습니다: \(repository.appPath(names.slug))")
        }
        do {
            try copy(template, to: destination, placeholders: names.placeholders)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return destination
    }

    static func replacePlaceholders(in text: String, _ placeholders: [(token: String, value: String)]) -> String {
        placeholders.reduce(text) { $0.replacingOccurrences(of: $1.token, with: $1.value) }
    }

    private static func copy(
        _ source: URL,
        to destination: URL,
        placeholders: [(token: String, value: String)]
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try fileManager.contentsOfDirectory(atPath: source.path).sorted()
        where !skippedNames.contains(name) {
            let item = source.appending(path: name)
            let target = destination.appending(path: replacePlaceholders(in: name, placeholders))
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                try copy(item, to: target, placeholders: placeholders)
                continue
            }
            let data = try Data(contentsOf: item)
            if let text = String(data: data, encoding: .utf8) {
                try Data(replacePlaceholders(in: text, placeholders).utf8).write(to: target)
            } else {
                try data.write(to: target)
            }
        }
    }
}
