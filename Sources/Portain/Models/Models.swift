import SwiftUI

// MARK: - Containers

/// Lifecycle state of a Docker container.
enum ContainerState: String, Sendable {
    case running
    case paused
    case restarting
    case created
    case exited
    case dead
    case removing
    case unknown

    init(raw: String) {
        self = ContainerState(rawValue: raw.lowercased()) ?? .unknown
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .paused: return "Paused"
        case .restarting: return "Restarting"
        case .created: return "Created"
        case .exited: return "Stopped"
        case .dead: return "Dead"
        case .removing: return "Removing"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .running: return .green
        case .paused: return .orange
        case .restarting: return .yellow
        case .created: return .blue
        case .exited: return .secondary
        case .dead: return .red
        case .removing: return .pink
        case .unknown: return .gray
        }
    }

    var isRunning: Bool { self == .running }
    var isPaused: Bool { self == .paused }
    /// Whether the container is actively using resources (running or paused).
    var isActive: Bool { self == .running || self == .paused || self == .restarting }
}

/// A published port mapping for a container (host -> container).
struct PortMapping: Identifiable, Hashable, Sendable {
    let id = UUID()
    let hostIP: String?
    let hostPort: Int?
    let containerPort: Int
    let proto: String

    var display: String {
        if let hostPort {
            return "\(hostPort) → \(containerPort)/\(proto)"
        }
        return "\(containerPort)/\(proto)"
    }

    var isPublished: Bool { hostPort != nil }
}

/// A Docker container as visualized by Portain.
struct DockerContainer: Identifiable, Hashable, Sendable {
    let id: String          // full container ID
    let name: String
    let image: String
    let project: String?    // docker compose project (folder), if any
    let service: String?    // docker compose service name, if any
    let command: String
    let createdAt: String
    let runningFor: String
    let status: String      // human readable status string from docker
    let state: ContainerState
    let ports: [PortMapping]
    let size: String

    // Populated separately from `docker stats`.
    var cpuPerc: String?
    var memUsage: String?
    var memPerc: String?

    var shortID: String { String(id.prefix(12)) }

    /// Name to show inside a project folder — the compose service if known,
    /// otherwise the full container name with the project prefix trimmed.
    var folderDisplayName: String {
        if let service { return service }
        if let project, name.hasPrefix(project + "-") {
            return String(name.dropFirst(project.count + 1))
        }
        return name
    }

    var displayImage: String {
        if image.hasPrefix("sha256:") {
            return "image@" + String(image.dropFirst("sha256:".count).prefix(12))
        }
        return image
    }

    var publishedPorts: [PortMapping] {
        ports.filter { $0.isPublished }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DockerContainer, rhs: DockerContainer) -> Bool { lhs.id == rhs.id }

    /// Stand-in used briefly if a container is looked up by id while it's
    /// being removed from the list.
    static func placeholder(id: String) -> DockerContainer {
        DockerContainer(
            id: id, name: "—", image: "", project: nil, service: nil,
            command: "", createdAt: "", runningFor: "", status: "",
            state: .unknown, ports: [], size: ""
        )
    }
}

// MARK: - Ports

/// A process listening on a TCP port.
struct ListeningPort: Identifiable, Hashable, Sendable {
    let pid: Int
    let command: String
    let user: String
    let address: String
    let port: Int
    let proto: String
    var families: Set<String>   // IPv4 / IPv6

    var id: String { "\(pid)-\(port)-\(address)" }

    /// Heuristic: is this port owned by Docker's networking stack?
    var isDocker: Bool {
        let c = command.lowercased()
        return c.contains("docker") || c.contains("vpnkit") || c.contains("com.docker")
    }

    /// Compact protocol + IP-family label for the table's "Type" column,
    /// e.g. "TCP4", "TCP6", or "TCP46" for dual-stack.
    var typeLabel: String {
        let v4 = families.contains("IPv4")
        let v6 = families.contains("IPv6")
        let suffix = v4 && v6 ? "46" : (v6 ? "6" : "4")
        return proto + suffix
    }

    var scopeLabel: String {
        if address == "*" || address == "0.0.0.0" || address == "::" { return "All interfaces" }
        if address == "127.0.0.1" || address == "::1" { return "Localhost only" }
        return address
    }

    var isLocalOnly: Bool {
        address == "127.0.0.1" || address == "::1"
    }
}
