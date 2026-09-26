public enum ExitCode {
    public static let success: Int32 = 0
    public static let failure: Int32 = 1
    public static let usage: Int32 = 64
}

/// A failure with a message for the user and the exit code the command ends with.
public struct RepoError: Error, Equatable, Sendable {
    public let message: String
    public let exitCode: Int32

    public init(_ message: String, exitCode: Int32) {
        self.message = message
        self.exitCode = exitCode
    }

    public static func usage(_ message: String) -> RepoError {
        RepoError(message, exitCode: ExitCode.usage)
    }

    public static func failure(_ message: String) -> RepoError {
        RepoError(message, exitCode: ExitCode.failure)
    }
}
