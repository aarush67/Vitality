import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var didAppear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                InfoTile(title: "CPU Usage", value: monitor.cpuUsage, symbol: "cpu")
                UsageGraph(data: monitor.cpuHistory)

                InfoTile(title: "Memory Usage", value: monitor.memoryUsage, symbol: "memorychip")
                InfoTile(title: "Battery Health", value: monitor.batteryHealth, symbol: "battery.100")

                ForEach(monitor.disks) { disk in
                    VStack(alignment: .leading) {
                        HStack {
                            Label(disk.name, systemImage: "externaldrive")
                            Spacer()
                            if disk.isEjectable {
                                Button(action: {
                                    print("🔘 Eject clicked for: \(disk.deviceIdentifier)")
                                    ejectVolume(at: disk.mountPath)
                                }) {
                                    Image(systemName: "eject")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ProgressView(value: clamped(disk.used, max: disk.total))
                            .progressViewStyle(.linear)

                        Text("\(disk.used / 1_000_000_000) GB used of \(disk.total / 1_000_000_000) GB")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
            }
            .padding()
            .opacity(didAppear ? 1 : 0)
            .onAppear {
                withAnimation(.easeIn(duration: 0.25)) {
                    didAppear = true
                }
            }
        }
        .frame(width: 360)
    }

    func clamped(_ used: Int, max: Int) -> Double {
        guard max > 0 else { return 0 }
        return min(Double(used) / Double(max), 1.0)
    }

    func ejectVolume(at mountPath: String) {
        let url = URL(fileURLWithPath: mountPath)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            print("✅ Ejected via NSWorkspace: \(mountPath)")
        } catch {
            print("❌ Eject failed: \(error.localizedDescription)")
        }
    }
}

struct InfoTile: View {
    let title: String
    let value: Double
    let symbol: String

    var body: some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: symbol)
            ProgressView(value: clampedValue)
                .progressViewStyle(LinearProgressViewStyle(tint: tintColor))
            Text(String(format: "%.0f%%", value * 100))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var tintColor: Color {
        switch clampedValue {
        case ..<0.6: return .green
        case 0.6..<0.85: return .yellow
        default: return .red
        }
    }
}

struct UsageGraph: View {
    let data: [Double] // 0.0 to 1.0 values

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(data.indices, id: \.self) { i in
                Capsule()
                    .fill(color(for: data[i]))
                    .frame(width: 4, height: CGFloat(data[i]) * 40)
            }
        }
        .padding(.vertical, 4)
    }

    private func color(for value: Double) -> Color {
        switch value {
        case ..<0.6: return .green
        case 0.6..<0.85: return .yellow
        default: return .red
        }
    }
}

