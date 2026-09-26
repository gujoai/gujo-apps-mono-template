import Foundation

public enum AppDataLocation {
    public static let environmentKey = "__DATA_ENV__"
    public static let bundleIdentifier = "__BUNDLE_ID__"

    /// `$__DATA_ENV__` when it is set, otherwise `~/Library/Application Support/__BUNDLE_ID__/`.
    /// The directory is created if it does not exist.
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let directory: URL
        if let path = environment[environmentKey], !path.isEmpty {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = URL.applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func makeStore(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ItemStore {
        ItemStore(directory: try directory(environment: environment))
    }
}
