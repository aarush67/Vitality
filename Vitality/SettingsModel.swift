import Foundation

class SettingsModel: ObservableObject {
    @Published var showCPU = true
    @Published var showMemory = true
    @Published var showBattery = true
    @Published var showDisks = true
    @Published var showUptime = true
    @Published var showThermal = true
    @Published var showTopApps = true
    @Published var showNetwork = true
}

