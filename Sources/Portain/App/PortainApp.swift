import SwiftUI
import AppKit

@main
struct PortainApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 880, minHeight: 560)
                .task { await state.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Portain") { showAboutPanel() }
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await state.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Presents a customized standard About panel with a short description and
/// a Joedesigns.com credit.
@MainActor
func showAboutPanel() {
    let body = NSMutableParagraphStyle()
    body.alignment = .center
    body.lineSpacing = 2
    body.paragraphSpacing = 10

    let credits = NSMutableAttributedString()

    credits.append(NSAttributedString(
        string: "See what's running — your Docker containers and the processes holding your ports — and act on them fast. Pure visualization plus simple, safe actions. Read-only by design.\n\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: body,
        ]
    ))

    credits.append(NSAttributedString(
        string: "Made and brought to you by ",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: body,
        ]
    ))
    credits.append(NSAttributedString(
        string: "Joedesigns.com",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.linkColor,
            .link: URL(string: "https://joedesigns.com")!,
            .paragraphStyle: body,
        ]
    ))

    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Portain",
        .credits: credits,
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Joedesigns.com",
    ])
    NSApp.activate(ignoringOtherApps: true)
}

/// Ensures the SPM-built executable behaves like a regular foreground app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
