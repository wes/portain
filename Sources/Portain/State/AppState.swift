import SwiftUI
import Combine

enum Tab: Hashable {
    case containers
    case ports
}

@MainActor
final class AppState: ObservableObject {
    // Navigation
    @Published var tab: Tab = .containers
    @Published var search: String = ""

    // Data
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var ports: [ListeningPort] = []

    // Status
    @Published private(set) var dockerInstalled = false
    @Published private(set) var dockerDaemonUp = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published var autoRefresh = true
    @Published private(set) var lastError: String?

    /// Container IDs that currently have an action in flight.
    @Published private(set) var busyContainers: Set<String> = []

    private let docker = DockerService()
    private let portService = PortService()
    private var timer: AnyCancellable?

    init() {
        dockerInstalled = docker.isInstalled
        startAutoRefresh()
    }

    // MARK: Filtering

    var filteredContainers: [DockerContainer] {
        let sorted = containers.sorted { a, b in
            if a.state.isActive != b.state.isActive { return a.state.isActive }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        guard !search.isEmpty else { return sorted }
        return sorted.filter { c in
            c.name.localizedCaseInsensitiveContains(search) ||
            (c.project?.localizedCaseInsensitiveContains(search) ?? false) ||
            c.displayImage.localizedCaseInsensitiveContains(search) ||
            c.shortID.localizedCaseInsensitiveContains(search) ||
            c.publishedPorts.contains { "\($0.hostPort ?? 0)".contains(search) }
        }
    }

    var filteredPorts: [ListeningPort] {
        guard !search.isEmpty else { return ports }
        return ports.filter { p in
            "\(p.port)".contains(search) ||
            p.command.localizedCaseInsensitiveContains(search) ||
            "\(p.pid)".contains(search) ||
            p.address.localizedCaseInsensitiveContains(search)
        }
    }

    var runningCount: Int { containers.filter { $0.state.isRunning }.count }

    /// Returns the container that publishes the given host port, if any.
    func container(forHostPort port: Int) -> DockerContainer? {
        containers.first { c in
            c.publishedPorts.contains { $0.hostPort == port }
        }
    }

    // MARK: Refresh

    func startAutoRefresh() {
        timer?.cancel()
        guard autoRefresh else { return }
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh(silent: true) }
            }
    }

    func toggleAutoRefresh() {
        autoRefresh.toggle()
        startAutoRefresh()
    }

    func refresh(silent: Bool = false) async {
        if !silent { isRefreshing = true }
        defer { isRefreshing = false }

        // Ports are always available.
        async let portList = portService.listListeningPorts()

        if docker.isInstalled {
            let daemon = await docker.daemonResponds()
            dockerDaemonUp = daemon
            if daemon {
                do {
                    var list = try await docker.listContainers()
                    let stats = await docker.liveStats()
                    for i in list.indices {
                        if let s = stats[list[i].id] {
                            list[i].cpuPerc = s.cpu
                            list[i].memUsage = s.mem
                            list[i].memPerc = s.memPerc
                        }
                    }
                    containers = list
                } catch {
                    if !silent { recordError(error) }
                }
            } else {
                containers = []
            }
        }

        ports = await portList
        lastRefresh = Date()
    }

    // MARK: Container actions

    func perform(_ action: ContainerAction, on container: DockerContainer) {
        guard !busyContainers.contains(container.id) else { return }
        busyContainers.insert(container.id)
        Task {
            defer { busyContainers.remove(container.id) }
            do {
                try await docker.perform(action, on: container.id)
                await refresh(silent: true)
            } catch {
                recordError(error)
            }
        }
    }

    /// Applies an action to every container in a group (e.g. all containers in
    /// a compose folder), skipping any already mid-action.
    func perform(_ action: ContainerAction, onAll containers: [DockerContainer]) {
        for container in containers {
            perform(action, on: container)
        }
    }

    func fetchLogs(for container: DockerContainer) async -> String {
        await docker.logs(for: container.id)
    }

    // MARK: Port actions

    /// Full command line (with arguments) for the process owning a port.
    func commandLine(for port: ListeningPort) async -> String {
        await portService.commandLine(pid: port.pid)
    }

    func killPort(_ port: ListeningPort, force: Bool) {
        Task {
            do {
                try await portService.kill(pid: port.pid, force: force)
                // Give the OS a beat to release the socket.
                try? await Task.sleep(nanoseconds: 350_000_000)
                await refresh(silent: true)
            } catch {
                recordError(error)
            }
        }
    }

    // MARK: Errors

    private func recordError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        print("Portain error: \(message)")
    }
}
