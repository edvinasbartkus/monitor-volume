import AppKit
import ApplicationServices
import VolumeCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = VolumeController()
    private let keyTap = MediaKeyTap()
    private var item: NSStatusItem!
    private var permissionTimer: Timer?
    private var menuIsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Monitor Volume")
        controller.onChange = { [weak self] in self?.updateMenu() }
        keyTap.onKey = { [weak self] action, fine in self?.controller.handle(action, fine: fine) ?? false }
        keyTap.onAvailabilityChange = { [weak self] in self?.updateMenu() }
        keyTap.start()
        controller.start()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !AXIsProcessTrusted() { self.keyTap.stop() }
            else if !self.keyTap.isRunning { self.keyTap.start() }
            self.updateMenu()
        }
        updateMenu()
    }

    private func updateMenu() {
        item.button?.toolTip = "Monitor Volume — \(controller.status)"
        // Do not replace an open menu under the user's pointer.
        guard !menuIsOpen else { return }
        let menu = NSMenu()
        menu.delegate = self
        add("Monitor Volume", to: menu)
        add("Output: \(controller.output?.name ?? "None")", to: menu)
        add(controller.status, to: menu)
        if !keyTap.isRunning {
            add(AXIsProcessTrusted() ? "Keyboard tap unavailable — check permissions" : "Keyboard permission needed", to: menu)
            add("Enable keyboard control…", action: #selector(requestPermissions), to: menu)
        }
        menu.addItem(.separator())
        add("Volume Up", action: #selector(volumeUp), enabled: controller.isReady, to: menu)
        add("Volume Down", action: #selector(volumeDown), enabled: controller.isReady, to: menu)
        add("Mute / Unmute", action: #selector(mute), enabled: controller.isReady, to: menu)
        let stepMenuItem = NSMenuItem(title: "Volume step: \(controller.stepPercent)%", action: nil, keyEquivalent: "")
        let stepMenu = NSMenu()
        for percentage in VolumeStep.supportedPercentages {
            let entry = add("\(percentage)% per tick", action: #selector(changeStep(_:)), to: stepMenu)
            entry.tag = percentage
            entry.state = controller.stepPercent == percentage ? .on : .off
        }
        stepMenuItem.submenu = stepMenu
        menu.addItem(stepMenuItem)
        menu.addItem(.separator())
        if let output = controller.output, output.isDisplay {
            let link = NSMenuItem(title: "Link current output to monitor", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let automatic = add("Automatic (unique name match)", action: #selector(linkMonitor(_:)), to: submenu)
            automatic.representedObject = MonitorLinkChoice(outputUID: output.uid, monitorID: nil)
            automatic.state = controller.selectedLink == nil ? .on : .off
            for (index, monitor) in controller.monitors.enumerated() {
                let entry = add("\(monitor.identity.name) — connection \(index + 1)", action: #selector(linkMonitor(_:)), to: submenu)
                entry.representedObject = MonitorLinkChoice(outputUID: output.uid, monitorID: monitor.identity.id)
                entry.toolTip = monitor.details.ioDisplayLocation
                entry.state = controller.selectedLink == monitor.identity.id ? .on : .off
            }
            if controller.monitors.isEmpty { add("No DDC monitors found", to: submenu) }
            link.submenu = submenu
            menu.addItem(link)
        }
        let pause = add("Pause keyboard control", action: #selector(togglePause), to: menu)
        pause.state = controller.paused ? .on : .off
        add("Refresh monitors", action: #selector(refresh), to: menu)
        menu.addItem(.separator())
        add("Quit Monitor Volume", action: #selector(quit), to: menu)
        item.menu = menu
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, enabled: Bool = true, to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = action != nil && enabled
        menu.addItem(entry)
        menu.autoenablesItems = false
        return entry
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        DispatchQueue.main.async { [weak self] in self?.updateMenu() }
    }

    @objc private func volumeUp() { controller.handle(.up) }
    @objc private func volumeDown() { controller.handle(.down) }
    @objc private func mute() { controller.handle(.mute) }
    @objc private func changeStep(_ sender: NSMenuItem) { controller.setStepPercent(sender.tag) }
    @objc private func refresh() { controller.refresh(); keyTap.start(); updateMenu() }
    @objc private func togglePause() { controller.paused.toggle(); controller.refresh() }
    @objc private func linkMonitor(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? MonitorLinkChoice else { return }
        controller.link(outputUID: choice.outputUID, monitorID: choice.monitorID)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func requestPermissions() {
        NSApp.activate(ignoringOtherApps: true)
        let pane: String
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            pane = "Privacy_Accessibility"
        } else {
            // Some macOS releases also require Input Monitoring for a global media-key tap.
            if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
            keyTap.start()
            pane = "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        keyTap.stop()
    }
}

private struct MonitorLinkChoice {
    let outputUID: String
    let monitorID: String?
}
