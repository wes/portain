import SwiftUI

// MARK: - List

@MainActor
struct ContainersList: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: DockerContainer.ID?
    /// Explicit per-folder expand state set by the user, keyed "section/project".
    /// Absent keys fall back to the section default (Running expanded, Stopped collapsed).
    @State private var folderOverrides: [String: Bool] = [:]

    var body: some View {
        Group {
            if !state.dockerInstalled {
                EmptyState(
                    systemImage: "shippingbox",
                    title: "Docker not found",
                    message: "Install Docker Desktop or OrbStack, then refresh. Portain only reads — it never installs anything."
                )
            } else if !state.dockerDaemonUp {
                EmptyState(
                    systemImage: "bolt.horizontal.circle",
                    title: "Docker daemon is offline",
                    message: "Start Docker Desktop or OrbStack, then refresh."
                )
            } else if state.filteredContainers.isEmpty {
                EmptyState(
                    systemImage: "shippingbox",
                    title: state.search.isEmpty ? "No containers" : "No matches",
                    message: state.search.isEmpty
                        ? "Nothing here yet. Containers you create will appear automatically."
                        : "No containers match “\(state.search)”."
                )
            } else {
                List(selection: $selection) {
                    let running = state.filteredContainers.filter { $0.state.isActive }
                    let stopped = state.filteredContainers.filter { !$0.state.isActive }

                    if !running.isEmpty {
                        Section {
                            buckets(for: running, section: "running")
                        } header: {
                            GroupHeader(title: "Running", count: running.count, tint: .green)
                        }
                    }
                    if !stopped.isEmpty {
                        Section {
                            buckets(for: stopped, section: "stopped")
                        } header: {
                            GroupHeader(title: "Stopped", count: stopped.count, tint: .secondary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Containers")
    }

    /// Renders the project folders (collapsible) and standalone containers.
    @ViewBuilder
    private func buckets(for containers: [DockerContainer], section: String) -> some View {
        ForEach(projectBuckets(containers)) { bucket in
            if let project = bucket.project {
                DisclosureGroup(isExpanded: expansion(section, project)) {
                    ForEach(bucket.containers) { container in
                        ContainerRow(container: container, inProject: true)
                            .tag(container.id)
                    }
                } label: {
                    FolderLabel(name: project, containers: bucket.containers)
                        .selectionDisabled()
                }
            } else {
                ForEach(bucket.containers) { container in
                    ContainerRow(container: container, inProject: false)
                        .tag(container.id)
                }
            }
        }
    }

    /// Two-way binding for a folder's expanded state. Running folders default
    /// expanded, Stopped folders default collapsed, until the user toggles.
    private func expansion(_ section: String, _ project: String) -> Binding<Bool> {
        let key = section + "/" + project
        let defaultExpanded = (section == "running")
        return Binding(
            get: { folderOverrides[key] ?? defaultExpanded },
            set: { folderOverrides[key] = $0 }
        )
    }

    /// Groups containers by compose project; standalone containers go last.
    private func projectBuckets(_ containers: [DockerContainer]) -> [ProjectBucket] {
        var order: [String] = []
        var byProject: [String: [DockerContainer]] = [:]
        var standalone: [DockerContainer] = []
        for container in containers {
            if let project = container.project {
                if byProject[project] == nil { order.append(project) }
                byProject[project, default: []].append(container)
            } else {
                standalone.append(container)
            }
        }
        var buckets = order
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ProjectBucket(project: $0, containers: byProject[$0]!) }
        if !standalone.isEmpty {
            buckets.append(ProjectBucket(project: nil, containers: standalone))
        }
        return buckets
    }
}

private struct ProjectBucket: Identifiable {
    let project: String?
    let containers: [DockerContainer]
    var id: String { project ?? "__standalone__" }
}

/// A Finder-style folder header for a compose project.
@MainActor
private struct FolderLabel: View {
    let name: String
    let containers: [DockerContainer]

    private var runningCount: Int { containers.filter { $0.state.isRunning }.count }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemBlue))
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(verbatim: runningCount > 0 ? "\(runningCount)/\(containers.count)" : "\(containers.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
    }
}

/// A section header with a colored dot and item count.
@MainActor
private struct GroupHeader: View {
    let title: String
    let count: Int
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

@MainActor
private struct ContainerRow: View {
    @EnvironmentObject private var state: AppState
    let container: DockerContainer
    var inProject: Bool = false
    @State private var hovering = false

    private var busy: Bool { state.busyContainers.contains(container.id) }
    private var title: String { inProject ? container.folderDisplayName : container.name }

    private var hasQuickActions: Bool {
        switch container.state {
        case .running, .paused, .exited, .created, .dead: return true
        default: return false
        }
    }
    private var showHoverActions: Bool { hovering && !busy && hasQuickActions }

    var body: some View {
        HStack(spacing: 10) {
            if busy {
                ProgressView().controlSize(.small).frame(width: 10)
            } else {
                StatusDot(color: container.state.color)
            }

            // Name (flexes)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // Image column
            Text(container.displayImage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 138, alignment: .trailing)

            // Ports / status column — constant footprint. Hover actions are
            // overlaid on top so they never shift the row's layout.
            portSummary
                .frame(width: 104, alignment: .trailing)
                .opacity(showHoverActions ? 0 : 1)
                .overlay(alignment: .trailing) {
                    if showHoverActions { quickActions }
                }
        }
        .frame(height: 24)
        .padding(.vertical, 3)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { ContainerActionsMenu(container: container) }
    }

    @ViewBuilder
    private var portSummary: some View {
        let published = container.publishedPorts
        if published.isEmpty {
            // Show the state label only while the container is active; a stopped
            // container shows nothing here rather than a redundant "Stopped" tag.
            if container.state.isActive {
                Text(container.state.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(container.state.color)
            }
        } else {
            HStack(spacing: 4) {
                ForEach(published.prefix(2)) { p in
                    PortChip(text: "\(p.hostPort ?? p.containerPort)", highlighted: container.state.isRunning)
                }
                if published.count > 2 {
                    Text("+\(published.count - 2)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 6) {
            switch container.state {
            case .running:
                miniButton("stop.fill") { state.perform(.stop, on: container) }
            case .paused:
                miniButton("play.fill") { state.perform(.unpause, on: container) }
                miniButton("stop.fill") { state.perform(.stop, on: container) }
            case .exited, .created, .dead:
                miniButton("play.fill") { state.perform(.start, on: container) }
            default:
                portSummary
            }
        }
    }

    private func miniButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.secondary)
    }
}

/// Context-menu actions shared by row + detail.
@MainActor
struct ContainerActionsMenu: View {
    @EnvironmentObject private var state: AppState
    let container: DockerContainer

    var body: some View {
        if container.state.isRunning {
            Button("Stop", systemImage: "stop.fill") { state.perform(.stop, on: container) }
            Button("Restart", systemImage: "arrow.clockwise") { state.perform(.restart, on: container) }
        } else if container.state.isPaused {
            Button("Resume", systemImage: "play.fill") { state.perform(.unpause, on: container) }
            Button("Stop", systemImage: "stop.fill") { state.perform(.stop, on: container) }
        } else {
            Button("Start", systemImage: "play.fill") { state.perform(.start, on: container) }
        }
        Divider()
        if container.state.isActive {
            Button("Kill", systemImage: "bolt.fill") { state.perform(.kill, on: container) }
        }
        Button("Remove", systemImage: "trash", role: .destructive) { state.perform(.remove, on: container) }
        Divider()
        Button("Copy Container ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(container.id, forType: .string)
        }
    }
}

// MARK: - Detail

@MainActor
struct ContainerDetail: View {
    @EnvironmentObject private var state: AppState
    let containerID: String
    @State private var showLogs = false

    /// Always reflects the latest snapshot from AppState so action buttons,
    /// status, and ports stay in sync after start/stop/pause/etc.
    private var container: DockerContainer {
        state.containers.first { $0.id == containerID } ?? .placeholder(id: containerID)
    }

    private var busy: Bool { state.busyContainers.contains(container.id) }

    var body: some View {
        Form {
            Section {
                DetailHeader(
                    symbol: "shippingbox.fill",
                    tint: container.state.color,
                    title: container.name,
                    statusColor: container.state.color,
                    subtitle: container.status.isEmpty ? container.state.label : container.status,
                    busy: busy
                )
            }

            Section {
                actionBar
            }

            if !container.ports.isEmpty {
                Section("Ports") {
                    ForEach(container.ports) { port in
                        LabeledContent {
                            if port.isPublished, let hp = port.hostPort {
                                Text(verbatim: "localhost:\(hp)")
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            } else {
                                Text("Internal").foregroundStyle(.secondary)
                            }
                        } label: {
                            Label {
                                Text(port.display).font(.system(.body, design: .monospaced))
                            } icon: {
                                Image(systemName: port.isPublished ? "arrow.left.arrow.right" : "lock")
                                    .foregroundStyle(port.isPublished ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }
            }

            Section("Details") {
                valueRow("Image", container.image)
                valueRow("Container ID", container.shortID)
                if let project = container.project {
                    LabeledContent("Project", value: project)
                }
                valueRow("Command", container.command)
                LabeledContent("Created", value: container.runningFor)
                if let cpu = container.cpuPerc { LabeledContent("CPU", value: cpu) }
                if let mem = container.memUsage {
                    LabeledContent("Memory", value: mem + (container.memPerc.map { " (\($0))" } ?? ""))
                }
                LabeledContent("Size", value: container.size)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(container.name)
        .sheet(isPresented: $showLogs) {
            LogsSheet(container: container)
        }
    }

    /// A details row with a selectable, monospaced, middle-truncated value.
    private func valueRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 10) {
            switch container.state {
            case .running:
                actionButton("Stop", "stop.fill", tint: .red) { state.perform(.stop, on: container) }
                actionButton("Restart", "arrow.clockwise") { state.perform(.restart, on: container) }
                actionButton("Kill", "bolt.fill", tint: .orange) { state.perform(.kill, on: container) }
            case .paused:
                actionButton("Resume", "play.fill", tint: .green) { state.perform(.unpause, on: container) }
                actionButton("Stop", "stop.fill", tint: .red) { state.perform(.stop, on: container) }
            default:
                actionButton("Start", "play.fill", tint: .green) { state.perform(.start, on: container) }
            }
            actionButton("Logs", "doc.text") { showLogs = true }
            Spacer()
            actionButton("Remove", "trash", tint: .red) { state.perform(.remove, on: container) }
        }
        .controlSize(.large)
        .disabled(busy)
    }

    @ViewBuilder
    private func actionButton(_ title: String, _ icon: String, tint: Color? = nil,
                              prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let label = Image(systemName: icon)
            .frame(width: 20)
            .accessibilityLabel(title)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .tint(tint ?? .accentColor)
                .help(title)
        } else if let tint {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .tint(tint)
                .help(title)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .help(title)
        }
    }
}

@MainActor
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

@MainActor
private struct LogsSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let container: DockerContainer
    @State private var logs = "Loading…"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs · \(container.name)").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                Text(logs)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 640, height: 460)
        .task {
            logs = await state.fetchLogs(for: container)
        }
    }
}
