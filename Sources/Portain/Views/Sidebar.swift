import SwiftUI

@MainActor
struct Sidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation
            VStack(spacing: 4) {
                SidebarItem(
                    tab: .containers,
                    icon: "shippingbox.fill",
                    title: "Containers",
                    count: state.containers.count,
                    running: state.runningCount
                )
                SidebarItem(
                    tab: .ports,
                    icon: "network",
                    title: "Ports",
                    count: state.ports.count,
                    running: nil,
                    showBadge: false
                )
            }
            .padding(.horizontal, 10)

            Spacer()

            StatusFooter()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
private struct SidebarItem: View {
    @EnvironmentObject private var state: AppState
    let tab: Tab
    let icon: String
    let title: String
    let count: Int
    /// When non-nil, the badge shows "running/total" (e.g. 1/3).
    let running: Int?
    /// Whether to show the trailing count badge.
    var showBadge: Bool = true

    private var selected: Bool { state.tab == tab }

    @ViewBuilder
    private var countBadge: some View {
        Group {
            if let running {
                HStack(spacing: 0) {
                    Text(verbatim: "\(running)")
                        .foregroundStyle(running > 0 ? Color.green : Color.secondary)
                    Text(verbatim: "/\(count)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(verbatim: "\(count)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
    }

    var body: some View {
        Button {
            state.tab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if showBadge { countBadge }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct StatusFooter: View {
    @EnvironmentObject private var state: AppState

    private var dockerColor: Color {
        if !state.dockerInstalled { return .secondary }
        return state.dockerDaemonUp ? .green : .orange
    }

    private var dockerText: String {
        if !state.dockerInstalled { return "Docker not installed" }
        return state.dockerDaemonUp ? "Docker connected" : "Docker daemon down"
    }

    /// App marketing version from the bundle; falls back when run unbundled
    /// (e.g. via `swift run` during development).
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                StatusDot(color: dockerColor, pulsing: state.dockerDaemonUp)
                Text(dockerText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                Text("Portain")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("v\(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            }
            // if let last = state.lastRefresh {
            //     Text("Updated \(last.formatted(date: .omitted, time: .standard))")
            //         .font(.system(size: 10))
            //         .foregroundStyle(.tertiary)
            // }
            
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}
