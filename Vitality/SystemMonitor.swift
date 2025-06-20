import Foundation
import IOKit.ps
import IOKit
import AppKit

class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var batteryHealth: Double = 0
    @Published var batteryCycles: Int = 0
    @Published var disks: [DiskInfo] = []
    @Published var uptime: String = ""
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var topCPUApps: [AppUsage] = []
    @Published var topMemoryApps: [AppUsage] = []
    @Published var networkRx: Double = 0
    @Published var networkTx: Double = 0
    @Published var isActive: Bool = false
    @Published var cpuHistory: [Double] = []
    
    func killProcess(pid: Int) {
        let task = Process()
        task.launchPath = "/bin/kill"
        task.arguments = ["-9", "\(pid)"]
        do {
            try task.run()
        } catch {
            print("❌ Failed to kill process \(pid): \(error.localizedDescription)")
        }
    }


    private var previousCPUInfo: host_cpu_load_info_data_t?
    private var lastNetwork: (rx: UInt64, tx: UInt64)? = nil
    private var timer: Timer?

    func startMonitoring() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.update()
        }
    }

    private func update() {
        DispatchQueue.global().async {
            let cpu = self.getCPUUsage()
            let mem = self.getMemoryUsage()
            let (battHealth, cycleCount) = self.readBatteryStats()
            let disks = self.getDiskInfo()
            let uptime = self.getUptime()
            let thermal = ProcessInfo.processInfo.thermalState
            let (rx, tx) = self.getNetworkStats()
            let cpuApps = self.getTopCPUApps()
            let memApps = self.getTopMemoryApps()

            DispatchQueue.main.async {
                self.cpuUsage = cpu
                self.memoryUsage = mem
                self.batteryHealth = battHealth
                self.batteryCycles = cycleCount
                self.disks = disks
                self.uptime = uptime
                self.thermalState = thermal
                self.networkRx = rx
                self.networkTx = tx
                self.topCPUApps = cpuApps
                self.topMemoryApps = memApps
                self.cpuHistory.append(cpu)
                if self.cpuHistory.count > 50 {
                    self.cpuHistory.removeFirst()
                }
            }
        }
    }

    private func getCPUUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var cpuInfo = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = Double(cpuInfo.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3)
        let total = user + system + idle + nice

        if let previous = previousCPUInfo {
            let prevTotal = Double(previous.cpu_ticks.0 + previous.cpu_ticks.1 + previous.cpu_ticks.2 + previous.cpu_ticks.3)
            let prevIdle = Double(previous.cpu_ticks.2)
            let totalDiff = total - prevTotal
            let idleDiff = idle - prevIdle
            previousCPUInfo = cpuInfo
            return totalDiff == 0 ? 0 : (1.0 - (idleDiff / totalDiff))
        } else {
            previousCPUInfo = cpuInfo
            return 0
        }
    }

    private func getMemoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(UInt32(MemoryLayout.size(ofValue: stats) / MemoryLayout<integer_t>.size))
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let used = Double(stats.active_count + stats.wire_count) * Double(vm_kernel_page_size)
        let total = used + Double(stats.free_count + stats.inactive_count) * Double(vm_kernel_page_size)
        return total == 0 ? 0 : used / total
    }

    private func readBatteryStats() -> (Double, Int) {
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-rn", "AppleSmartBattery"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return (1.0, 0) }

        var maxCap = 1, designCap = 1, cycles = 0
        for line in output.split(separator: "\n") {
            if line.contains("MaxCapacity") {
                maxCap = Int(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            }
            if line.contains("DesignCapacity") {
                designCap = Int(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            }
            if line.contains("CycleCount") {
                cycles = Int(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
            }
        }

        let health = designCap > 0 ? Double(maxCap) / Double(designCap) : 1.0
        return (health, cycles)
    }

    private func getUptime() -> String {
        let interval = ProcessInfo.processInfo.systemUptime
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "N/A"
    }

    private func getNetworkStats() -> (Double, Double) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0

        let task = Process()
        task.launchPath = "/usr/sbin/netstat"
        task.arguments = ["-ib"]
        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
        } catch {
            print("❌ Failed to run netstat: \(error.localizedDescription)")
            return (0, 0)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return (0, 0)
        }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 10, parts[0] != "Name",
               let ibytes = UInt64(parts[6]), let obytes = UInt64(parts[9]) {
                rx += ibytes
                tx += obytes
            }
        }

        if let last = lastNetwork {
            let deltaRx = max(0, Double(rx) - Double(last.rx)) / 2.0
            let deltaTx = max(0, Double(tx) - Double(last.tx)) / 2.0
            lastNetwork = (rx, tx)
            return (deltaRx, deltaTx)
        } else {
            lastNetwork = (rx, tx)
            return (0, 0)
        }
    }

    func getTopCPUApps() -> [AppUsage] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["axo", "pid,pcpu,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var seenNames = Set<String>()
        var results: [AppUsage] = []

        let lines = output.split(separator: "\n").dropFirst()
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1])
            else { continue }

            let command = String(parts[2])
            let name = cleanAppName(command)

            // Filter out unwanted system or helper processes
            if name.isEmpty || name.starts(with: "com.") || name == "kernel_task" || name == "(null)" || name == "_" {
                continue
            }

            // Only keep one entry per app name (e.g., only 1 Chrome)
            if seenNames.contains(name) { continue }
            seenNames.insert(name)

            results.append(AppUsage(pid: pid, name: name, cpu: cpu, memMB: 0)) // memMB not used here
        }

        // Sort by CPU usage
        return results.sorted { $0.cpu > $1.cpu }
    }


    private func getTopMemoryApps() -> [AppUsage] {
        let task = Process()
        task.launchPath = "/usr/bin/top"
        task.arguments = ["-l", "1", "-stats", "pid,mem,command", "-n", "50"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do { try task.run() } catch {
            print("❌ Failed to run top: \(error.localizedDescription)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var usageMap: [String: Double] = [:]
        for line in output.split(separator: "\n") {
            if line.contains("(") || line.contains("used") || line.contains("unused") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }

            let memStr = parts[1]
            let memMB: Double
            if memStr.hasSuffix("M"), let num = Double(memStr.dropLast()) {
                memMB = num
            } else if memStr.hasSuffix("K"), let num = Double(memStr.dropLast()) {
                memMB = num / 1024.0
            } else { continue }

            let command = parts.dropFirst(2).joined(separator: " ")
            let name = cleanAppName(command)
            usageMap[name, default: 0] += memMB
        }

        return usageMap
            .map { AppUsage(pid: -1, name: $0.key, cpu: 0, memMB: $0.value) }
            .filter { $0.memMB > 1 }
            .sorted { $0.memMB > $1.memMB }
            .prefix(5)
            .map { $0 }
    }

    func cleanAppName(_ command: String) -> String {
        let url = URL(fileURLWithPath: command)
        let name = url.deletingPathExtension().lastPathComponent

        if name.lowercased().contains("chrome") {
            return "Google Chrome"
        } else if name.lowercased().contains("safari") {
            return "Safari"
        } else if name.lowercased().contains("zoom") {
            return "Zoom"
        }

        return name
    }



    private func getDiskInfo() -> [DiskInfo] {
        var disks: [DiskInfo] = []
        let ignoredNames = ["VM", "Preboot", "Recovery", "Update", "com.apple.TimeMachine.localsnapshots"]
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsInternalKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeIsBrowsableKey
        ]

        guard let volumeURLs = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) else {
            return disks
        }

        for url in volumeURLs {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let name = values.volumeName,
                  let isInternal = values.volumeIsInternal,
                  let isBrowsable = values.volumeIsBrowsable,
                  let total = values.volumeTotalCapacity,
                  let free = values.volumeAvailableCapacity,
                  !ignoredNames.contains(name),
                  isBrowsable else { continue }

            guard let deviceID = getDiskIdentifier(forMountPath: url.path) else { continue }
            let used = total - free
            let isEjectable = isDiskEjectable(deviceID)

            if name == "Macintosh HD" || !isInternal {
                disks.append(DiskInfo(
                    name: name, mountPath: url.path, isEjectable: isEjectable,
                    deviceIdentifier: deviceID, isInternal: isInternal,
                    total: total, used: used
                ))
            }
        }

        return disks
    }

    private func getDiskIdentifier(forMountPath path: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/diskutil"
        task.arguments = ["info", "-plist", path]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        return plist["ParentWholeDisk"] as? String ?? plist["DeviceIdentifier"] as? String
    }

    private func isDiskEjectable(_ deviceID: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/diskutil"
        task.arguments = ["info", "-plist", "/dev/\(deviceID)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return false
        }

        return plist["Ejectable"] as? Bool ?? false
    }

    struct DiskInfo: Identifiable {
        let id = UUID()
        let name: String
        let mountPath: String
        let isEjectable: Bool
        let deviceIdentifier: String
        let isInternal: Bool
        let total: Int
        let used: Int
    }

    struct AppUsage: Identifiable {
        let pid: Int
        let name: String
        let cpu: Double
        let memMB: Double
        var id: Int { pid }
    }
}

