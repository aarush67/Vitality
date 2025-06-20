import SwiftUI
import AppKit

@main
struct VitalityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    let monitor = SystemMonitor()
    let settings = SettingsModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ✅ Start system monitoring
        monitor.startMonitoring()

        // ✅ Prepare haptic feedback engine
        HapticManager.shared.prepareAdvanced()

        // ✅ Set up menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "Vitality")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // ✅ Prepare popover (but attach view on toggle)
        popover.behavior = .transient
        popover.animates = true
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // ✅ Inject new view to ensure up-to-date content
            let mainView = MainView(monitor: monitor, settings: settings)
            popover.contentViewController = NSHostingController(rootView: mainView)
            popover.contentSize = NSSize(width: 360, height: 600)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

