import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private let lights = LumeController()
    private let camera = CameraMonitor()
    @Published private(set) var autoMode = UserDefaults.standard.object(forKey: "autoCamera") as? Bool ?? true
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private lazy var popover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        let host = NSHostingController(rootView: ControlPanel(lights: lights, app: self))
        host.sizingOptions = .preferredContentSize   // grows as panel sections expand
        p.contentViewController = host
        return p
    }()

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        lights.onStatusChange = { [weak self] in self?.refreshIcon() }
        camera.onChange = { [weak self] active in
            guard let self, self.autoMode else { return }
            self.setPower(active)
        }
        camera.start()
        refreshIcon()
    }

    func setPower(_ on: Bool) {
        lights.setPower(on)
        refreshIcon()
    }

    // Left-click toggles. Right-click (or Option-click) opens the controls.
    @objc private func clicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.option) == true {
            togglePopover()
        } else {
            setPower(!lights.anyOn)
        }
    }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // An accessory app has to activate for the rename field to take keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func toggleAuto() {
        autoMode.toggle()
        UserDefaults.standard.set(autoMode, forKey: "autoCamera")
        if autoMode && camera.inUse != lights.anyOn { setPower(camera.inUse) }
    }

    func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        launchAtLogin = service.status == .enabled
    }

    private func refreshIcon() {
        statusItem.button?.image = lights.connectedCount == 0 ? PanelIcon.disconnected
                                 : (lights.anyOn ? PanelIcon.on : PanelIcon.off)
    }
}

if CommandLine.arguments.contains("--selftest") { Telink.selfTest(); exit(0) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
