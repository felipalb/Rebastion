import SwiftUI

/// The achievement catalog. Every achievement is derived from the saved profile alone, so
/// progress can be recomputed (and re-synced to Game Center) at any time.
/// The IDs must match the achievements registered for the app in App Store Connect.
enum GameAchievement: String, CaseIterable, Identifiable {
    case firstRun = "bonk.first_run"
    case kills100 = "bonk.kills_100"
    case kills1000 = "bonk.kills_1000"
    case kills10000 = "bonk.kills_10000"
    case firstBoss = "bonk.first_boss"
    case bosses10 = "bonk.bosses_10"
    case wave10 = "bonk.wave_10"
    case wave20 = "bonk.wave_20"
    case wave30 = "bonk.wave_30"
    case firstFusion = "bonk.first_fusion"
    case fusions25 = "bonk.fusions_25"
    case combo50 = "bonk.combo_50"
    case combo100 = "bonk.combo_100"
    case labUpgrades10 = "bonk.lab_10"
    case allHeroes = "bonk.all_heroes"
    case allUltimates = "bonk.all_ultimates"
    case allShots = "bonk.all_shots"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstRun: "Primeira Defesa"
        case .kills100: "Caçador"
        case .kills1000: "Exterminador"
        case .kills10000: "Lenda de Rebastion"
        case .firstBoss: "Chefe Abatido"
        case .bosses10: "Matador de Titãs"
        case .wave10: "Resistente"
        case .wave20: "Inabalável"
        case .wave30: "Imparável"
        case .firstFusion: "Alquimista"
        case .fusions25: "Mestre das Fusões"
        case .combo50: "Em Chamas"
        case .combo100: "Combo Insano"
        case .labUpgrades10: "Cientista"
        case .allHeroes: "Esquadrão Completo"
        case .allUltimates: "Arsenal Supremo"
        case .allShots: "Colecionador"
        }
    }

    var detail: String {
        switch self {
        case .firstRun: "Termine sua primeira run."
        case .kills100: "Derrote 100 invasores no total."
        case .kills1000: "Derrote 1.000 invasores no total."
        case .kills10000: "Derrote 10.000 invasores no total."
        case .firstBoss: "Derrote seu primeiro chefe."
        case .bosses10: "Derrote 10 chefes no total."
        case .wave10: "Alcance a onda 10."
        case .wave20: "Alcance a onda 20."
        case .wave30: "Alcance a onda 30."
        case .firstFusion: "Crie sua primeira fusão."
        case .fusions25: "Crie 25 fusões no total."
        case .combo50: "Faça um combo de 50 em uma run."
        case .combo100: "Faça um combo de 100 em uma run."
        case .labUpgrades10: "Compre 10 melhorias no Laboratório."
        case .allHeroes: "Desbloqueie todos os heróis."
        case .allUltimates: "Desbloqueie todas as ultimates."
        case .allShots: "Descubra todos os tiros e fusões."
        }
    }

    var points: Int {
        switch self {
        case .firstRun: 10
        case .kills100: 15
        case .kills1000: 30
        case .kills10000: 75
        case .firstBoss: 20
        case .bosses10: 40
        case .wave10: 20
        case .wave20: 40
        case .wave30: 75
        case .firstFusion: 20
        case .fusions25: 40
        case .combo50: 30
        case .combo100: 50
        case .labUpgrades10: 25
        case .allHeroes, .allUltimates, .allShots: 50
        }
    }

    var symbol: String {
        switch self {
        case .firstRun: "flag.checkered"
        case .kills100, .kills1000, .kills10000: "scope"
        case .firstBoss, .bosses10: "crown.fill"
        case .wave10, .wave20, .wave30: "water.waves"
        case .firstFusion, .fusions25: "sparkles"
        case .combo50, .combo100: "flame.fill"
        case .labUpgrades10: "flask.fill"
        case .allHeroes: "person.3.fill"
        case .allUltimates: "burst.fill"
        case .allShots: "book.closed.fill"
        }
    }

    var color: Color {
        switch self {
        case .firstRun: GamePalette.primary
        case .kills100, .kills1000, .kills10000: GamePalette.coral
        case .firstBoss, .bosses10: GamePalette.gold
        case .wave10, .wave20, .wave30: GamePalette.cyan
        case .firstFusion, .fusions25: GamePalette.magenta
        case .combo50, .combo100: GamePalette.accent
        case .labUpgrades10: GamePalette.lime
        case .allHeroes, .allUltimates, .allShots: GamePalette.violet
        }
    }

    /// Progress from 0 to 1.
    func progress(in profile: PlayerProfile) -> Double {
        func ratio(_ value: Int, _ goal: Int) -> Double { min(1, Double(value) / Double(goal)) }
        return switch self {
        case .firstRun: ratio(profile.totalRuns, 1)
        case .kills100: ratio(profile.totalKills, 100)
        case .kills1000: ratio(profile.totalKills, 1000)
        case .kills10000: ratio(profile.totalKills, 10000)
        case .firstBoss: ratio(profile.bossesDefeated, 1)
        case .bosses10: ratio(profile.bossesDefeated, 10)
        case .wave10: ratio(profile.bestWave, 10)
        case .wave20: ratio(profile.bestWave, 20)
        case .wave30: ratio(profile.bestWave, 30)
        case .firstFusion: ratio(profile.fusionsMade, 1)
        case .fusions25: ratio(profile.fusionsMade, 25)
        case .combo50: ratio(profile.bestCombo, 50)
        case .combo100: ratio(profile.bestCombo, 100)
        case .labUpgrades10: ratio(profile.labLevels.values.reduce(0, +), 10)
        case .allHeroes: ratio(profile.unlockedCharacters.count, HeroCharacter.allCases.count)
        case .allUltimates: ratio(profile.unlockedUltimates.count, UltimateKind.allCases.count)
        case .allShots: ratio(profile.discoveredBalls.count, BallType.allCases.count)
        }
    }
}
