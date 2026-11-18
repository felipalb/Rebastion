import SwiftUI

/// The level-up choice. It opens with a burst of sparkles, then slides up
/// as a bottom sheet over a barely tinted arena, so it reads as a reward and never as a loss.
struct UpgradeView: View {
    let engine: GameEngine

    @State private var appeared = false

    private var isChest: Bool { engine.upgradeContext == .bossChest }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                header
                    .overlay {
                        SparkleBurst(colors: isChest ? [GamePalette.gold, .white] : [GamePalette.primary, GamePalette.accent, .white])
                    }
                ForEach(Array(engine.upgradeChoices.enumerated()), id: \.element.id) { index, option in
                    UpgradeCard(option: option, detail: detail(for: option), levelText: levelText(for: option)) {
                        engine.choose(option)
                    }
                    .disabled(engine.upgradeLockRemaining > 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.35, bounce: 0.3).delay(Double(index) * 0.06), value: engine.upgradeChoices)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: 460)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                            .fill(LinearGradient(colors: [accent.opacity(0.22), GamePalette.heroNavy.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                            .stroke(accent.opacity(0.7), lineWidth: 1.5)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
            .offset(y: appeared ? 0 : 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Keep the arena bright: a light glow in the accent color rising from the sheet,
            // never the dark fade of the game-over screen.
            LinearGradient(colors: [accent.opacity(0.08), accent.opacity(0.18), GamePalette.heroNavy.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { appeared = true }
        }
    }

    private var accent: Color { isChest ? GamePalette.gold : GamePalette.primary }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isChest ? "shippingbox.fill" : "arrow.up.circle.fill")
                Text(isChest ? "RECOMPENSA" : "NÍVEL \(engine.level)")
                    .contentTransition(.numericText(value: Double(engine.level)))
            }
            .font(.caption.weight(.black))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(accent, in: Capsule())

            Text(isChest ? "BAÚ DO CHEFE" : "SUBIU DE NÍVEL!")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(isChest
                    ? AnyShapeStyle(GamePalette.gold)
                    : AnyShapeStyle(LinearGradient(colors: [GamePalette.primary, GamePalette.accent], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: accent.opacity(0.5), radius: 8)
                .scaleEffect(appeared ? 1 : 0.5)
                .animation(.spring(duration: 0.5, bounce: 0.55).delay(0.1), value: appeared)
            Text(isChest ? "Recompensa rara garantida" : "Escolha 1 melhoria para fortalecer o herói")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func detail(for option: UpgradeOption) -> String {
        switch option {
        case .passive(let passive): passive.detail
        case .newBall(let type), .levelBall(let type), .fuse(let type): type.detail
        }
    }

    private func levelText(for option: UpgradeOption) -> String? {
        switch option {
        case .passive(let passive):
            let current = engine.passiveLevels[passive] ?? 0
            return passive == .fortify ? nil : "Nv \(current) → \(current + 1)"
        case .newBall:
            return "Novo"
        case .levelBall(let type):
            let current = engine.ballLevels[type] ?? 1
            return "Nv \(current) → \(current + 1)"
        case .fuse(let type):
            guard let (a, b) = type.recipe else { return nil }
            return "\(a.title) + \(b.title)"
        }
    }
}

/// A one-shot ring of stars and sparkles thrown out from the level-up title.
private struct SparkleBurst: View {
    let colors: [Color]

    @State private var fired = false

    private static let count = 14

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { i in
                let angle = Double(i) / Double(Self.count) * 2 * .pi
                let reach: CGFloat = i.isMultiple(of: 2) ? 160 : 115
                Image(systemName: i.isMultiple(of: 3) ? "star.fill" : "sparkle")
                    .font(.system(size: i.isMultiple(of: 2) ? 16 : 11, weight: .black))
                    .foregroundStyle(colors[i % colors.count])
                    .scaleEffect(fired ? 1 : 0.2)
                    .offset(x: fired ? cos(angle) * reach : 0, y: fired ? sin(angle) * reach * 0.6 : 0)
                    .opacity(fired ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 1)) { fired = true }
        }
    }
}

struct UpgradeCard: View {
    let option: UpgradeOption
    let detail: String
    let levelText: String?
    let action: () -> Void

    @State private var shimmer = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: option.symbol)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(option.color)
                    .frame(width: 54, height: 54)
                    .background(option.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.tag)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(option.rarity.color)
                        if option.rarity != .common {
                            Text(option.rarity.label)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .background(option.rarity.color, in: Capsule())
                        }
                    }
                    Text(option.title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let levelText {
                        Text(levelText)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(option.color)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderStyle, lineWidth: option.rarity >= .legendary ? 2 : 1)
            }
            .shadow(color: option.rarity >= .legendary ? option.rarity.color.opacity(shimmer ? 0.7 : 0.25) : .clear, radius: 14)
        }
        .buttonStyle(CardPressStyle())
        .onAppear {
            guard option.rarity >= .legendary else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { shimmer = true }
        }
    }

    private var borderStyle: AnyShapeStyle {
        if option.rarity == .fusion {
            return AnyShapeStyle(AngularGradient(colors: [GamePalette.magenta, GamePalette.cyan, GamePalette.gold, GamePalette.magenta], center: .center))
        }
        return AnyShapeStyle(option.rarity == .common ? Color.white.opacity(0.12) : option.rarity.color.opacity(0.8))
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}
