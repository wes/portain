import SwiftUI
import AppKit

@main
struct PortainMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var timer: Timer?
    private var ports: [ListeningPort] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Hide from dock
        setupStatusItem()
        startAutoRefresh()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Portain")
            button.image?.isTemplate = true
            button.toolTip = "Portain - Port Manager"
        }
        
        setupMenu()
    }
    
    private func setupMenu() {
        menu = NSMenu()
        menu?.autoenablesItems = false
        
        statusItem?.menu = menu
        updateMenu()
    }
    
    private func updateMenu() {
        guard let menu = menu else { return }
        menu.removeAllItems()
        
        // Header
        let titleItem = NSMenuItem(title: "Portain Menu Bar", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open main app
        let openItem = NSMenuItem(title: "Open Portain", action: #selector(openMainApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Ports section
        if ports.isEmpty {
            let emptyItem = NSMenuItem(title: "No active ports", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let portsHeader = NSMenuItem(title: "Active Ports (\(ports.count))", action: nil, keyEquivalent: "")
            portsHeader.isEnabled = false
            menu.addItem(portsHeader)
            
            menu.addItem(NSMenuItem.separator())
            
            // Group ports by docker vs non-docker
            let dockerPorts = ports.filter { $0.isDocker }
            let regularPorts = ports.filter { !$0.isDocker }
            
            // Regular ports (clickable to kill)
            if !regularPorts.isEmpty {
                for port in regularPorts.sorted(by: { $0.port < $1.port }) {
                    let title = String(format: ":%d - %@", port.port, truncateCommand(port.command))
                    let item = NSMenuItem(title: title, action: #selector(killPort(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = port
                    item.toolTip = "Click to kill (PID: \(port.pid))"
                    menu.addItem(item)
                }
            }
            
            // Docker ports (non-clickable)
            if !dockerPorts.isEmpty {
                if !regularPorts.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                }
                
                let dockerHeader = NSMenuItem(title: "Docker Ports", action: nil, keyEquivalent: "")
                dockerHeader.isEnabled = false
                dockerHeader.attributedTitle = NSAttributedString(string: "Docker Ports", attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                ])
                menu.addItem(dockerHeader)
                
                for port in dockerPorts.sorted(by: { $0.port < $1.port }) {
                    let title = String(format: ":%d - Docker", port.port)
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Refresh
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshPorts), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Menu Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    private func truncateCommand(_ command: String) -> String {
        let components = command.split(separator: "/")
        if let last = components.last {
            let clean = String(last).replacingOccurrences(of: " ", with: "")
            return String(clean.prefix(20))
        }
        return String(command.prefix(20))
    }
    
    @objc private func openMainApp() {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["swift", "run", "Portain"]
        task.currentDirectoryPath = FileManager.default.currentDirectoryPath
        
        do {
            try task.run()
        } catch {
            print("Failed to launch main app: \(error)")
        }
    }
    
    @objc private func killPort(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        
        // Show confirmation alert
        let alert = NSAlert()
        alert.messageText = "Kill Process?"
        alert.informativeText = "Kill \(port.command) (PID: \(port.pid)) using port \(port.port)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                do {
                    let portService = PortService()
                    try await portService.kill(pid: port.pid, force: false)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await refreshPorts()
                } catch {
                    await MainActor.run {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "Failed to kill process"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.alertStyle = .critical
                        errorAlert.runModal()
                    }
                }
            }
        }
    }
    
    @objc private func refreshPorts() {
        Task {
            await loadPorts()
        }
    }
    
    private func loadPorts() async {
        let portService = PortService()
        let newPorts = await portService.listListeningPorts()
        await MainActor.run {
            self.ports = newPorts.filter { !$0.isLocalOnly }
            self.updateMenu()
        }
    }
    
    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { await self.loadPorts() }
        }
        Task { await loadPorts() }
    }
}