import Foundation
import Observation

struct GameSettings: Codable, Equatable {
    var sound = true
    var haptics = true
    var screenShake = true
    var damageNumbers = true
}

struct PlayerProfile: Codable, Equatable {
    var cores = 0
    var bestScore = 0
    var bestWave = 0
    var bestCombo = 0
    var totalRuns = 0
    var totalKills = 0
    var bossesDefeated = 0
    var fusionsMade = 0
    var labLevels: [String: Int] = [:]
    var unlockedCharacters: Set<String> = [HeroCharacter.vanguard.rawValue]
    var selectedCharacter: String = HeroCharacter.vanguard.rawValue
    var discoveredBalls: Set<String> = [BallType.basic.rawValue]
    var unlockedUltimates: Set<String> = [UltimateKind.pulse.rawValue]
    var selectedUltimate: String = UltimateKind.pulse.rawValue
    var settings = GameSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cores = try c.decodeIfPresent(Int.self, forKey: .cores) ?? 0
        bestScore = try c.decodeIfPresent(Int.self, forKey: .bestScore) ?? 0
        bestWave = try c.decodeIfPresent(Int.self, forKey: .bestWave) ?? 0
        bestCombo = try c.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 0
        totalRuns = try c.decodeIfPresent(Int.self, forKey: .totalRuns) ?? 0
        totalKills = try c.decodeIfPresent(Int.self, forKey: .totalKills) ?? 0
        bossesDefeated = try c.decodeIfPresent(Int.self, forKey: .bossesDefeated) ?? 0
        fusionsMade = try c.decodeIfPresent(Int.self, forKey: .fusionsMade) ?? 0
        labLevels = try c.decodeIfPresent([String: Int].self, forKey: .labLevels) ?? [:]
        unlockedCharacters = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedCharacters) ?? [HeroCharacter.vanguard.rawValue]
        selectedCharacter = try c.decodeIfPresent(String.self, forKey: .selectedCharacter) ?? HeroCharacter.vanguard.rawValue
        discoveredBalls = try c.decodeIfPresent(Set<String>.self, forKey: .discoveredBalls) ?? [BallType.basic.rawValue]
        unlockedUltimates = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedUltimates) ?? [UltimateKind.pulse.rawValue]
        selectedUltimate = try c.decodeIfPresent(String.self, forKey: .selectedUltimate) ?? UltimateKind.pulse.rawValue
        settings = try c.decodeIfPresent(GameSettings.self, forKey: .settings) ?? GameSettings()
    }
}

struct RunReward: Equatable {
    var cores: Int
    var newBestScore: Bool
    var newBestWave: Bool
}

/// Local persistence: a JSON file in Application Support, written after every change.
@MainActor
@Observable
final class ProfileStore {
    private(set) var profile: PlayerProfile
    /// Called after every save, e.g. to sync achievements.
    @ObservationIgnored var onSave: ((PlayerProfile) -> Void)?

    private let url: URL

    init(filename: String = "profile.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = PlayerProfile()
        }
    }

    var selectedCharacter: HeroCharacter {
        HeroCharacter(rawValue: profile.selectedCharacter) ?? .vanguard
    }

    var selectedUltimate: UltimateKind {
        UltimateKind(rawValue: profile.selectedUltimate) ?? .pulse
    }

    func labLevel(_ upgrade: LabUpgrade) -> Int {
        profile.labLevels[upgrade.rawValue] ?? 0
    }

    func isUnlocked(_ character: HeroCharacter) -> Bool {
        profile.unlockedCharacters.contains(character.rawValue)
    }

    func isUnlocked(_ ultimate: UltimateKind) -> Bool {
        profile.unlockedUltimates.contains(ultimate.rawValue)
    }

    func isDiscovered(_ ball: BallType) -> Bool {
        profile.discoveredBalls.contains(ball.rawValue)
    }

    func runConfig() -> RunConfig {
        var lab: [LabUpgrade: Int] = [:]
        for upgrade in LabUpgrade.allCases { lab[upgrade] = labLevel(upgrade) }
        return RunConfig(
            character: selectedCharacter,
            ultimate: selectedUltimate,
            lab: lab,
            coachUltimate: profile.totalRuns == 0
        )
    }

    @discardableResult
    func purchase(_ upgrade: LabUpgrade) -> Bool {
        let level = labLevel(upgrade)
        guard level < upgrade.maxLevel else { return false }
        let cost = upgrade.cost(forLevel: level)
        guard profile.cores >= cost else { return false }
        profile.cores -= cost
        profile.labLevels[upgrade.rawValue] = level + 1
        save()
        return true
    }

    @discardableResult
    func unlock(_ character: HeroCharacter) -> Bool {
        guard !isUnlocked(character), profile.cores >= character.cost else { return false }
        profile.cores -= character.cost
        profile.unlockedCharacters.insert(character.rawValue)
        profile.selectedCharacter = character.rawValue
        save()
        return true
    }

    func select(_ character: HeroCharacter) {
        guard isUnlocked(character) else { return }
        profile.selectedCharacter = character.rawValue
        save()
    }

    @discardableResult
    func unlock(_ ultimate: UltimateKind) -> Bool {
        guard !isUnlocked(ultimate), profile.cores >= ultimate.cost else { return false }
        profile.cores -= ultimate.cost
        profile.unlockedUltimates.insert(ultimate.rawValue)
        profile.selectedUltimate = ultimate.rawValue
        save()
        return true
    }

    func select(_ ultimate: UltimateKind) {
        guard isUnlocked(ultimate) else { return }
        profile.selectedUltimate = ultimate.rawValue
        save()
    }

    func updateSettings(_ settings: GameSettings) {
        profile.settings = settings
        save()
    }

    func record(_ run: RunStats) -> RunReward {
        let reward = RunReward(
            cores: run.coresEarned,
            newBestScore: run.score > profile.bestScore,
            newBestWave: run.wave > profile.bestWave
        )
        profile.cores += run.coresEarned
        profile.bestScore = max(profile.bestScore, run.score)
        profile.bestWave = max(profile.bestWave, run.wave)
        profile.bestCombo = max(profile.bestCombo, run.bestCombo)
        profile.totalRuns += 1
        profile.totalKills += run.kills
        profile.bossesDefeated += run.bossesDefeated
        profile.fusionsMade += run.fusions
        profile.discoveredBalls.formUnion(run.discoveredBalls.map(\.rawValue))
        save()
        return reward
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url, options: [.atomic])
        } catch {
            assertionFailure("Failed to save profile: \(error)")
        }
        onSave?(profile)
    }
}
