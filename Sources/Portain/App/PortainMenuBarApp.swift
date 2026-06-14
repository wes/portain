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
    private var portService = PortService()
    private var timer: Timer?
    private var ports: [ListeningPort] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        let titleItem = NSMenuItem(title: "Portain", action: nil, keyEquivalent: "")
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
            let emptyItem = NSMenuItem(title: "No ports in use", action: nil, keyEquivalent: "")
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
            
            // Regular ports
            if !regularPorts.isEmpty {
                for port in regularPorts.sorted(by: { $0.port < $1.port }) {
                    let title = String(format: ":%d - %@", port.port, truncateCommand(port.command))
                    let item = NSMenuItem(title: title, action: #selector(killPort(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = port
                    
                    // Add submenu with details
                    let submenu = NSMenu()
                    
                    let detailsItem = NSMenuItem(title: "PID: \(port.pid)", action: nil, keyEquivalent: "")
                    detailsItem.isEnabled = false
                    submenu.addItem(detailsItem)
                    
                    let addressItem = NSMenuItem(title: "Address: \(port.scopeLabel)", action: nil, keyEquivalent: "")
                    addressItem.isEnabled = false
                    submenu.addItem(addressItem)
                    
                    submenu.addItem(NSMenuItem.separator())
                    
                    let killItem = NSMenuItem(title: "Kill Process", action: #selector(killPort(_:)), keyEquivalent: "")
                    killItem.target = self
                    killItem.representedObject = port
                    killItem.attributedTitle = NSAttributedString(string: "Kill Process", attributes: [
                        .foregroundColor: NSColor.systemRed,
                        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    ])
                    submenu.addItem(killItem)
                    
                    let forceKillItem = NSMenuItem(title: "Force Kill", action: #selector(forceKillPort(_:)), keyEquivalent: "")
                    forceKillItem.target = self
                    forceKillItem.representedObject = port
                    forceKillItem.attributedTitle = NSAttributedString(string: "Force Kill", attributes: [
                        .foregroundColor: NSColor.systemRed,
                        .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
                    ])
                    submenu.addItem(forceKillItem)
                    
                    item.submenu = submenu
                    menu.addItem(item)
                }
            }
            
            // Docker ports
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
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshPorts), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        // Auto refresh toggle
        let autoRefreshItem = NSMenuItem(title: "Auto Refresh", action: #selector(toggleAutoRefresh), keyEquivalent: "")
        autoRefreshItem.target = self
        autoRefreshItem.state = timer != nil ? .on : .off
        menu.addItem(autoRefreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    private func truncateCommand(_ command: String) -> String {
        let components = command.split(separator: "/")
        if let last = components.last {
            return String(last).replacingOccurrences(of: " ", with: "")
        }
        return command
    }
    
    @objc private func openMainApp() {
        // Try to launch the main Portain app
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.joedesigns.Portain") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // If not found as an app, try to run it from the build directory
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["swift", "run", "Portain"]
            task.currentDirectoryPath = "/Users/wes/Sites/portain"
            task.launch()
        }
    }
    
    @objc private func killPort(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        
        Task {
            do {
                try await portService.kill(pid: port.pid, force: false)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshPorts()
            } catch {
                print("Failed to kill port: \(error)")
            }
        }
    }
    
    @objc private func forceKillPort(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? ListeningPort else { return }
        
        Task {
            do {
                try await portService.kill(pid: port.pid, force: true)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshPorts()
            } catch {
                print("Failed to force kill port: \(error)")
            }
        }
    }
    
    @objc private func refreshPorts() {
        Task {
            await loadPorts()
        }
    }
    
    private func loadPorts() async {
        let newPorts = await portService.listListeningPorts()
        await MainActor.run {
            self.ports = newPorts.filter { !$0.isLocalOnly }
            self.updateMenu()
        }
    }
    
    @objc private func toggleAutoRefresh() {
        if timer != nil {
            stopAutoRefresh()
        } else {
            startAutoRefresh()
        }
        updateMenu()
    }
    
    private func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { await self.loadPorts() }
        }
        Task { await loadPorts() }
    }
    
    private func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}