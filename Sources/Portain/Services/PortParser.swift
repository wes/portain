import Foundation

/// Parsing helpers for docker port strings and lsof output.
enum PortParser {

    /// Parses docker's "Ports" column, e.g.
    /// "0.0.0.0:8080->8080/tcp, :::8080->8080/tcp, 9229/tcp"
    static func parseDockerPorts(_ raw: String) -> [PortMapping] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var mappings: [PortMapping] = []
        for segment in trimmed.split(separator: ",") {
            let token = segment.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            // Split "host->container/proto" or "container/proto".
            let arrowParts = token.components(separatedBy: "->")
            let containerPart = arrowParts.last ?? token

            // containerPart looks like "8080/tcp"
            let slash = containerPart.components(separatedBy: "/")
            guard let containerPort = Int(slash.first ?? "") else { continue }
            let proto = slash.count > 1 ? slash[1] : "tcp"

            var hostIP: String?
            var hostPort: Int?
            if arrowParts.count > 1 {
                let hostPart = arrowParts[0]
                // hostPart like "0.0.0.0:8080" or ":::8080" (IPv6 wildcard)
                if let lastColon = hostPart.range(of: ":", options: .backwards) {
                    hostIP = String(hostPart[..<lastColon.lowerBound])
                    hostPort = Int(hostPart[lastColon.upperBound...])
                } else {
                    hostPort = Int(hostPart)
                }
            }

            mappings.append(PortMapping(
                hostIP: hostIP,
                hostPort: hostPort,
                containerPort: containerPort,
                proto: proto
            ))
        }
        // De-duplicate identical published mappings (IPv4 + IPv6 pairs).
        var seen = Set<String>()
        return mappings.filter { m in
            let key = "\(m.hostPort ?? -1)-\(m.containerPort)-\(m.proto)"
            return seen.insert(key).inserted
        }
    }

    /// Parses `lsof -nP -iTCP -sTCP:LISTEN -FpcLtPn` machine output.
    static func parseLsof(_ output: String) -> [ListeningPort] {
        var results: [Int: [Int: ListeningPort]] = [:]   // pid -> port -> entry

        var pid = 0
        var command = ""
        var user = ""

        // Per-file accumulators.
        var fileType = ""      // IPv4 / IPv6
        var fileProto = ""     // TCP / UDP
        var haveFile = false

        func flushFile() {
            guard haveFile else { return }
            haveFile = false
            // name was applied directly when seen; nothing to do here.
        }

        func record(name: String) {
            // name like "*:55483", "127.0.0.1:17600", "[::1]:123"
            guard let lastColon = name.range(of: ":", options: .backwards),
                  let port = Int(name[lastColon.upperBound...]) else { return }
            var address = String(name[..<lastColon.lowerBound])
            address = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if address.isEmpty { address = "*" }

            let family = fileType.contains("6") ? "IPv6" : "IPv4"
            let proto = fileProto.isEmpty ? "TCP" : fileProto

            if var existing = results[pid]?[port] {
                existing.families.insert(family)
                results[pid, default: [:]][port] = existing
            } else {
                let entry = ListeningPort(
                    pid: pid,
                    command: command,
                    user: user,
                    address: address,
                    port: port,
                    proto: proto,
                    families: [family]
                )
                results[pid, default: [:]][port] = entry
            }
        }

        for rawLine in output.split(separator: "\n") {
            guard let tag = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch tag {
            case "p":
                flushFile()
                pid = Int(value) ?? 0
            case "c":
                command = value
            case "L":
                user = value
            case "f":            // new file record
                flushFile()
                fileType = ""
                fileProto = ""
            case "t":
                fileType = value
            case "P":
                fileProto = value
            case "n":
                record(name: value)
            default:
                break
            }
        }
        flushFile()

        return results.values.flatMap { $0.values }.sorted { $0.port < $1.port }
    }
}
