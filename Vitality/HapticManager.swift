import AppKit
import CoreHaptics
import SwiftUI

final class HapticManager: ObservableObject {
    static let shared = HapticManager()

    @AppStorage("hapticsEnabled") var hapticsEnabled: Bool = true

    private var engine: CHHapticEngine?

    private init() {}

    func prepareAdvanced() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
        }
    }

    func simple(_ style: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard hapticsEnabled else { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(style, performanceTime: .now)
        }
    }

    func playAdvanced() {
        guard hapticsEnabled else { return }

        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [sharpness, intensity],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            print("❌ Failed to play Core Haptic pattern: \(error.localizedDescription)")
        }
    }
}

