import SwiftUI
import AppKit
import Combine

@main
struct VitalityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(monitor: appDelegate.monitor)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var monitor = SystemMonitor()
    var window: FloatingPanel?
    var eventMonitor: Any?
    var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.startMonitoring()

        // ✅ Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "Vitality Monitor")
            button.action = #selector(toggleWindow)
            button.target = self
        }

        // ✅ Live CPU % in menu bar
        monitor.$cpuUsage
            .receive(on: RunLoop.main)
            .sink { [weak self] usage in
                let percent = Int(usage * 100)
                self?.statusItem?.button?.title = " \(percent)%"
            }
            .store(in: &cancellables)

        // ✅ Auto-close window when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeWindow()
        }
    }

    @objc func toggleWindow() {
        if let window = window, window.isVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }

    func showWindow() {
        let contentView = MainView(monitor: monitor)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 20)

        let hosting = NSHostingController(rootView: contentView)

        let newWindow = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.contentView = hosting.view
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = true
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .transient]
        newWindow.ignoresMouseEvents = false
        newWindow.isReleasedWhenClosed = false
        newWindow.alphaValue = 0

        // 🧭 Position below the menu bar icon
        if let button = statusItem?.button,
           let screen = button.window?.screen {
            let buttonFrame = button.convert(button.bounds, to: nil)
            let screenFrame = button.window?.convertToScreen(buttonFrame) ?? .zero
            let x = screenFrame.origin.x + screenFrame.width / 2 - 180
            let y = screenFrame.origin.y - 4
            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }

        newWindow.makeKeyAndOrderFront(nil)

        // ✨ Smooth fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            newWindow.animator().alphaValue = 1
        }

        self.window = newWindow
    }

    func closeWindow() {
        if let window = window {
            window.orderOut(nil)
            self.window = nil
        }
    }
}

// ✅ Interactive floating window
class FloatingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

