import SwiftUI

// MARK: - Home screen
//
// The home screen is the arena itself (see `GameView`): these views fill the header, arena and
// footer slots while the engine sits in `.menu` and the hero idles with no enemies.

/// Header slot on the home screen: cores where the lives sit in a run, settings where pause sits.
struct MenuHeader: View {
    let cores: Int
    let openSettings: () -> Void

    var body: some View {
        HStack {
            CoreBadge(amount: cores)
                .animation(.snappy, value: cores)

            Spacer(minLength: 0)

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajustes")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
    }
}

/// Logo and start button floating over the empty arena. Everything but the button lets touches
/// through, so the hero can still be dragged around underneath.
struct MenuStage: View {
    let profile: ProfileStore
    let visible: Bool
    let start: () -> Void

    @State private var flicker = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            VStack(spacing: 10) {
                NeonLogo(flicker: flicker, animating: visible)
                if profile.profile.bestScore > 0 {
                    RecordLine(score: profile.profile.bestScore, wave: profile.profile.bestWave)
                }
            }
            .allowsHitTesting(false)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -16)
            .scaleEffect(visible ? 1 : 0.96)

            Spacer(minLength: 24)
            Spacer(minLength: 0)

            StartRunButton(animating: visible, action: start)
                .opacity(visible ? 1 : 0)
                .scaleEffect(visible ? 1 : 1.12)

            // Keeps the button clear of the hero standing on the defense line.
            Spacer()
                .frame(height: 150)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(visible)
        .onAppear { flicker += 1 }
        .onChange(of: visible) { _, isVisible in
            if isVisible { flicker += 1 }
        }
    }
}

/// The title as a neon sign: flickers on whenever the home screen comes back, then breathes.
struct NeonLogo: View {
    let flicker: Int
    let animating: Bool

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            let beat = (sin(context.date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2
            HStack(spacing: 0) {
                letters("RE", color: GamePalette.heroOrange, beat: beat)
                letters("BASTION", color: GamePalette.heroBlue, beat: beat)
            }
            .font(.system(size: 48, weight: .black, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: flicker) { content, opacity in
            content.opacity(opacity)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.0, duration: 0.01)
                LinearKeyframe(0.0, duration: 0.12)
                LinearKeyframe(1.0, duration: 0.04)
                LinearKeyframe(0.15, duration: 0.05)
                LinearKeyframe(0.9, duration: 0.04)
                LinearKeyframe(0.35, duration: 0.07)
                LinearKeyframe(1.0, duration: 0.12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rebastion")
        .accessibilityAddTraits(.isHeader)
    }

    private func letters(_ text: String, color: Color, beat: Double) -> some View {
        Text(text)
            .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .center))
            .shadow(color: color, radius: 2)
            .shadow(color: color.opacity(0.45 + 0.45 * beat), radius: 10 + 14 * beat)
    }
}

struct RecordLine: View {
    let score: Int
    let wave: Int

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(score, format: .number)
            } icon: {
                Image(systemName: "crown.fill")
                    .foregroundStyle(GamePalette.gold)
            }
            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: 3, height: 3)
            Text("ONDA \(wave)")
        }
        .font(.caption.weight(.heavy).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorde \(score) pontos, onda \(wave)")
    }
}

