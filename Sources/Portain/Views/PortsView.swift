import SwiftUI

// MARK: - List

@MainActor
struct PortsList: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: ListeningPort.ID?

    var body: some View {
        Group {
            if state.filteredPorts.isEmpty {
                EmptyState(
                    systemImage: "network.slash",
                    title: state.search.isEmpty ? "Nothing listening" : "No matches",
                    message: state.search.isEmpty
                        ? "No processes are listening on TCP ports right now."
                        : "No ports match “\(state.search)”."
                )
            } else {
                Table(state.filteredPorts, selection: $selection) {
                    TableColumn("Port") { port in
                        Text(verbatim: "\(port.port)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(port.isLocalOnly ? .secondary : .primary)
                    }
                    .width(min: 46, ideal: 56, max: 72)

                    TableColumn("Process") { port in
                        PortProcessCell(port: port, state: state)
                    }
                    .width(min: 80, ideal: 180)

                    TableColumn("PID") { port in
                        Text(verbatim: "\(port.pid)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 46, ideal: 58, max: 72)

                    TableColumn("Type") { port in
                        Text(port.typeLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 48, ideal: 62, max: 84)

                    TableColumn("Address") { port in
                        HStack(spacing: 5) {
                            Image(systemName: port.isLocalOnly ? "lock.fill" : "globe")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(port.address)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .help(port.scopeLabel)
                    }
                    .width(min: 64, ideal: 130)

                    TableColumn("User") { port in
                        Text(port.user)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 40, ideal: 84, max: 120)

                    TableColumn("Actions") { port in
                        PortActionsCell(port: port, state: state)
                    }
                    .width(56)
                }
                .tableStyle(.inset)
                .contextMenu(forSelectionType: ListeningPort.ID.self) { ids in
                    let ports = state.filteredPorts.filter { ids.contains($0.id) }
                    if ports.count > 1 {
                        PortBulkActionsMenu(ports: ports, state: state)
                    } else if let port = ports.first {
                        PortActionsMenu(port: port, state: state)
                    }
                }
            }
        }
        .navigationTitle("Ports")
    }
}

/// Process name (or backing container name) plus a docker badge, on one line.
@MainActor
private struct PortProcessCell: View {
    let port: ListeningPort
    let state: AppState

    private var linkedContainer: DockerContainer? {
        state.container(forHostPort: port.port)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(linkedContainer?.name ?? port.command)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if linkedContainer != nil {
                Pill(text: "docker", color: .blue, systemImage: "shippingbox.fill")
            } else if port.isDocker {
                Pill(text: "docker", color: .blue)
            }
        }
    }
}

/// Inline kill button with confirmation, used in the table's Actions column.
@MainActor
private struct PortActionsCell: View {
    let port: ListeningPort
    let state: AppState
    @State private var confirmKill = false

    var body: some View {
        Button(role: .destructive) {
            confirmKill = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
        .help("Kill process on this port")
        .contextMenu { PortActionsMenu(port: port, state: state) }
        .confirmationDialog(
            Text(verbatim: "Kill \(port.command) on port \(port.port)?"),
            isPresented: $confirmKill,
            titleVisibility: .visible
        ) {
            Button("Terminate (SIGTERM)") { state.killPort(port, force: false) }
            Button("Force Kill (SIGKILL)", role: .destructive) { state.killPort(port, force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(verbatim: "PID \(port.pid) — \(port.command). This stops the process bound to this port.")
        }
    }
}

@MainActor
struct PortActionsMenu: View {
    let port: ListeningPort
    let state: AppState

    var body: some View {
        Button("Terminate Process", systemImage: "xmark.circle") {
            state.killPort(port, force: false)
        }
        Button("Force Kill", systemImage: "bolt.fill", role: .destructive) {
            state.killPort(port, force: true)
        }
        Divider()
        Button("Copy PID") { copy("\(port.pid)") }
        Button("Copy Port") { copy("\(port.port)") }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Context-menu actions when multiple ports are selected.
@MainActor
struct PortBulkActionsMenu: View {
    let ports: [ListeningPort]
    let state: AppState

    var body: some View {
        Button("Terminate \(ports.count) Processes", systemImage: "xmark.circle") {
            for port in ports { state.killPort(port, force: false) }
        }
        Button("Force Kill \(ports.count) Processes", systemImage: "bolt.fill", role: .destructive) {
            for port in ports { state.killPort(port, force: true) }
        }
        Divider()
        Button("Copy \(ports.count) PIDs") {
            let pids = ports.map { String($0.pid) }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pids, forType: .string)
        }
    }
}

// MARK: - Detail

@MainActor
struct PortDetail: View {
    @EnvironmentObject private var state: AppState
    let port: ListeningPort
    @State private var confirmForce = false
    @State private var commandLine: String?

    private var linkedContainer: DockerContainer? {
        state.container(forHostPort: port.port)
    }

    var body: some View {
        Form {
            Section {
                DetailHeader(
                    symbol: "network",
                    symbolText: "\(port.port)",
                    tint: .accentColor,
                    title: linkedContainer?.name ?? port.command,
                    statusColor: port.isLocalOnly ? .secondary : .green,
                    subtitle: "\(port.proto) · \(port.scopeLabel)"
                )
            }

            Section {
                actionBar
            }

            if let container = linkedContainer {
                Section("Backed by container") {
                    Button {
                        state.tab = .containers
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(container.state.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(container.name).foregroundStyle(.primary)
                                Text(container.displayImage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Switch to this container")
                }
            }

            Section("Details") {
                LabeledContent("Process", value: port.command)
                commandRow
                valueRow("PID", "\(port.pid)")
                LabeledContent("User", value: port.user)
                valueRow("Address", "\(port.address):\(port.port)")
                LabeledContent("Protocol", value: port.proto)
                LabeledContent("Family", value: port.families.sorted().joined(separator: ", "))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: "Port \(port.port)"))
        .task(id: port.id) {
            commandLine = nil
            let cmd = await state.commandLine(for: port)
            commandLine = cmd.isEmpty ? "—" : cmd
        }
    }

    /// Full command line that launched the process, fetched lazily via `ps`.
    /// Wraps over multiple lines since command lines can be long.
    @ViewBuilder
    private var commandRow: some View {
        LabeledContent("Command") {
            if let commandLine {
                Text(commandLine)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 10) {
            actionButton("Terminate", "xmark.circle.fill", tint: .orange) {
                state.killPort(port, force: false)
            }
            actionButton("Force Kill", "bolt.fill", tint: .red) {
                confirmForce = true
            }
            actionButton("Copy PID", "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(port.pid)", forType: .string)
            }
            Spacer()
        }
        .controlSize(.large)
        .confirmationDialog(Text(verbatim: "Force kill PID \(port.pid)?"),
                            isPresented: $confirmForce, titleVisibility: .visible) {
            Button("Force Kill (SIGKILL)", role: .destructive) { state.killPort(port, force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SIGKILL can't be caught — the process won't get to clean up.")
        }
    }

    /// Icon-only bordered button with a hover-highlight and tooltip, matching
    /// the container detail action bar.
    @ViewBuilder
    private func actionButton(_ title: String, _ icon: String, tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        let label = Image(systemName: icon)
            .frame(width: 20)
            .accessibilityLabel(title)
        if let tint {
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
