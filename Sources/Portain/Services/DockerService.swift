import Foundation

/// Actions Portain can perform on a container.
enum ContainerAction: String, Sendable {
    case start, stop, restart, pause, unpause, kill, remove

    var dockerArgs: [String] {
        switch self {
        case .start:   return ["start"]
        case .stop:    return ["stop"]
        case .restart: return ["restart"]
        case .pause:   return ["pause"]
        case .unpause: return ["unpause"]
        case .kill:    return ["kill"]
        case .remove:  return ["rm", "-f"]
        }
    }

    var verb: String {
        switch self {
        case .start: return "Starting"
        case .stop: return "Stopping"
        case .restart: return "Restarting"
        case .pause: return "Pausing"
        case .unpause: return "Resuming"
        case .kill: return "Killing"
        case .remove: return "Removing"
        }
    }
}

/// Talks to the `docker` CLI. We deliberately avoid orchestration — only
/// listing, inspecting, and simple lifecycle actions.
struct DockerService {
    /// Resolved docker binary path, or nil if Docker isn't installed.
    let binaryPath: String?

    init() {
        binaryPath = ProcessRunner.firstExisting([
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker"
        ])
    }

    var isInstalled: Bool { binaryPath != nil }

    // MARK: NDJSON decoding

    private struct PSLine: Decodable {
        let ID: String
        let Names: String
        let Image: String
        let Labels: String
        let Command: String
        let CreatedAt: String
        let RunningFor: String
        let Ports: String
        let State: String
        let Status: String
        let Size: String
    }

    private struct StatsLine: Decodable {
        let ID: String
        let CPUPerc: String
        let MemUsage: String
        let MemPerc: String
    }

    /// Parses docker's comma-separated "k=v,k=v" Labels string.
    private static func parseLabels(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[..<eq])
            let value = String(pair[pair.index(after: eq)...])
            result[key] = value
        }
        return result
    }

    // MARK: Queries

    /// Returns true if the docker daemon answers. Distinct from `isInstalled`.
    func daemonResponds() async -> Bool {
        guard let binaryPath else { return false }
        let result = await ProcessRunner.run(binaryPath, ["version", "--format", "{{.Server.Version}}"])
        return result.ok
    }

    func listContainers() async throws -> [DockerContainer] {
        guard let binaryPath else { throw DockerError.notInstalled }
        let result = await ProcessRunner.run(binaryPath, [
            "ps", "-a", "--no-trunc", "--format", "{{json .}}"
        ])
        guard result.ok else { throw DockerError.daemon(result.failureMessage) }

        let decoder = JSONDecoder()
        var containers: [DockerContainer] = []
        for line in result.stdout.split(separator: "\n") {
            let data = Data(line.utf8)
            guard let ps = try? decoder.decode(PSLine.self, from: data) else { continue }
            let labels = Self.parseLabels(ps.Labels)
            containers.append(DockerContainer(
                id: ps.ID,
                name: ps.Names,
                image: ps.Image,
                project: labels["com.docker.compose.project"],
                service: labels["com.docker.compose.service"],
                command: ps.Command.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                createdAt: ps.CreatedAt,
                runningFor: ps.RunningFor,
                status: ps.Status,
                state: ContainerState(raw: ps.State),
                ports: PortParser.parseDockerPorts(ps.Ports),
                size: ps.Size
            ))
        }
        return containers
    }

    /// Fetches CPU / memory stats for running containers (non-blocking snapshot).
    func liveStats() async -> [String: (cpu: String, mem: String, memPerc: String)] {
        guard let binaryPath else { return [:] }
        let result = await ProcessRunner.run(binaryPath, [
            "stats", "--no-stream", "--format", "{{json .}}"
        ])
        guard result.ok else { return [:] }
        let decoder = JSONDecoder()
        var map: [String: (String, String, String)] = [:]
        for line in result.stdout.split(separator: "\n") {
            guard let stat = try? decoder.decode(StatsLine.self, from: Data(line.utf8)) else { continue }
            map[stat.ID] = (stat.CPUPerc, stat.MemUsage, stat.MemPerc)
        }
        return map
    }

    func logs(for id: String, lines: Int = 200) async -> String {
        guard let binaryPath else { return "Docker not installed." }
        let result = await ProcessRunner.run(binaryPath, [
            "logs", "--tail", String(lines), id
        ])
        let combined = result.stdout + result.stderr
        return combined.isEmpty ? "No log output." : combined
    }

    // MARK: Actions

    @discardableResult
    func perform(_ action: ContainerAction, on id: String) async throws -> String {
        guard let binaryPath else { throw DockerError.notInstalled }
        let result = await ProcessRunner.run(binaryPath, action.dockerArgs + [id])
        guard result.ok else { throw DockerError.action(result.failureMessage) }
        return result.stdout
    }
}

enum DockerError: LocalizedError {
    case notInstalled
    case daemon(String)
    case action(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Docker isn't installed. Install Docker Desktop or OrbStack to manage containers."
        case .daemon(let msg):
            return "Couldn't reach the Docker daemon. \(msg)"
        case .action(let msg):
            return msg
        }
    }
}
