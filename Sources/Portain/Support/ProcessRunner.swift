import Foundation

/// Result of running a command-line process.
struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    var ok: Bool { exitCode == 0 }

    /// Best-effort human readable error message from a failed run.
    var failureMessage: String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        return "Command failed with exit code \(exitCode)."
    }
}

/// Runs external binaries off the main thread. GUI apps don't inherit the
/// login shell's PATH, so callers pass absolute executable paths.
enum ProcessRunner {
    static func run(_ path: String, _ args: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: CommandResult(
                        stdout: "",
                        stderr: error.localizedDescription,
                        exitCode: -1
                    ))
                    return
                }

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: CommandResult(
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self),
                    exitCode: process.terminationStatus
                ))
            }
        }
    }

    /// Returns the first existing path from a list of candidates.
    static func firstExisting(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
