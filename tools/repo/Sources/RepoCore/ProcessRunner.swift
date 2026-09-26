import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String

    public var succeeded: Bool {
        status == 0
    }
}

/// Runs commands through `/usr/bin/env`, so they resolve through the caller's PATH.
public enum ProcessRunner {
    /// Runs a command with the parent's standard streams and returns its exit code.
    public static func run(_ arguments: [String], in directory: URL) throws -> Int32 {
        let process = makeProcess(arguments, in: directory)
        try launch(process, arguments)
        process.waitUntilExit()
        return exitCode(of: process)
    }

    /// Runs a short command and captures its output. Both pipes are read to the end before waiting,
    /// and stderr is drained on another thread so neither pipe can fill up and block the child.
    /// `environment` is added to this process's environment.
    public static func capture(
        _ arguments: [String],
        in directory: URL,
        environment: [String: String] = [:]
    ) throws -> ProcessResult {
        let process = makeProcess(arguments, in: directory)
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try launch(process, arguments)
        let errorReader = PipeReader(errorPipe.fileHandleForReading)
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorReader.wait()
        process.waitUntilExit()
        return ProcessResult(
            status: exitCode(of: process),
            standardOutput: String(decoding: output, as: UTF8.self),
            standardError: String(decoding: errorOutput, as: UTF8.self)
        )
    }

    private static func makeProcess(_ arguments: [String], in directory: URL) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        return process
    }

    private static func launch(_ process: Process, _ arguments: [String]) throws {
        do {
            try process.run()
        } catch {
            throw RepoError.failure("실행할 수 없습니다: \(arguments.joined(separator: " ")) (\(error.localizedDescription))")
        }
    }

    private static func exitCode(of process: Process) -> Int32 {
        process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }
}

/// Reads a pipe to the end on its own thread. A dedicated thread, not a dispatch queue, so the read can
/// start even when every pool thread is blocked in `wait()` (as when many tests capture output at once).
private final class PipeReader: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ handle: FileHandle) {
        let thread = Thread { [self] in
            data = handle.readDataToEndOfFile()
            done.signal()
        }
        thread.start()
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}
