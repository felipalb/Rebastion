import SwiftUI

struct HUDHeader: View {
    let engine: GameEngine

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 3) {
                ScoreView(score: engine.score, combo: engine.combo)
                // Fixed-height slot so the combo appearing never resizes the arena.
                ZStack {
                    if engine.combo >= 2 {
                        ComboChip(combo: engine.combo, multiplier: engine.comboMultiplier)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(height: 24)
                .animation(.spring(duration: 0.25, bounce: 0.5), value: engine.combo >= 2)
            }

            HStack(alignment: .center) {
                LivesView(lives: engine.lives)

                Spacer(minLength: 0)

                Button {
                    engine.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pausar")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
    }
}

/// Big glowing score. Pops on every gain and glows hotter (combo color) while a combo runs.
struct ScoreView: View {
    let score: Int
    let combo: Int

    private var glow: Color { combo >= 2 ? ComboChip.color(for: combo) : GamePalette.gold }

    var body: some View {
        Text(score, format: .number)
            .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(LinearGradient(colors: [.white, GamePalette.gold], startPoint: .top, endPoint: .bottom))
            .shadow(color: glow.opacity(0.75), radius: combo >= 2 ? 10 : 6)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: 190)
            .contentTransition(.numericText(value: Double(score)))
            .animation(.snappy(duration: 0.2), value: score)
            .keyframeAnimator(initialValue: 1.0, trigger: score) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.12, duration: 0.08)
                    SpringKeyframe(1.0, duration: 0.2)
                }
            }
            .accessibilityLabel("Pontuação")
            .accessibilityValue("\(score)")
    }
}

/// One heart with a "3x" life count badged on its bottom-right corner, sized to read at a glance.
/// Shakes and flashes white on damage, bounces green on heal, and throbs when one life is left.
struct LivesView: View {
    let lives: Int

    @State private var hurtTrigger = 0
    @State private var healTrigger = 0
    @State private var flash: Color?

    private var critical: Bool { lives == 1 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "heart.fill")
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(flash ?? GamePalette.coral)
                .shadow(color: GamePalette.coral.opacity(0.9), radius: 3)
                .symbolEffect(.bounce, value: healTrigger)
                .symbolEffect(.pulse, isActive: critical)
                .frame(width: 38, height: 38)
                .background(GamePalette.coral.opacity(critical ? 0.3 : 0.16), in: Circle())
                .overlay(Circle().stroke((flash ?? GamePalette.coral).opacity(critical ? 1 : 0.6), lineWidth: critical ? 2 : 1.5))
                .shadow(color: GamePalette.coral.opacity(critical ? 0.7 : 0.35), radius: critical ? 10 : 6)
            Text("\(lives)x")
                .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(GamePalette.ink)
                .contentTransition(.numericText(value: Double(lives)))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(flash ?? .white, in: Capsule())
                .overlay(Capsule().stroke(GamePalette.ink, lineWidth: 1.5))
                .offset(x: 10, y: 4)
        }
        .phaseAnimator([1.0, 1.06], trigger: critical) { content, scale in
            content.scaleEffect(critical ? scale : 1)
        } animation: { _ in .easeInOut(duration: 0.45) }
        .keyframeAnimator(initialValue: 0.0, trigger: hurtTrigger) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-7, duration: 0.05)
                LinearKeyframe(7, duration: 0.07)
                LinearKeyframe(-5, duration: 0.07)
                LinearKeyframe(4, duration: 0.07)
                LinearKeyframe(0, duration: 0.06)
            }
        }
        .animation(.snappy, value: lives)
        .onChange(of: lives) { old, new in
            guard new != old else { return }
            if new < old { hurtTrigger += 1 } else { healTrigger += 1 }
            withAnimation(.easeOut(duration: 0.08)) { flash = new < old ? .white : GamePalette.lime }
            withAnimation(.easeIn(duration: 0.45).delay(0.15)) { flash = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vidas")
        .accessibilityValue("\(lives)")
    }
}

struct ComboChip: View {
    let combo: Int
    let multiplier: Double

    static func color(for combo: Int) -> Color {
        switch combo {
        case ..<10: GamePalette.primary
        case ..<25: GamePalette.gold
        case ..<50: GamePalette.accent
        case ..<100: GamePalette.coral
        default: GamePalette.magenta
        }
    }

    private var color: Color { Self.color(for: combo) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .symbolEffect(.bounce, value: combo)
            Text("COMBO \(combo)")
                .contentTransition(.numericText(value: Double(combo)))
            Text("x\(multiplier, specifier: "%.1f")")
                .padding(.horizontal, 5)
                .background(.black.opacity(0.85), in: Capsule())
                .foregroundStyle(color)
        }
        .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(color, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: color.opacity(0.9), radius: 8)
        .keyframeAnimator(initialValue: 1.0, trigger: combo) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.15, duration: 0.07)
                SpringKeyframe(1.0, duration: 0.2)
            }
        }
        .animation(.snappy(duration: 0.15), value: combo)
    }
}

struct BossBar: View {
    let ratio: Double
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(GamePalette.coral)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: [GamePalette.coral, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * ratio)
                        .shadow(color: GamePalette.coral, radius: 6)
                    ForEach([0.33, 0.66], id: \.self) { mark in
                        Rectangle()
                            .fill(.black.opacity(0.6))
                            .frame(width: 2)
                            .offset(x: proxy.size.width * mark)
                    }
                }
            }
            .frame(height: 10)
            .animation(.easeOut(duration: 0.15), value: ratio)
        }
        .padding(.horizontal, 40)
    }
}

struct BannerView: View {
    let banner: Banner

