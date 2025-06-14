import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack {
            Text("Vitality Settings")
                .font(.title2)
            Text("No configurable settings yet — but coming soon!")
                .font(.caption)
                .padding(.top, 5)
        }
        .frame(width: 300, height: 100)
        .padding()
    }
}

