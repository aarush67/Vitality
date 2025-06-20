import SwiftUI
import AppKit

struct MainView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var settings: SettingsModel
    @State private var tileOrder: [TileType] = TileType.defaultOrder
    @GestureState private var isDragging = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(tileOrder, id: \.self) { tile in
                    tileView(for: tile)
                        .background(DragHandle())
                        .onDrag {
                            HapticManager.shared.simple(.alignment)
                            return NSItemProvider(object: tile.rawValue as NSString)
                        }
                        .onDrop(of: [.text], delegate: TileDropDelegate(item: tile, items: $tileOrder))
                        .transition(.scale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: tileOrder)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(
            VisualEffectBlur(material: .underWindowBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
        .frame(minWidth: 440, minHeight: 640)
    }

    @ViewBuilder
    private func tileView(for tile: TileType) -> some View {
        switch tile {
        case .cpu where settings.showCPU:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "CPU")
                    CircularProgress(title: "CPU Usage", value: monitor.cpuUsage)
                    LineChart(values: monitor.cpuHistory)
                }
            }

        case .memory where settings.showMemory:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "Memory")
                    MetricTile(title: "Memory", value: monitor.memoryUsage, symbol: "memorychip")
                }
            }

        case .battery where settings.showBattery:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "Battery")
                    BatteryTile(health: monitor.batteryHealth, cycles: monitor.batteryCycles)
                }
            }

        case .uptime where settings.showUptime:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "Uptime")
                    UptimeTile(uptime: monitor.uptime)
                }
            }

        case .thermal where settings.showThermal:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "Thermal")
                    ThermalTile(state: monitor.thermalState)
                }
            }

        case .topCPU where settings.showTopApps:
            TopCPUAppsTile(monitor: monitor)

        case .topMemory where settings.showTopApps:
            TopMemoryAppsTile(monitor: monitor)

        case .network where settings.showNetwork:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "Network")
                    NetworkTile(rx: monitor.networkRx, tx: monitor.networkTx)
                }
            }

        case .disks where settings.showDisks:
            TileWrapper {
                VStack(spacing: 8) {
                    SectionHeader(title: "Disks")
                    ForEach(monitor.disks) { disk in
                        DiskTile(disk: disk) {
                            eject(disk.mountPath)
                            HapticManager.shared.simple(.levelChange)
                        }
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    private func eject(_ path: String) {
        let url = URL(fileURLWithPath: path)
        try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}

enum TileType: String, CaseIterable, Hashable {
    case cpu, memory, battery, uptime, thermal, topCPU, topMemory, network, disks

    static let defaultOrder: [TileType] = [
        .cpu, .memory, .battery, .uptime,
        .thermal, .topCPU, .topMemory, .network, .disks
    ]
}

struct TileDropDelegate: DropDelegate {
    let item: TileType
    @Binding var items: [TileType]

    func performDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadItem(forTypeIdentifier: "public.text", options: nil) { data, _ in
            guard
                let data = data as? Data,
                let raw = String(data: data, encoding: .utf8),
                let dragged = TileType(rawValue: raw),
                dragged != item,
                let from = items.firstIndex(of: dragged),
                let to = items.firstIndex(of: item)
            else { return }

            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    HapticManager.shared.simple(.alignment)
                }
            }
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct TileWrapper<Content: View>: View {
    var content: () -> Content
    @State private var isHovering = false

    var body: some View {
        content()
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 6)
            )
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct DragHandle: View {
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CircularProgress: View {
    let title: String
    let value: Double
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(min(value, 1)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption2)
            }
            .frame(width: 80, height: 80)
            Text(title).font(.caption2)
        }
    }
}

struct LineChart: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard !values.isEmpty else { return }
                let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
                let maxY = values.max() ?? 1
                for (idx, val) in values.enumerated() {
                    let x = CGFloat(idx) * stepX
                    let y = (1 - CGFloat(val / maxY)) * geo.size.height
                    if idx == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)
        }
        .frame(height: 60)
    }
}

struct MetricTile: View {
    let title: String
    let value: Double
    let symbol: String
    var body: some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: symbol)
                .font(.caption)
            ProgressView(value: value)
            Text(String(format: "%.0f%%", value * 100))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct BatteryTile: View {
    let health: Double
    let cycles: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MetricTile(title: "Health", value: health, symbol: "battery.100")
            Text("Cycles: \(cycles)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct UptimeTile: View {
    let uptime: String
    var body: some View {
        Label("Uptime: \(uptime)", systemImage: "clock")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

struct ThermalTile: View {
    let state: ProcessInfo.ThermalState
    var body: some View {
        Label(state.descriptionText, systemImage: "thermometer")
            .font(.caption2)
            .foregroundColor(state.colorValue)
    }
}

extension ProcessInfo.ThermalState {
    var descriptionText: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var colorValue: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}

struct TopAppsTile: View {
    let apps: [SystemMonitor.AppUsage]
    let isMemory: Bool
    let monitor: SystemMonitor  // passed explicitly now

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(apps.prefix(3)), id: \.id) { app in
                TopAppRow(app: app, isMemory: isMemory, monitor: monitor)
            }
        }
    }
}


@ViewBuilder
private func TopAppRow(app: SystemMonitor.AppUsage, isMemory: Bool, monitor: SystemMonitor) -> some View {
    let progress: Double = isMemory ? app.memMB / 8000 : app.cpu / 100
    let label: String = isMemory ? "\(Int(app.memMB)) MB" : String(format: "%.1f%%", app.cpu)

    HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.name)
                .font(.caption2)
            ProgressView(value: progress)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }

        Spacer()

        if !isMemory && app.pid > 0 {
            Button {
                monitor.killProcess(pid: app.pid)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Force quit \(app.name)")
        }
    }
}






struct TopCPUAppsTile: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        let apps = Array(monitor.topCPUApps.prefix(3))

        return TileWrapper {
            VStack(spacing: 8) {
                SectionHeader(title: "Top CPU Apps")
                TopAppsTile(apps: apps, isMemory: false, monitor: monitor)
            }
        }
    }
}



struct TopMemoryAppsTile: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        let apps = Array(monitor.topMemoryApps.prefix(3))

        return TileWrapper {
            VStack(spacing: 8) {
                SectionHeader(title: "Top Memory Apps")
                TopAppsTile(apps: apps, isMemory: true, monitor: monitor)
            }
        }
    }
}



struct NetworkTile: View {
    let rx: Double
    let tx: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Download", systemImage: "arrow.down")
            ProgressView(value: min(rx / 10_000_000, 1.0))
            Text(String(format: "%.2f MB/s", rx / 1_000_000))
                .font(.caption2)
                .foregroundColor(.secondary)

            Label("Upload", systemImage: "arrow.up")
            ProgressView(value: min(tx / 10_000_000, 1.0))
            Text(String(format: "%.2f MB/s", tx / 1_000_000))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