    private var color: Color {
        switch banner.style {
        case .wave: GamePalette.primary
        case .boss: GamePalette.coral
        case .combo: GamePalette.gold
        case .fusion: GamePalette.accent
        case .clear: GamePalette.primary
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(banner.title)
                .font(.system(size: banner.style == .combo ? 30 : 34, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.9), radius: 12)
            if let subtitle = banner.subtitle {
                Text(subtitle)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 22)
        .multilineTextAlignment(.center)
    }
}

struct HUDFooter: View {
    let engine: GameEngine

    private var progress: Double {
        min(1, Double(engine.experience) / Double(max(1, engine.experienceNeeded)))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("NV \(engine.level)")
                    .font(.caption.weight(.black).monospacedDigit())
                    .foregroundStyle(GamePalette.primary)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(colors: [GamePalette.primary, GamePalette.heroBlue.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * progress)
                            .shadow(color: GamePalette.primary.opacity(0.8), radius: 4)
                    }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.2), value: progress)
            }

            // No ultimate button: a one-handed thumb covers this corner. The ultimate fires with
            // an upward swipe, and the hero's aura and the glowing edges show when it's ready.
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    BallChip(type: .basic, level: nil, count: engine.basicBallCount)
                    ForEach(engine.ownedSpecialBalls, id: \.type) { entry in
                        BallChip(type: entry.type, level: entry.type.isFusion ? nil : entry.level, count: nil)
                    }
                    ForEach(0..<max(0, engine.maxSlots - engine.specialSlotsUsed), id: \.self) { _ in
                        Circle()
                            .strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: 34, height: 34)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct BallChip: View {
    let type: BallType
    let level: Int?
    let count: Int?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: type.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(type.color)
                .frame(width: 34, height: 34)
                .background(type.color.opacity(0.16), in: Circle())
                .overlay(Circle().stroke(type.color.opacity(type.isFusion ? 1 : 0.5), lineWidth: type.isFusion ? 2 : 1))
                .shadow(color: type.isFusion ? type.color : .clear, radius: 5)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .black).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .background(.white, in: Capsule())
            } else if let level {
                HStack(spacing: 1) {
                    ForEach(0..<BallType.maxLevel, id: \.self) { i in
                        Circle()
                            .fill(i < level ? type.color : .white.opacity(0.2))
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(2)
                .background(.black.opacity(0.7), in: Capsule())
                .offset(x: -6, y: 2)
            }
        }
        .accessibilityLabel(type.title)
    }
}

/// Spells out the swipe while the ultimate is charged. First run only; the orange light
/// climbing the screen edges carries the reminder on every run.
struct UltimateReadyHint: View {
    let kind: UltimateKind

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
            Text("DESLIZE PARA CIMA")
        }
        .font(.system(size: 12, weight: .black))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GamePalette.ink.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(kind.color, lineWidth: 1.5))
        .foregroundStyle(kind.color)
        .shadow(color: kind.color.opacity(0.6), radius: 8)
        .accessibilityHidden(true)
    }
}

/// Red pulsing edges over the arena when the player is down to their last life.
struct LastLifeVignette: View {
    var body: some View {
        Rectangle()
            .fill(RadialGradient(colors: [.clear, .clear, GamePalette.coral.opacity(0.55)], center: .center, startRadius: 0, endRadius: 420))
            .phaseAnimator([0.35, 0.9]) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.6) }
    }
}

/// The screen edges glow in the hero's orange while the ultimate is charged, with a band of
/// light sweeping from the bottom edge up the sides to the top: the same upward swipe that
/// fires it. Hard to forget even with eyes on the fight.
struct UltimateReadyEdges: View {
    private let color = GamePalette.heroOrange
    private let depth: CGFloat = 28
    /// Seconds for the band to climb the screen.
    private let sweep = 0.9
    /// Half-height of the band, as a fraction of the screen.
    private let band = 0.28
    /// Glow left on the edges between passes.
    private let rest = 0.3

    var body: some View {
        TimelineView(.animation) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: sweep) / sweep
            // 0 is the top of the screen, 1 the bottom; the band starts below the screen and exits above it.
            let center = 1 + band - progress * (1 + 2 * band)
            edges.mask(sweepMask(center: center))
        }
    }

    private var edges: some View {
        ZStack {
            edge(.top)
            edge(.bottom)
            edge(.leading)
            edge(.trailing)
            Rectangle().strokeBorder(color.opacity(0.9), lineWidth: 2.5)
        }
    }

    private func sweepMask(center: Double) -> some View {
        let clamp = { (x: Double) in min(1, max(0, x)) }
        return LinearGradient(stops: [
            .init(color: .white.opacity(rest), location: 0),
            .init(color: .white.opacity(rest), location: clamp(center - band)),
            .init(color: .white, location: clamp(center)),
            .init(color: .white.opacity(rest), location: clamp(center + band)),
            .init(color: .white.opacity(rest), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func edge(_ edge: Edge) -> some View {
        let start: UnitPoint, end: UnitPoint, alignment: Alignment
        switch edge {
        case .top: (start, end, alignment) = (.top, .bottom, .top)
        case .bottom: (start, end, alignment) = (.bottom, .top, .bottom)
        case .leading: (start, end, alignment) = (.leading, .trailing, .leading)
        case .trailing: (start, end, alignment) = (.trailing, .leading, .trailing)
        }
        let horizontal = edge == .top || edge == .bottom
        return LinearGradient(colors: [color.opacity(0.7), color.opacity(0)], startPoint: start, endPoint: end)
            .frame(width: horizontal ? nil : depth, height: horizontal ? depth : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}
