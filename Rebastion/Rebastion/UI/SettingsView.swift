import SwiftUI

/// One switchable preference, shared by the full settings screen and the pause grid.
enum SettingOption: CaseIterable, Identifiable {
    case sound, haptics, screenShake, damageNumbers

    var id: Self { self }

    var title: String {
        switch self {
        case .sound: "Som"
        case .haptics: "Vibração"
        case .screenShake: "Tremor de tela"
        case .damageNumbers: "Números de dano"
        }
    }

    var detail: String {
        switch self {
        case .sound: "Efeitos sonoros do jogo"
        case .haptics: "Resposta tátil nos impactos"
        case .screenShake: "A tela treme nas explosões"
        case .damageNumbers: "Mostra o dano sobre os inimigos"
        }
    }

    var symbol: String {
        switch self {
        case .sound: "speaker.wave.2.fill"
        case .haptics: "iphone.radiowaves.left.and.right"
        case .screenShake: "rectangle.on.rectangle.angled"
        case .damageNumbers: "textformat.123"
        }
    }

    var offSymbol: String {
        switch self {
        case .sound: "speaker.slash.fill"
        default: symbol
        }
    }

    var color: Color {
        switch self {
        case .sound: GamePalette.primary
        case .haptics: GamePalette.violet
        case .screenShake: GamePalette.accent
        case .damageNumbers: GamePalette.coral
        }
    }

    var keyPath: WritableKeyPath<GameSettings, Bool> {
        switch self {
        case .sound: \.sound
        case .haptics: \.haptics
        case .screenShake: \.screenShake
        case .damageNumbers: \.damageNumbers
        }
    }
}

extension GameSession {
    func binding(for option: SettingOption) -> Binding<Bool> {
        Binding(
            get: { self.profile.profile.settings[keyPath: option.keyPath] },
            set: { newValue in
                var settings = self.profile.profile.settings
                settings[keyPath: option.keyPath] = newValue
                self.updateSettings(settings)
            }
        )
    }
}

/// Rounded, filled symbol in the style of the system settings rows.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - Full settings (home screen sheet)

struct SettingsView: View {
    let session: GameSession

    private var profile: PlayerProfile { session.profile.profile }
    private var gameCenter: GameCenterService { session.gameCenter }

    var body: some View {
        List {
            Section {
                GameCenterCard(gameCenter: gameCenter)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Áudio e toque") {
                row(.sound)
                row(.haptics)
            }

            Section("Visual") {
                row(.screenShake)
                row(.damageNumbers)
            }

            Section("Game Center") {
                NavigationLink {
                    AchievementsView(session: session)
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "trophy.fill", color: GamePalette.gold)
                        Text("Conquistas")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text("\(unlockedCount)/\(GameAchievement.allCases.count)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    gameCenter.showLeaderboards()
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "list.number", color: GamePalette.primary)
                        Text("Placares")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(gameCenter.isAuthenticated ? .white : .secondary)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(!gameCenter.isAuthenticated)
            }

            Section("Seu progresso") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    StatCell(title: "Runs", value: "\(profile.totalRuns)", color: GamePalette.primary)
                    StatCell(title: "Melhor onda", value: "\(profile.bestWave)", color: GamePalette.cyan)
                    StatCell(title: "Recorde", value: profile.bestScore.formatted(.number.notation(.compactName)), color: GamePalette.gold)
                    StatCell(title: "Abates", value: profile.totalKills.formatted(.number.notation(.compactName)), color: GamePalette.coral)
                    StatCell(title: "Chefes", value: "\(profile.bossesDefeated)", color: GamePalette.accent)
                    StatCell(title: "Fusões", value: "\(profile.fusionsMade)", color: GamePalette.magenta)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            }

            Section {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Text("RE").foregroundStyle(GamePalette.heroOrange)
                        Text("BASTION").foregroundStyle(GamePalette.heroBlue)
                    }
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    Text("Versão \(Self.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .tint(GamePalette.primary)
    }

    private var unlockedCount: Int {
        GameAchievement.allCases.filter { $0.progress(in: profile) >= 1 }.count
    }

    private func row(_ option: SettingOption) -> some View {
        Toggle(isOn: session.binding(for: option)) {
            HStack(spacing: 12) {
                IconTile(symbol: option.symbol, color: option.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.body.weight(.semibold))
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

struct GameCenterCard: View {
    let gameCenter: GameCenterService

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "gamecontroller.fill", color: gameCenter.isAuthenticated ? GamePalette.lime : .gray, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(gameCenter.playerName ?? "Game Center")
                    .font(.headline)
                Text(gameCenter.isAuthenticated ? "Conectado · conquistas sincronizadas" : "Entre no Game Center nos Ajustes do iPhone para salvar conquistas e placares.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [GamePalette.heroNavy.opacity(0.9), GamePalette.heroBlue.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.1)))
    }
}

// MARK: - Pause quick settings

/// Two-by-two grid of tappable tiles: lit in the option's color when on, dimmed when off.
struct QuickSettingsGrid: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AJUSTES")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(SettingOption.allCases) { option in
                    tile(option)
                }
            }
        }
    }

    private func tile(_ option: SettingOption) -> some View {
        let binding = session.binding(for: option)
        let isOn = binding.wrappedValue
        return Button {
            binding.wrappedValue.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? option.symbol : option.offSymbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isOn ? .black : .secondary)
                    .frame(width: 32, height: 32)
                    .background(isOn ? option.color : .white.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(isOn ? "Ligado" : "Desligado")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isOn ? option.color : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isOn ? option.color.opacity(0.14) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isOn ? option.color.opacity(0.45) : .white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.snappy(duration: 0.2), value: isOn)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(option.title)
        .accessibilityValue(isOn ? "Ligado" : "Desligado")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Achievements

struct AchievementsView: View {
    let session: GameSession

    private var profile: PlayerProfile { session.profile.profile }

    var body: some View {
        let all = GameAchievement.allCases
        let unlocked = all.filter { $0.progress(in: profile) >= 1 }
        List {
            Section {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unlocked.count) de \(all.count)")
                                .font(.title2.weight(.black).monospacedDigit())
                            Text("conquistas desbloqueadas")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("\(unlocked.map(\.points).reduce(0, +))", systemImage: "star.fill")
                            .font(.headline.weight(.heavy).monospacedDigit())
                            .foregroundStyle(GamePalette.gold)
                    }
                    ProgressView(value: Double(unlocked.count), total: Double(all.count))
                        .tint(GamePalette.gold)
                }
                .padding(.vertical, 4)

                if session.gameCenter.isAuthenticated {
                    Button {
                        session.gameCenter.showAchievements()
                    } label: {
                        Label("Abrir no Game Center", systemImage: "gamecontroller.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            Section {
                ForEach(all) { achievement in
                    row(achievement)
                }
            }
        }
        .navigationTitle("Conquistas")
        .tint(GamePalette.primary)
    }

    private func row(_ achievement: GameAchievement) -> some View {
        let progress = achievement.progress(in: profile)
        let done = progress >= 1
        return HStack(spacing: 12) {
            IconTile(symbol: done ? achievement.symbol : "lock.fill", color: done ? achievement.color : .gray.opacity(0.5), size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(done ? .white : .secondary)
                    Spacer()
                    Text("\(achievement.points) pts")
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(done ? GamePalette.gold : .secondary)
                }
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !done {
                    ProgressView(value: progress)
                        .tint(achievement.color)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
