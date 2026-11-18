import UIKit
import QuartzCore

/// Throttled haptics so a burst of kills doesn't turn into a continuous buzz.
@MainActor
final class Haptics {
    var isEnabled = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    private var lastFired: [String: CFTimeInterval] = [:]

    enum Impact { case light, medium, heavy, rigid }

    func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
    }

    func impact(_ kind: Impact, intensity: CGFloat = 1, minInterval: CFTimeInterval = 0.05) {
        guard isEnabled, allow("\(kind)", minInterval) else { return }
        switch kind {
        case .light: light.impactOccurred(intensity: intensity)
        case .medium: medium.impactOccurred(intensity: intensity)
        case .heavy: heavy.impactOccurred(intensity: intensity)
        case .rigid: rigid.impactOccurred(intensity: intensity)
        }
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled, allow("n\(type.rawValue)", 0.25) else { return }
        notification.notificationOccurred(type)
    }

    private func allow(_ key: String, _ interval: CFTimeInterval) -> Bool {
        let now = CACurrentMediaTime()
        if let last = lastFired[key], now - last < interval { return false }
        lastFired[key] = now
        return true
    }
}

/// Single entry point for sound + haptics, respecting the player's settings.
@MainActor
final class FeedbackHub {
    let sound = SoundEngine()
    let haptics = Haptics()
    var screenShake = true

    func apply(_ settings: GameSettings) {
        sound.isEnabled = settings.sound
        haptics.isEnabled = settings.haptics
        screenShake = settings.screenShake
    }
}
