import Foundation

/// Lists listening TCP ports and can terminate the owning processes.
struct PortService {
    let lsofPath: String?
    let killPath: String
    let psPath: String

    init() {
        lsofPath = ProcessRunner.firstExisting([
            "/usr/sbin/lsof",
            "/usr/bin/lsof",
            "/opt/homebrew/bin/lsof"
        ])
        killPath = ProcessRunner.firstExisting(["/bin/kill", "/usr/bin/kill"]) ?? "/bin/kill"
        psPath = ProcessRunner.firstExisting(["/bin/ps", "/usr/bin/ps"]) ?? "/bin/ps"
    }

    /// The full command line that launched a process, via `ps`. lsof only gives
    /// the (often truncated) executable name; this returns the argv string with
    /// arguments. Returns an empty string if the process is gone or ps fails.
    func commandLine(pid: Int) async -> String {
        let result = await ProcessRunner.run(psPath, ["-ww", "-o", "command=", "-p", String(pid)])
        guard result.ok else { return "" }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listListeningPorts() async -> [ListeningPort] {
        guard let lsofPath else { return [] }
        let result = await ProcessRunner.run(lsofPath, [
            "-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLtPn"
        ])
        // lsof exits non-zero when some handles are inaccessible; still parse stdout.
        return PortParser.parseLsof(result.stdout)
    }

    /// Sends a signal to a process. `force` uses SIGKILL, otherwise SIGTERM.
    func kill(pid: Int, force: Bool) async throws {
        let signal = force ? "-KILL" : "-TERM"
        let result = await ProcessRunner.run(killPath, [signal, String(pid)])
        guard result.ok else { throw PortError.kill(result.failureMessage) }
    }
}

enum PortError: LocalizedError {
    case kill(String)

    var errorDescription: String? {
        switch self {
        case .kill(let msg):
            if msg.contains("Operation not permitted") {
                return "Permission denied — this process is owned by another user or the system."
            }
            return msg
        }
    }
}
