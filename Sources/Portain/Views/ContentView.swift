import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedContainer: DockerContainer.ID?
    @State private var selectedPort: ListeningPort.ID?

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 208, ideal: 224, max: 280)
        } content: {
            Group {
                switch state.tab {
                case .containers:
                    ContainersList(selection: $selectedContainer)
                case .ports:
                    PortsList(selection: $selectedPort)
                }
            }
            .navigationSplitViewColumnWidth(
                min: state.tab == .ports ? 520 : 320,
                ideal: state.tab == .ports ? 640 : 380,
                max: state.tab == .ports ? 900 : 520
            )
        } detail: {
            DetailPane(
                selectedContainer: $selectedContainer,
                selectedPort: $selectedPort
            )
            .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await state.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(state.isRefreshing ? 360 : 0))
                        .animation(state.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default, value: state.isRefreshing)
                }
                .help("Refresh now (⌘R)")

                Toggle(isOn: Binding(
                    get: { state.autoRefresh },
                    set: { _ in state.toggleAutoRefresh() }
                )) {
                    Image(systemName: "timer")
                }
                .toggleStyle(.button)
                .help("Auto-refresh every 3s")
            }
        }
        .searchable(text: $state.search, placement: .toolbar, prompt: searchPrompt)
    }

    private var searchPrompt: String {
        state.tab == .containers ? "Search containers, images, ports" : "Search ports, processes, PIDs"
    }
}

/// Routes the detail pane based on the active tab + selection.
@MainActor
private struct DetailPane: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedContainer: DockerContainer.ID?
    @Binding var selectedPort: ListeningPort.ID?

    var body: some View {
        switch state.tab {
        case .containers:
            if let id = selectedContainer,
               state.containers.contains(where: { $0.id == id }) {
                ContainerDetail(containerID: id)
            } else {
                EmptyState(
                    systemImage: "shippingbox",
                    title: "Select a container",
                    message: "Choose a container to inspect its ports, status, and run actions."
                )
            }
        case .ports:
            if let id = selectedPort,
               let port = state.ports.first(where: { $0.id == id }) {
                PortDetail(port: port)
            } else {
                EmptyState(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: "Select a port",
                    message: "Choose a listening port to see the process behind it and free it up."
                )
            }
        }
    }
}
