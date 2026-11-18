import SwiftUI
import UIKit

/// A color defined once and handed to SwiftUI (`color`) and SpriteKit (`ui`) alike.
struct Tone {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(red: red, green: green, blue: blue) }
    var ui: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
}

/// Every color in the game. The brand is the hero's own colors, sampled from its sprite: all
/// chrome (title, buttons, HUD, aim, level-up) is built from those. The spectrum below them
/// stays for gameplay identity only: ball elements, enemy kinds, rarities.
enum Tones {
    static let background = Tone(red: 0.025, green: 0.035, blue: 0.07)
    static let arenaTop = Tone(red: 0.055, green: 0.075, blue: 0.14)
    static let arenaBottom = Tone(red: 0.025, green: 0.03, blue: 0.075)
    static let ink = Tone(red: 0.018, green: 0.025, blue: 0.075)

    // Hero brand.
    /// The glow of the eyes and the arm cannon.
    static let heroBlue = Tone(red: 0.1, green: 0.82, blue: 1)
    /// The armor joints.
    static let heroOrange = Tone(red: 1, green: 0.52, blue: 0.08)
    /// The armor plates.
    static let heroNavy = Tone(red: 0.09, green: 0.19, blue: 0.47)

    // Gameplay spectrum and semantics.
    static let lime = Tone(red: 0.69, green: 1, blue: 0.2)
    static let cyan = Tone(red: 0.2, green: 0.9, blue: 1)
    static let violet = Tone(red: 0.55, green: 0.35, blue: 1)
    static let coral = Tone(red: 1, green: 0.3, blue: 0.38)
    static let magenta = Tone(red: 1, green: 0.3, blue: 0.85)
    static let gold = Tone(red: 1, green: 0.82, blue: 0.25)
}

enum GamePalette {
    static let background = Tones.background.color
    static let arenaTop = Tones.arenaTop.color
    static let arenaBottom = Tones.arenaBottom.color
    static let ink = Tones.ink.color

    static let heroBlue = Tones.heroBlue.color
    static let heroOrange = Tones.heroOrange.color
    static let heroNavy = Tones.heroNavy.color
    /// Main accent: primary buttons, progress, selection, aim.
    static let primary = heroBlue
    /// Second accent: whatever has to pop against the blue.
    static let accent = heroOrange

    static let lime = Tones.lime.color
    static let cyan = Tones.cyan.color
    static let violet = Tones.violet.color
    static let coral = Tones.coral.color
    static let magenta = Tones.magenta.color
    static let gold = Tones.gold.color
}

/// UIKit mirror of the palette for SpriteKit nodes.
enum Neon {
    static let background = Tones.background.ui
    static let arenaTop = Tones.arenaTop.ui
    static let arenaBottom = Tones.arenaBottom.ui

    static let heroBlue = Tones.heroBlue.ui
    static let heroOrange = Tones.heroOrange.ui
    static let heroNavy = Tones.heroNavy.ui
    static let primary = heroBlue
    static let accent = heroOrange

    static let lime = Tones.lime.ui
    static let cyan = Tones.cyan.ui
    static let violet = Tones.violet.ui
    static let coral = Tones.coral.ui
    static let magenta = Tones.magenta.ui
    static let gold = Tones.gold.ui
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = GamePalette.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: tint.opacity(0.45), radius: configuration.isPressed ? 4 : 14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

extension View {
    func modalCard() -> some View {
        self
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12)))
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.72))
    }
}

struct CoreBadge: View {
    let amount: Int

    var body: some View {
        // Not a Label: toolbars render labels icon-only, and the amount must always show.
        HStack(spacing: 6) {
            Image(systemName: "hexagon.fill")
            Text(amount, format: .number)
        }
        .font(.subheadline.weight(.heavy).monospacedDigit())
        .foregroundStyle(GamePalette.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(GamePalette.primary.opacity(0.12), in: Capsule())
        .contentTransition(.numericText())
        .fixedSize()
    }
}
