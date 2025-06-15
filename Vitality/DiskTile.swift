import SwiftUI

struct DiskTile: View {
    let disk: SystemMonitor.DiskInfo
    let ejectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive")
                    .foregroundColor(.accentColor)
                Text(disk.name)
                    .font(.headline)
            }

            Text("Path: \(disk.mountPath)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(format: "Used: %.1f GB / Total: %.1f GB",
                        Double(disk.used) / 1_000_000_000,
                        Double(disk.total) / 1_000_000_000))
                .font(.caption2)

            if disk.isEjectable {
                Button("Eject") {
                    ejectAction()
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }
}

