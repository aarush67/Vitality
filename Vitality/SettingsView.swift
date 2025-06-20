import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeader(title: "Dashboard Modules")
            settingsToggle("CPU", binding: $settings.showCPU)
            settingsToggle("Memory", binding: $settings.showMemory)
            settingsToggle("Battery", binding: $settings.showBattery)
            settingsToggle("Disk Usage", binding: $settings.showDisks)
            settingsToggle("Uptime", binding: $settings.showUptime)
            settingsToggle("Thermal Status", binding: $settings.showThermal)
            settingsToggle("Top Apps", binding: $settings.showTopApps)
            settingsToggle("Network", binding: $settings.showNetwork)

            Divider().padding(.vertical, 10)

            SectionHeader(title: "Feedback")
            Toggle("Enable Haptics", isOn: Binding(
                get: { HapticManager.shared.hapticsEnabled },
                set: { HapticManager.shared.hapticsEnabled = $0 }
            ))
            .toggleStyle(.switch)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)
        )
        .frame(width: 320)
        .padding()
    }

    private func settingsToggle(_ label: String, binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
    }
}

