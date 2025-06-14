import Foundation
import IOKit
import IOKit.ps

class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var batteryHealth: Double = 0
    @Published var disks: [DiskInfo] = []
    @Published var isActive: Bool = false
    @Published var cpuHistory: [Double] = []

    private var timer: Timer?
    private var previousCPUInfo: host_cpu_load_info_data_t?

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
            let batt = self.getBatteryHealth()
            let disks = self.getDiskInfo()

            DispatchQueue.main.async {
                self.cpuUsage = cpu
                self.memoryUsage = mem
                self.batteryHealth = batt
                self.disks = disks

                // ✅ Append to history
                self.cpuHistory.append(cpu)
                if self.cpuHistory.count > 60 {
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
        var count = mach_msg_type_number_t(UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size))

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)

        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        return total > 0 ? used / total : 0
    }


    private func getBatteryHealth() -> Double {
        let task = Process()
        task.launchPath = "/usr/sbin/ioreg"
        task.arguments = ["-rn", "AppleSmartBattery"]

        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return 0 }

        var maxCap = 1
        var designCap = 1

        for line in output.split(separator: "\n") {
            if line.contains("MaxCapacity") {
                maxCap = Int(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            }
            if line.contains("DesignCapacity") {
                designCap = Int(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1
            }
        }

        return min(Double(maxCap) / Double(designCap), 1.0)
    }

    private func getDiskInfo() -> [DiskInfo] {
        var disks: [DiskInfo] = []

        let ignoreNames = ["Preboot", "VM", "Recovery", "Update", "com.apple.TimeMachine.localsnapshots"]

        let volumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsInternalKey
            ],
            options: []
        ) ?? []

        for url in volumeURLs {
            guard let values = try? url.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeIsInternalKey
            ]),
            let name = values.volumeName,
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacity,
            let isInternal = values.volumeIsInternal else {
                continue
            }

            if ignoreNames.contains(name) || name.contains("Simulator") {
                continue
            }

            guard let deviceID = getDiskIdentifier(forMountPath: url.path) else { continue }

            let isEjectable = isDiskEjectable(deviceID)
            let used = total - available

            if name == "Macintosh HD" || !isInternal {
                disks.append(DiskInfo(
                    name: name,
                    mountPath: url.path,
                    isEjectable: isEjectable,
                    deviceIdentifier: deviceID,
                    isInternal: isInternal,
                    total: total,
                    used: used
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

        do {
            try task.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        // Prefer ejectable parent disk (e.g., disk3 not disk3s1)
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
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return false
        }

        return (plist["Ejectable"] as? Bool) ?? false
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
}