/// The one loud thing on the home screen: a glowing capsule that ripples like the charged ultimate.
struct StartRunButton: View {
    let animating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("COMEÇAR RUN")
            }
            .font(.system(size: 22, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 36)
            .frame(height: 64)
            .background {
                TimelineView(.animation(paused: !animating)) { context in
                    backdrop(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .buttonStyle(StartPressStyle())
        .accessibilityLabel("Começar run")
    }

    private func backdrop(time: Double) -> some View {
        let beat = (sin(time * 3) + 1) / 2
        // A highlight sweeps across every few seconds, then rests.
        let sweep = (time / 2.6).truncatingRemainder(dividingBy: 1) * 2.6 / 0.9
        return ZStack {
            ForEach(0..<2, id: \.self) { i in
                let p = (time * 0.55 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                Capsule()
                    .stroke(GamePalette.primary.opacity((1 - p) * 0.7), lineWidth: 2)
                    .padding(-18 * p)
            }

            Capsule()
                .fill(LinearGradient(colors: [GamePalette.heroBlue, Color(red: 0.12, green: 0.5, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    GeometryReader { proxy in
                        // Taller than the capsule so the tilted band never shows its ends.
                        LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 60, height: proxy.size.height * 3)
                            .offset(y: -proxy.size.height)
                            .rotationEffect(.degrees(20))
                            .offset(x: -90 + (proxy.size.width + 180) * min(1, sweep))
                            .opacity(sweep < 1 ? 1 : 0)
                    }
                    .clipShape(Capsule())
                }
                .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1.5))
                .shadow(color: GamePalette.primary.opacity(0.5 + 0.35 * beat), radius: 14 + 10 * beat)
        }
    }
}

struct StartPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
    }
}

/// Footer slot on the home screen: the starting character, the ultimate and the lab, each
/// flagging when the player can afford something new.
struct MenuFooter: View {
    let profile: ProfileStore
    let open: (MenuSheet) -> Void

    private var hero: HeroCharacter { profile.selectedCharacter }

    private var heroAffordable: Bool {
        HeroCharacter.allCases.contains { !profile.isUnlocked($0) && profile.profile.cores >= $0.cost }
    }

    private var ultimate: UltimateKind { profile.selectedUltimate }

    private var ultimateAffordable: Bool {
        UltimateKind.allCases.contains { !profile.isUnlocked($0) && profile.profile.cores >= $0.cost }
    }

    private var labAffordable: Int {
        LabUpgrade.allCases.filter { upgrade in
            let level = profile.labLevel(upgrade)
            return level < upgrade.maxLevel && profile.profile.cores >= upgrade.cost(forLevel: level)
        }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            MenuCard(symbol: hero.symbol, color: hero.color, caption: "INICIAL", title: hero.title, alert: heroAffordable) {
                open(.heroes)
            }
            MenuCard(symbol: ultimate.symbol, color: ultimate.color, caption: "ULTIMATE", title: ultimate.title, alert: ultimateAffordable) {
                open(.ultimates)
            }
            MenuCard(
                symbol: "flask.fill",
                color: GamePalette.accent,
                caption: "LABORATÓRIO",
                title: labAffordable == 0 ? "Melhorias" : (labAffordable == 1 ? "1 nova" : "\(labAffordable) novas"),
                alert: labAffordable > 0
            ) {
                open(.lab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct MenuCard: View {
    let symbol: String
    let color: Color
    let caption: String
    let title: String
    let alert: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.15), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if alert {
                            Circle()
                                .fill(GamePalette.accent)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(GamePalette.ink, lineWidth: 2))
                                .shadow(color: GamePalette.accent, radius: 4)
                                .phaseAnimator([1.0, 1.25]) { content, scale in
                                    content.scaleEffect(scale)
                                } animation: { _ in .easeInOut(duration: 0.7) }
                                .offset(x: 3, y: -2)
                        }
                    }
                VStack(spacing: 0) {
                    Text(caption)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.footnote.weight(.black))
                        .foregroundStyle(.white)
                        .contentTransition(.interpolate)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption.capitalized): \(title)")
        .accessibilityAddTraits(.isButton)
    }
}

enum MenuSheet: String, Identifiable {
    case lab, heroes, ultimates, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lab: "Laboratório"
        case .heroes: "Tiro inicial"
        case .ultimates: "Ultimates"
        case .settings: "Ajustes"
        }
    }
}

struct MenuSheetView: View {
    let session: GameSession
    let sheet: MenuSheet
    let dismiss: () -> Void

    private var profile: ProfileStore { session.profile }

