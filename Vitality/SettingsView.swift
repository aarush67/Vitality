import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Form {
            Section(header: Text("Dashboard Modules")) {
                Toggle("CPU", isOn: $settings.showCPU)
                Toggle("Memory", isOn: $settings.showMemory)
                Toggle("Battery", isOn: $settings.showBattery)
                Toggle("Disk Usage", isOn: $settings.showDisks)
                Toggle("Uptime", isOn: $settings.showUptime)
                Toggle("Thermal Status", isOn: $settings.showThermal)
                Toggle("Top Apps", isOn: $settings.showTopApps)
                Toggle("Network", isOn: $settings.showNetwork)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