    var body: some View {
        NavigationStack {
            Group {
                switch sheet {
                case .lab: LabView(profile: profile)
                case .heroes: HeroesView(profile: profile)
                case .ultimates: UltimatesView(profile: profile)
                case .settings: SettingsView(session: session)
                }
            }
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .coreBadgeToolbar(cores: profile.profile.cores, visible: sheet != .settings)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", action: dismiss)
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

private extension View {
    /// Cores in the leading toolbar slot; on iOS 26+ without the shared glass capsule behind it.
    @ViewBuilder
    func coreBadgeToolbar(cores: Int, visible: Bool) -> some View {
        if !visible {
            self
        } else if #available(iOS 26, *) {
            toolbar {
                ToolbarItem(placement: .topBarLeading) { CoreBadge(amount: cores) }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            toolbar {
                ToolbarItem(placement: .topBarLeading) { CoreBadge(amount: cores) }
            }
        }
    }
}

struct LabView: View {
    let profile: ProfileStore

    var body: some View {
        List {
            Section {
                ForEach(LabUpgrade.allCases) { upgrade in
                    let level = profile.labLevel(upgrade)
                    let maxed = level >= upgrade.maxLevel
                    let cost = upgrade.cost(forLevel: level)
                    HStack(spacing: 12) {
                        Image(systemName: upgrade.symbol)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(GamePalette.accent)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(upgrade.title)
                                .font(.headline)
                            Text(upgrade.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                ForEach(0..<upgrade.maxLevel, id: \.self) { i in
                                    Capsule()
                                        .fill(i < level ? GamePalette.accent : .white.opacity(0.15))
                                        .frame(width: 14, height: 4)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            _ = profile.purchase(upgrade)
                        } label: {
                            if maxed {
                                Text("MÁX")
                            } else {
                                Label("\(cost)", systemImage: "hexagon.fill")
                            }
                        }
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .buttonStyle(.bordered)
                        .tint(GamePalette.primary)
                        .disabled(maxed || profile.profile.cores < cost)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Núcleos são ganhos ao final de cada run, de acordo com a onda alcançada, chefes derrotados e pontuação. Os inimigos se adaptam: quanto mais forte o seu equipamento (laboratório, herói e Ultimate), mais duras as runs.")
            }
        }
        .sensoryFeedback(.success, trigger: profile.profile.cores)
    }
}

struct HeroesView: View {
    let profile: ProfileStore

    var body: some View {
        List {
            Section {
                ForEach(HeroCharacter.allCases) { hero in
                    row(hero)
                }
            } footer: {
                Text("Heróis que começam com mais tiros especiais enfrentam inimigos mais duros.")
            }
            Section {
                NavigationLink {
                    CodexView(profile: profile)
                        .navigationTitle("Codex")
                } label: {
                    Label("Tiros e fusões", systemImage: "book.closed.fill")
                        .foregroundStyle(GamePalette.accent)
                }
            }
        }
    }

    private func row(_ hero: HeroCharacter) -> some View {
        let unlocked = profile.isUnlocked(hero)
        let selected = profile.selectedCharacter == hero
        return HStack(spacing: 12) {
            Image(systemName: hero.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(unlocked ? hero.color : .secondary)
                .frame(width: 48, height: 48)
                .background((unlocked ? hero.color : .gray).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(hero.title)
                    .font(.headline)
                Text(hero.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(GamePalette.primary)
            } else if unlocked {
                Button("Usar") { profile.select(hero) }
                    .buttonStyle(.bordered)
                    .tint(hero.color)
            } else {
                Button {
                    if profile.unlock(hero) { profile.select(hero) }
                } label: {
                    Label("\(hero.cost)", systemImage: "hexagon.fill")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                }
                .buttonStyle(.bordered)
                .tint(GamePalette.primary)
                .disabled(profile.profile.cores < hero.cost)
            }
        }
        .padding(.vertical, 4)
    }
}

struct UltimatesView: View {
    let profile: ProfileStore

    var body: some View {
        List {
            Section {
                ForEach(UltimateKind.allCases) { ultimate in
                    row(ultimate)
                }
            } footer: {
                Text("A Ultimate carrega enquanto você derrota inimigos. Quando estiver pronta, deslize o dedo para cima na arena para usar. Ultimates mais fortes deixam os inimigos mais duros.")
            }
        }
    }

    private func row(_ ultimate: UltimateKind) -> some View {
        let unlocked = profile.isUnlocked(ultimate)
        let selected = profile.selectedUltimate == ultimate
        return HStack(spacing: 12) {
            Image(systemName: ultimate.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(unlocked ? ultimate.color : .secondary)
                .frame(width: 48, height: 48)
                .background((unlocked ? ultimate.color : .gray).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ultimate.title)
                        .font(.headline)
                    if ultimate.cost == 0 {
                        Text("PADRÃO")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(ultimate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(GamePalette.primary)
            } else if unlocked {
                Button("Usar") { profile.select(ultimate) }
                    .buttonStyle(.bordered)
                    .tint(ultimate.color)
            } else {
                Button {
                    profile.unlock(ultimate)
                } label: {
                    Label("\(ultimate.cost)", systemImage: "hexagon.fill")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                }
                .buttonStyle(.bordered)
                .tint(GamePalette.primary)
                .disabled(profile.profile.cores < ultimate.cost)
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: selected) { _, now in now }
    }
}

struct CodexView: View {
    let profile: ProfileStore

    var body: some View {
        List {
            Section("Tiros") {
                ForEach(BallType.allCases.filter { !$0.isFusion }) { ball in
                    CodexRow(ball: ball, discovered: profile.isDiscovered(ball))
                }
            }
            Section {
                ForEach(BallType.allCases.filter(\.isFusion)) { ball in
                    CodexRow(ball: ball, discovered: profile.isDiscovered(ball))
                }
            } header: {
                Text("Fusões")
            } footer: {
                Text("Evolua dois tiros ao nível máximo para que a fusão apareça como opção.")
            }
        }
    }
}

struct CodexRow: View {
    let ball: BallType
    let discovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            BallChip(type: ball, level: nil, count: nil)
                .opacity(discovered ? 1 : 0.35)
                .saturation(discovered ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(discovered ? ball.title : "???")
                    .font(.headline)
                if let (a, b) = ball.recipe {
                    Text("\(a.title) + \(b.title)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ball.color)
                }
                Text(discovered ? ball.detail : "Ainda não descoberta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
