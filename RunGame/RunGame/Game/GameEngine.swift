import Foundation
import Observation
import CoreGraphics

// MARK: - Simulation entities

struct StatusEffects {
    var burnDPS = 0.0
    var burnTime = 0.0
    var slow = 0.0
    var slowTime = 0.0
    var freezeTime = 0.0
    var poisonStacks = 0
    var poisonDPS = 0.0
    var poisonTime = 0.0

    var isFrozen: Bool { freezeTime > 0 }
    var isBurning: Bool { burnTime > 0 }
    var isPoisoned: Bool { poisonTime > 0 && poisonStacks > 0 }
    var isSlowed: Bool { slowTime > 0 }
}

struct Enemy: Identifiable {
    let id: Int
    let kind: EnemyKind
    var position: CGPoint
    var health: Double
    let maxHealth: Double
    let radius: CGFloat
    var speed: CGFloat
    let isElite: Bool
    var status = StatusEffects()
    var holdY: CGFloat = 0
    var attackTimer = 0.0
    var summonTimer = 0.0
    var spiralAngle = 0.0
    var strafeDirection: CGFloat = 1
    var bossPhase = 1
    var bossVariant: BossVariant = .void
    var lastHitType: BallType = .basic
    var plagueCarrier = false
    var dotBuffer = 0.0
    var dotTick = 0.0
    var dotType: BallType = .fire
    var wobbleSeed: Double = 0

    var isAlive: Bool { health > 0 }
}

struct Ball: Identifiable {
    let id: Int
    var type: BallType
    var position: CGPoint
    var velocity: CGVector
    var pierceLeft: Int
    var wallBounces = 0
    var age = 0.0
    var immunities: [(id: Int, until: Double)] = []
    var isTemporary = false
    var radius: CGFloat = 7
    /// Heated by a wall ricochet: it hurts the hero if it falls back onto them.
    var isHot = false
}

struct Bullet: Identifiable {
    let id: Int
    let kind: BulletKind
    var position: CGPoint
    var velocity: CGVector
    var radius: CGFloat
    var health: Int
    /// Sprite frames base (`<art>_01…04`): the shooter's own shot, or the kind's shared art.
    let art: String
    /// Last ball that cracked this bullet, so one pass only counts once.
    var lastBallID: Int?
    /// The shooter's signature behavior, and its tier when fired.
    var trick: ShotTrick = .none
    var tier = 1
    /// Seconds since it was fired; times forks, fuses, homing and lunges.
    var age = 0.0
    /// Speed a surging or lunging shot works up to.
    var cruise: CGFloat = 0
}

/// Stat multipliers derived from passives, character and lab upgrades.
struct Modifiers {
    var damage = 1.0
    var ballSpeed: CGFloat = 520
    var launchInterval = 0.14
    var critChance = 0.05
    var critMultiplier = 2.5
    var pierce = 0
    var pulseDamage = 1.0
    var pulseGain = 1.0
    var chill = 0.0
    var enemyHealth = 1.0
    var scoreBonus = 0.0
    var coreGain = 1.0
    var eliteBonus = 0.0
    var lifeStealEvery = 0
    var lastStand = 0.0
    var bankShot = 0.0
    var xpGain = 1.0
    var maxSlots = 4
}

// MARK: - Engine

@MainActor
@Observable
final class GameEngine {
    // Observed: things the SwiftUI HUD displays. They change at most a few times per second.
    private(set) var phase: GamePhase = .menu
    private(set) var wave = 1
    private(set) var level = 1
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var experience = 0
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var specialEnergy = 0.0
    /// Whole seconds left before the Pulse can charge again (0 = charging normally).
    private(set) var pulseCooldownSeconds = 0
    private(set) var waveModifier: WaveModifier = .standard
    private(set) var upgradeChoices: [UpgradeOption] = []
    private(set) var upgradeContext: UpgradeContext = .levelUp
    private(set) var upgradeLockRemaining = 0.0
    private(set) var banner: Banner?
    /// Seconds into the boss intro card, nil when none is showing. Only advances while playing.
    private(set) var bossIntroElapsed: Double?
    private(set) var bossHealthRatio: Double?
    private(set) var bossVariant: BossVariant = .void
    private(set) var ballLevels: [BallType: Int] = [:]
    private(set) var basicBallCount = 2
    private(set) var passiveLevels: [Passive: Int] = [:]
    /// Armor equipped on the hero, one piece per slot at the best rarity picked for it.
    private(set) var heroGear: [HeroGearSlot: UpgradeRarity] = [:]
    /// Lowest rarity across a complete armor set, nil until every slot holds a piece.
    private(set) var gearSetRarity: UpgradeRarity?
    private(set) var finalStats: RunStats?
    private(set) var config = RunConfig()
    /// Times the player free-aimed this run. The boss aim tip watches it to know it was learned.
    private(set) var manualAimCount = 0

    // Not observed: per-frame simulation state, read directly by the SpriteKit scene.
    @ObservationIgnored private(set) var enemies: [Enemy] = []
    @ObservationIgnored private(set) var balls: [Ball] = []
    @ObservationIgnored private(set) var bullets: [Bullet] = []
    @ObservationIgnored private(set) var heroX: CGFloat = 200
    @ObservationIgnored private(set) var arenaSize = CGSize(width: 390, height: 640)
    @ObservationIgnored private(set) var aimTargetID: Int?
    @ObservationIgnored private(set) var aimAngle: CGFloat = -.pi / 2
    /// Enemy the player tapped. Overrides auto-aim until it dies, leaves the screen or is tapped again.
    @ObservationIgnored private(set) var manualTargetID: Int?
    /// Spot the player tapped on empty arena. Balls fly toward it (great for wall bank shots)
    /// until it is tapped again, an enemy is picked, or the wave ends.
    @ObservationIgnored private(set) var manualAimPoint: CGPoint?
    /// Slow-motion beat between "level up!" and the upgrade screen, so the pause reads as a reward.
    @ObservationIgnored private(set) var levelUpBeat: Double?
    @ObservationIgnored private(set) var heroInvulnerability = 0.0
    @ObservationIgnored private(set) var time = 0.0
    @ObservationIgnored private(set) var ammoCount = 0

    @ObservationIgnored private var events: [GameEvent] = []
    @ObservationIgnored private var rng = SeededGenerator(seed: 1)
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var ammo: [BallType] = []
    @ObservationIgnored private var mods = Modifiers()
    @ObservationIgnored private var heroTargetX: CGFloat = 200
    @ObservationIgnored private var dragAnchor: (touch: CGFloat, hero: CGFloat)?
    @ObservationIgnored private var launchTimer = 0.0
    @ObservationIgnored private var spawnTimer = 0.0
    @ObservationIgnored private var spawnRemaining = 0
    @ObservationIgnored private var bossPending = false
    @ObservationIgnored private var waveClearTimer: Double?
    @ObservationIgnored private var comboTimer = 0.0
    @ObservationIgnored private var bannerTimer = 0.0
    @ObservationIgnored private var nextBannerID = 1
    @ObservationIgnored private var pendingLevelUps = 0
    @ObservationIgnored private var pendingChest = false
    @ObservationIgnored private var killsSinceHeal = 0
    @ObservationIgnored private var vampireKills = 0
    @ObservationIgnored private var stats = RunStats()
    @ObservationIgnored private var pulseCooldown = 0.0
    @ObservationIgnored private var lethalWarned = false
    /// Adaptive difficulty, in waves: how far ahead of (or behind) the real wave the enemies are
    /// tuned. Clean waves push it up, lost lives pull it down, so the run settles just above
    /// what the player can comfortably handle.
    @ObservationIgnored private var edge = 0.0
    @ObservationIgnored private var hurtThisWave = false
    @ObservationIgnored private var introducedShots: Set<BulletKind> = []
    @ObservationIgnored private var introducedTricks: Set<String> = []
    @ObservationIgnored private var announcedTier = 1
    @ObservationIgnored private var hotBallsAnnounced = false

    static let maxBullets = 140
    static let edgeRange = -3.0...4.0
    /// Past this score enemies may fire run-ending shots.
    static let lethalScoreThreshold = 300_000
    static let heroRadius: CGFloat = 16
    /// Half-width of the auto-aim lane beyond the enemy's own radius, before it widens with height.
    static let autoAimLane: CGFloat = 30
    /// After a Pulse the reactor overheats and gains no charge for this long.
    static let pulseCooldownDuration = 12.0
    /// Fits inside the lead-in before a boss wave's first spawn.
    static let bossIntroDuration = 2.1

    var heroY: CGFloat { arenaSize.height - 64 }
    var heroPosition: CGPoint { CGPoint(x: heroX, y: heroY) }
    var experienceNeeded: Int { Int(18 + Double(level - 1) * 12 + pow(Double(level), 1.6)) }
    var comboMultiplier: Double { min(10, 1 + Double(combo) / 5) }
    var canPulse: Bool { phase == .playing && specialEnergy >= 1 }
    var isBossWave: Bool { wave % 5 == 0 }
    /// 1 for the first boss (wave 5), 2 for the second, and so on.
    private var bossTier: Int { max(1, wave / 5) }
    var specialSlotsUsed: Int { ballLevels.count }
    var maxSlots: Int { mods.maxSlots }

    /// Owned special balls sorted for display (fusions first).
    var ownedSpecialBalls: [(type: BallType, level: Int)] {
        ballLevels
            .map { (type: $0.key, level: $0.value) }
            .sorted { lhs, rhs in
                if lhs.type.isFusion != rhs.type.isFusion { return lhs.type.isFusion }
                return lhs.type.rawValue < rhs.type.rawValue
            }
    }

    private var baseDamage: Double { 10 * (1 + 0.04 * Double(level - 1)) }

    /// The opening waves run behind the clock: a lag that fades out by wave 13, so the first
    /// waves and the first boss leave room to learn before the curve proper takes over.
    /// An upgraded hero has nothing left to learn: the lag shrinks with the loadout and is gone
    /// at 3 waves' worth of it.
    private var warmUp: Double {
        2.5 * max(0, 1 - Double(wave - 1) / 12) * max(0, 1 - config.loadoutThreat / 3)
    }

    /// Upgraded players come for a real fight, so the loadout raises the bar by half again its
    /// raw worth, in full from wave 1.
    private var loadoutBar: Double { Self.loadoutWeight * config.loadoutThreat }
    static let loadoutWeight = 1.5

    /// The adaptive edge can sink below its usual floor by the loadout's raw worth, so a player
    /// who struggles with a strong loadout is eased down, but never all the way to the bare
    /// baseline: the extra weight stays.
    private var edgeFloor: Double { Self.edgeRange.lowerBound - config.loadoutThreat }

    /// The wave the enemies are tuned for: the real wave, minus the warm-up, plus the
    /// loadout's bar (lab, hero, ultimate), shifted by the player's `edge`. Drives enemy
    /// toughness, speed, spawn rate, mix, shot types and bosses.
    private var threat: Double { max(1, Double(wave) - warmUp + loadoutBar + edge) }

    /// Share of the horde's shot attempts that actually fire: none early on, then creeping up
    /// with the threat so grunts and tanks harass the hero instead of only walking down.
    private var hordeFireChance: Double { min(0.35, max(0, 0.03 * (threat - 3))) }

    private var healthScale: Double {
        let modifierScale = waveModifier == .armored ? 1.55 : 1
        return pow(1.17, threat - 1) * modifierScale * mods.enemyHealth
    }

    private var descentSpeed: CGFloat {
        let frenzy: CGFloat = waveModifier == .frenzy ? 1.55 : 1
        return (30 + 2.2 * CGFloat(min(threat, 40))) * frenzy * CGFloat(max(0.3, 1 - mods.chill))
    }

    /// Tier of the enemies' signature shots (`ShotTrick`): 1 from the start, then 2 and 3 as
    /// the threat climbs. It follows the threat both ways, so a struggling player sees it ease.
    private var trickTier: Int { threat >= 15 ? 3 : (threat >= 8 ? 2 : 1) }

    /// Enemy projectiles get faster as the run goes on.
    private var bulletSpeedScale: CGFloat { 1 + 0.012 * CGFloat(min(threat, 40)) }

    /// Chance that a wall ricochet heats the ball so it can hurt the hero on the way back.
    /// None in the opening threat, then fading in so bank shots turn into a real risk.
    private var ricochetHeatChance: Double { min(0.45, max(0, 0.03 * (threat - 2.5))) }

    /// Tougher threat makes bosses attack more often: multiplies their attack intervals.
    private var bossTempo: Double { max(0.55, 1.2 - 0.03 * threat) }

    /// Bosses met at a low threat (the first one, or a struggling player) come in lighter.
    private var bossHealthEase: Double { min(1, 0.5 + 0.065 * threat) }

    /// Pulse charge per kill shrinks as waves get longer, so it stays a once-per-wave tool.
    private var pulseChargeScale: Double { 1 / (1 + 0.1 * Double(wave - 1)) }

    // MARK: Lifecycle

    func start(config: RunConfig) {
        self.config = config
        rng = SeededGenerator(seed: config.seed)
        nextID = 1
        wave = 1
        level = 1
        score = 0
        experience = 0
        combo = 0
        bestCombo = 0
        comboTimer = 0
        killsSinceHeal = 0
        vampireKills = 0
        enemies = []
        balls = []
        bullets = []
        events = [.runStarted]
        ammo = []
        passiveLevels = [:]
        ballLevels = [:]
        heroGear = [:]
        gearSetRarity = nil
        finalStats = nil
        banner = nil
        bossIntroElapsed = nil
        bossHealthRatio = nil
        upgradeChoices = []
        pendingLevelUps = 0
        pendingChest = false
        waveClearTimer = nil
        heroInvulnerability = 0
        time = 0
        pulseCooldown = 0
        pulseCooldownSeconds = 0
        lethalWarned = false
        edge = 0
        hurtThisWave = false
        introducedShots = []
        introducedTricks = []
        announcedTier = 1
        hotBallsAnnounced = false
        stats = RunStats()

        lives = 3 + config.labLevel(.vitality)
        basicBallCount = 2
        switch config.character {
        case .vanguard:
            break
        case .ricochet:
            break
        case .pyra:
            lives -= 1
            basicBallCount = 1
            ballLevels[.fire] = 1
            ballLevels[.explosive] = 1
        case .glacius:
            basicBallCount = 1
            ballLevels[.ice] = 1
        }
        if config.labLevel(.headStart) > 0 {
            let candidates = BallType.elemental.filter { ballLevels[$0] == nil }
            if let pick = candidates.randomElement(using: &rng) {
                ballLevels[pick] = 1
            }
        }
        stats.discoveredBalls = Set(ballLevels.keys)

        recomputeModifiers()
        specialEnergy = min(1, 0.15 * Double(config.labLevel(.reactor)))
        // The run picks up wherever the player left the hero on the home screen.
        heroTargetX = heroX
        manualTargetID = nil
        manualAimPoint = nil
        manualAimCount = 0
        levelUpBeat = nil
        syncRoster()
        phase = .playing
        startWave(1)
    }

    func setArenaSize(_ size: CGSize) {
        guard size.width > 50, size.height > 200 else { return }
        let changed = size != arenaSize
        arenaSize = size
        if changed {
            heroX = phase == .menu ? size.width / 2 : min(max(heroX, 24), size.width - 24)
            heroTargetX = heroX
        }
    }

    func pause() {
        guard phase == .playing else { return }
        phase = .paused
        dragAnchor = nil
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .playing
    }

    func abandonRun() {
        guard phase == .paused || phase == .playing || phase == .choosingUpgrade else { return }
        finishRun()
    }

    func returnToMenu() {
        phase = .menu
        enemies = []
        balls = []
        bullets = []
        banner = nil
        bossIntroElapsed = nil
        bossHealthRatio = nil
        heroGear = [:]
        gearSetRarity = nil
        heroInvulnerability = 0
        specialEnergy = 0
        manualTargetID = nil
        manualAimPoint = nil
        levelUpBeat = nil
        aimTargetID = nil
        // The hero jogs back to the middle of the home screen.
        heroTargetX = arenaSize.width / 2
    }

    /// Dresses the idle hero on the home screen as the character the next run will use.
    func preview(_ config: RunConfig) {
        guard phase == .menu else { return }
        self.config = config
    }

    func drainEvents() -> [GameEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    // MARK: Input

    func beginDrag(at x: CGFloat) {
        guard phase == .playing || phase == .menu else { return }
        dragAnchor = (x, heroTargetX)
    }

    func drag(to x: CGFloat) {
        guard phase == .playing || phase == .menu, let anchor = dragAnchor else { return }
        heroTargetX = min(max(anchor.hero + (x - anchor.touch) * 1.25, 24), arenaSize.width - 24)
    }

    func endDrag() {
        dragAnchor = nil
    }

    /// Locks the aim on the enemy under a tap (generous hit area). Tapping the locked enemy
    /// again releases it back to auto-aim.
    /// A tap picks an enemy to focus, or, on empty arena, a point to aim at. Tapping the current
    /// focus again hands control back to auto-aim.
    func selectTarget(at point: CGPoint) {
        guard phase == .playing else { return }
        let hit = enemies
            .filter { $0.position.y + $0.radius > 0 && $0.position.y < heroY }
            .map { (enemy: $0, distance: hypot($0.position.x - point.x, $0.position.y - point.y)) }
            .filter { $0.distance <= $0.enemy.radius + 24 }
            .min { $0.distance < $1.distance }
        if let enemy = hit?.enemy {
            manualAimPoint = nil
            if enemy.id == manualTargetID {
                manualTargetID = nil
                events.append(.targetReleased)
            } else {
                manualTargetID = enemy.id
                events.append(.targetLocked(enemyID: enemy.id, position: enemy.position))
            }
            return
        }
        if let current = manualAimPoint, hypot(current.x - point.x, current.y - point.y) < 36 {
            releaseAimPoint()
            return
        }
        // Keep the point above the hero so the shot always travels up the arena.
        let aim = CGPoint(
            x: min(max(point.x, 0), arenaSize.width),
            y: min(point.y, heroY - 40)
        )
        manualTargetID = nil
        manualAimPoint = aim
        manualAimCount += 1
        events.append(.aimPointSet(aim))
    }

    private func releaseAimPoint() {
        guard manualAimPoint != nil else { return }
        manualAimPoint = nil
        events.append(.targetReleased)
    }

    func activatePulse() {
        guard canPulse else { return }
        specialEnergy = 0
        pulseCooldown = Self.pulseCooldownDuration
        pulseCooldownSeconds = Int(pulseCooldown.rounded(.up))
        let kind = config.ultimate
        switch kind {
        case .pulse: firePulseNova()
        case .stasis: fireStasis()
        case .storm: fireStorm()
        case .swarm: fireSwarm()
        }
        events.append(.ultimate(kind, heroPosition))
        processDeaths()
    }

    private func clearBullets() {
        for bullet in bullets {
            events.append(.bulletBlocked(bullet.position))
        }
        bullets.removeAll()
    }

    private func firePulseNova() {
        let damage = 24 * healthScale * mods.pulseDamage
        for index in enemies.indices {
            // Bosses shrug off most of the blast: the Pulse is a panic button, not a boss killer.
            let scale = enemies[index].kind == .boss ? 0.35 : 1
            damageEnemy(at: index, amount: damage * scale, type: .basic)
            if enemies[index].kind != .boss {
                enemies[index].position.y = max(-enemies[index].radius, enemies[index].position.y - 60)
            }
        }
        clearBullets()
        let count = 12
        for i in 0..<count {
            let angle = CGFloat.pi + CGFloat.pi * (CGFloat(i) + 0.5) / CGFloat(count)
            spawnUltimateBall(angle: angle, pierce: 2 + mods.pierce, speedScale: 1.1)
        }
    }

    /// Time stops for the horde; bosses only crawl, since a frozen boss would trivialize the fight.
    private func fireStasis() {
        let damage = 8 * healthScale * mods.pulseDamage
        for index in enemies.indices {
            if enemies[index].kind == .boss {
                enemies[index].status.slow = max(enemies[index].status.slow, 0.7)
                enemies[index].status.slowTime = max(enemies[index].status.slowTime, 4)
            } else {
                enemies[index].status.freezeTime = max(enemies[index].status.freezeTime, 4 * mods.pulseDamage.squareRoot())
            }
            damageEnemy(at: index, amount: damage, type: .ice)
        }
        clearBullets()
    }

    /// Three bolts per visible enemy. The boss-killer of the set, but it leaves bullets alone.
    private func fireStorm() {
        let damage = 14 * healthScale * mods.pulseDamage
        for index in enemies.indices where enemies[index].position.y + enemies[index].radius > 0 {
            let scale = enemies[index].kind == .boss ? 0.6 : 1
            let target = enemies[index].position
            for _ in 0..<3 {
                damageEnemy(at: index, amount: damage * scale, type: .lightning)
            }
            let sky = CGPoint(x: target.x + rng.range(-40...40), y: -20)
            events.append(.chain(from: sky, to: target, type: .lightning))
        }
    }

    /// A dense, piercing volley along the current aim, so it rewards aiming at what matters.
    private func fireSwarm() {
        let count = 24
        for i in 0..<count {
            let spread = 0.35 * (CGFloat(i) / CGFloat(count - 1) * 2 - 1)
            spawnUltimateBall(angle: aimAngle + spread, pierce: 3 + mods.pierce, speedScale: 1.0 + 0.25 * CGFloat(i % 3))
        }
    }

    private func spawnUltimateBall(angle: CGFloat, pierce: Int, speedScale: CGFloat) {
        let speed = mods.ballSpeed * speedScale
        var ball = Ball(
            id: makeID(),
            type: .basic,
            position: heroPosition,
            velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
            pierceLeft: pierce
        )
        ball.isTemporary = true
        ball.radius = 6
        balls.append(ball)
    }

    func choose(_ option: UpgradeOption) {
        guard phase == .choosingUpgrade, upgradeLockRemaining <= 0, upgradeChoices.contains(option) else { return }
        let gear = gearPreview(for: option)
        apply(option)
        events.append(.upgradeChosen)
        if gear.isUpgrade {
            equipGear(gear.slot, rarity: gear.rarity)
        }
        upgradeChoices = []
        if pendingLevelUps > 0 {
            presentUpgrade(.levelUp)
        } else if pendingChest {
            pendingChest = false
            presentUpgrade(.bossChest)
        } else {
            phase = .playing
        }
    }

    // MARK: Update loop

    func update(deltaTime rawDelta: Double) {
        if phase == .choosingUpgrade, upgradeLockRemaining > 0 {
            upgradeLockRemaining = max(0, upgradeLockRemaining - rawDelta)
        }
        let dt = min(rawDelta, 1.0 / 30.0)
        if phase == .playing, let beat = levelUpBeat {
            // No slow motion here: slowing the action reads as dying. The hero just can't be hit.
            levelUpBeat = beat - dt
            heroInvulnerability = max(heroInvulnerability, 0.3)
        }
        if phase == .menu {
            // The home screen is the arena without enemies: the hero can still be dragged around.
            heroX += (heroTargetX - heroX) * CGFloat(min(1, dt * 18))
            return
        }
        guard phase == .playing else { return }
        time += dt

        heroX += (heroTargetX - heroX) * CGFloat(min(1, dt * 18))
        heroInvulnerability = max(0, heroInvulnerability - dt)

        updateBanner(dt)
        updateBossIntro(dt)
        updateCombo(dt)
        updatePulseCooldown(dt)
        updateSpawning(dt)
        updateEnemies(dt)
        updateLaunching(dt)
        updateBalls(dt)
        updateBullets(dt)
        processDeaths()
        updateBossBar()
        checkWaveClear(dt)
        warnLethalShots()

        if lives <= 0 {
            finishRun()
            return
        }
        guard pendingLevelUps > 0 || pendingChest else { return }
        // Let the "level up" burst land around the hero before the choice slides in.
        guard let beat = levelUpBeat else {
            levelUpBeat = Self.levelUpBeatDuration
            return
        }
        guard beat <= 0 else { return }
        levelUpBeat = nil
        if pendingLevelUps > 0 {
            presentUpgrade(.levelUp)
        } else if pendingChest {
            pendingChest = false
            presentUpgrade(.bossChest)
        }
    }

    static let levelUpBeatDuration = 0.45

    // MARK: Waves

    private func startWave(_ number: Int) {
        wave = number
        if number > 1 { releaseAimPoint() }
        stats.wave = number
        waveClearTimer = nil
        hurtThisWave = false
        if isBossWave || number == 1 {
            waveModifier = .standard
        } else {
            let roll = rng.range(0...1.0)
            waveModifier = roll < 0.5 ? .standard : (roll < 0.67 ? .frenzy : (roll < 0.84 ? .armored : .swarm))
        }
        if isBossWave {
            bossPending = true
            spawnRemaining = 3 + number / 2
            spawnTimer = 2.2
            bossVariant = BossVariant.forWave(number)
            bossIntroElapsed = 0
            // The boss's name is on its intro card.
            showBanner(title: "CHEFE · ONDA \(number)", subtitle: nil, style: .boss, duration: 2.4)
        } else {
            bossPending = false
            let base = 6 + 2.8 * Double(number)
            spawnRemaining = Int(base * (waveModifier == .swarm ? 1.45 : 1))
            spawnTimer = 0.6
            showBanner(title: "ONDA \(number)", subtitle: waveModifier == .standard ? nil : waveModifier.title, style: .wave, duration: 1.6)
        }
        events.append(.waveStarted(wave: number, isBoss: isBossWave))
    }

    /// Clean waves raise the edge, a little more after a boss. Hurt waves still nudge it up a
    /// bit (the penalty already landed in `loseLife`), so the challenge keeps climbing. The
    /// first waves are clean for almost anyone, so they count for less.
    private func adaptAfterWave() {
        let ramp = min(1, Double(wave) / 5)
        let gain = (hurtThisWave ? 0.05 : (isBossWave ? 0.5 : 0.3)) * ramp
        edge = min(Self.edgeRange.upperBound, edge + gain)
    }

    private func warnLethalShots() {
        guard !lethalWarned, score >= Self.lethalScoreThreshold else { return }
        lethalWarned = true
        showBanner(title: "TIROS LETAIS", subtitle: "Estrelas pretas matam na hora", style: .boss, duration: 2.6)
    }

    private var spawnInterval: Double {
        let base = max(0.22, 0.85 - 0.032 * threat)
        return waveModifier == .swarm ? base * 0.55 : base
    }

    private func updateSpawning(_ dt: Double) {
        guard waveClearTimer == nil else { return }
        spawnTimer -= dt
        guard spawnTimer <= 0 else { return }
        if bossPending {
            bossPending = false
            spawn(kind: .boss, elite: false)
            events.append(.bossSpawned)
            spawnTimer = 3
            return
        }
        guard spawnRemaining > 0 else { return }
        spawnRemaining -= 1
        spawnTimer = spawnInterval * rng.range(0.7...1.3)
        let kind = rollKind()
        let eliteChance = threat >= 3 ? min(0.4, (6 + threat + mods.eliteBonus) / 100) : 0
        spawn(kind: kind, elite: rng.chance(eliteChance))
    }

    private func rollKind() -> EnemyKind {
        let roll = rng.range(0...100.0)
        // Thresholds creep up with the threat, so grunts give way to tougher kinds over the run.
        let level = threat
        let late = min(level, 30)
        if level >= 6, roll < 6 + late * 0.3 { return .bomber }
        if level >= 5, roll < 16 + late * 0.5 { return .shielded }
        if level >= 3, roll < 26 + late * 0.8 { return .shooter }
        if level >= 4, roll < 36 + late * 0.8 { return .splitter }
        if level >= 3, roll < 50 + late * 0.8 { return .tank }
        if level >= 2, roll < 72 + late * 0.5 { return .runner }
        return .grunt
    }

    @discardableResult
    private func spawn(kind: EnemyKind, elite: Bool, at position: CGPoint? = nil) -> Int {
        let radius = kind.radius * (elite ? 1.2 : 1)
        let bossScale = kind == .boss ? (1 + 0.3 * Double(bossTier - 1)) * bossHealthEase : 1
        let health = kind.baseHealth * healthScale * bossScale * (elite ? 2 : 1)
        let x = position?.x ?? rng.range((radius + 8)...max(radius + 9, arenaSize.width - radius - 8))
        let y = position?.y ?? -radius
        var enemy = Enemy(
            id: makeID(),
            kind: kind,
            position: CGPoint(x: x, y: y),
            health: health,
            maxHealth: health,
            radius: radius,
            speed: descentSpeed * CGFloat(kind.speedScale),
            isElite: elite
        )
        enemy.wobbleSeed = rng.range(0...(Double.pi * 2))
        switch kind {
        case .shooter:
            enemy.holdY = arenaSize.height * rng.range(0.12...0.42)
            enemy.attackTimer = rng.range(1.0...2.0)
            enemy.strafeDirection = rng.chance(0.5) ? 1 : -1
        case .boss:
            enemy.holdY = arenaSize.height * 0.16
            enemy.attackTimer = 2
            enemy.summonTimer = 7
            enemy.bossVariant = bossVariant
        default:
            enemy.attackTimer = rng.range(1.5...3.5)
        }
        enemies.append(enemy)
        return enemy.id
    }

    private func checkWaveClear(_ dt: Double) {
        if let timer = waveClearTimer {
            let remaining = timer - dt
            if remaining <= 0 {
                startWave(wave + 1)
            } else {
                waveClearTimer = remaining
            }
            return
        }
        guard spawnRemaining == 0, !bossPending, enemies.isEmpty else { return }
        waveClearTimer = 2.2
        adaptAfterWave()
        let bonus = wave * 100
        score += bonus
        bullets.removeAll()
        events.append(.waveCleared)
        showBanner(title: "ONDA LIMPA", subtitle: "+\(bonus)", style: .clear, duration: 1.8)
        if isBossWave {
            pendingChest = true
        }
    }

    // MARK: Enemies

    private func updateEnemies(_ dt: Double) {
        let lineY = heroY
        var escaped: [Int] = []
        for index in enemies.indices {
            var enemy = enemies[index]
            tickStatus(&enemy, dt: dt)

            let frozen = enemy.status.isFrozen && enemy.kind != .boss
            var slowFactor: CGFloat = 1
            if enemy.status.isSlowed {
                let slow = enemy.kind == .boss ? enemy.status.slow * 0.5 : enemy.status.slow
                slowFactor = CGFloat(max(0.15, 1 - slow))
            }
            let speed = frozen ? 0 : enemy.speed * slowFactor

            switch enemy.kind {
            case .shooter:
                if enemy.position.y < enemy.holdY {
                    enemy.position.y += speed * CGFloat(dt) * 1.4
                } else {
                    enemy.position.x += enemy.strafeDirection * 22 * slowFactor * CGFloat(frozen ? 0 : dt)
                    if enemy.position.x < enemy.radius + 6 || enemy.position.x > arenaSize.width - enemy.radius - 6 {
                        enemy.strafeDirection *= -1
                    }
                    if !frozen {
                        enemy.attackTimer -= dt
                        if enemy.attackTimer <= 0 {
                            enemy.attackTimer = max(1.3, 2.5 - 0.05 * threat) + rng.range(0...0.6)
                            // Elite shooters fire a three-way spread.
                            fireAimed(from: enemy.position, speed: 190 * bulletSpeedScale, spread: enemy.isElite ? 0.2 : 0, count: enemy.isElite ? 3 : 1,
                                      art: enemy.kind.shotArt, trick: enemy.kind.shotTrick)
                            events.append(.enemyShot(enemy.position))
                        }
                    }
                }
            case .boss:
                updateBoss(&enemy, dt: dt, speed: speed, slowFactor: slowFactor)
            default:
                fly(&enemy, speed: speed, slowFactor: frozen ? 0 : slowFactor, dt: dt)
                if !frozen, enemy.kind != .runner, enemy.kind != .bomber { hordeAttack(&enemy, dt: dt) }
            }
            enemy.position.x = min(max(enemy.position.x, enemy.radius), arenaSize.width - enemy.radius)

            if enemy.position.y - enemy.radius * 0.3 > lineY {
                escaped.append(enemy.id)
            }
            enemies[index] = enemy
        }
        if !escaped.isEmpty {
            for id in escaped {
                if let enemy = enemies.first(where: { $0.id == id }) {
                    events.append(.enemyEscaped(enemy.position))
                }
            }
            enemies.removeAll { escaped.contains($0.id) }
            loseLife(count: escaped.count)
        }
    }

    /// The horde flies rather than marches: each wingbeat pushes the descent forward and lets it
    /// sag back, and the flyer weaves gently from side to side, bending away from the walls.
    private func fly(_ enemy: inout Enemy, speed: CGFloat, slowFactor: CGFloat, dt: Double) {
        let flight = enemy.kind.flight
        let surge = 1 + flight.surge * sin(time * flight.beat + enemy.wobbleSeed)
        enemy.position.y += speed * CGFloat(surge * dt)
        var glide = CGFloat(cos(time * flight.weave + enemy.wobbleSeed)) * flight.glide
        // Near a wall the weave only swings back towards the middle.
        let margin = enemy.radius + 12
        if enemy.position.x < margin { glide = abs(glide) }
        if enemy.position.x > arenaSize.width - margin { glide = -abs(glide) }
        enemy.position.x += glide * slowFactor * CGFloat(dt)
    }

    /// Grunts, tanks, splitters and shielded enemies take the odd shot at the hero while they
    /// walk down. They hold fire in the bottom third, so nothing fires point-blank. Each fires
    /// its own `ShotTrick`, so even the weakest enemy has a bite.
    private func hordeAttack(_ enemy: inout Enemy, dt: Double) {
        guard enemy.position.y > enemy.radius, enemy.position.y < heroY * 0.66 else { return }
        enemy.attackTimer -= dt
        guard enemy.attackTimer <= 0 else { return }
        enemy.attackTimer = rng.range(2.6...4.2)
        guard rng.chance(hordeFireChance) else { return }
        fireAimed(from: enemy.position, speed: 165 * bulletSpeedScale, spread: 0.25, count: enemy.isElite ? 2 : 1,
                  art: enemy.kind.shotArt, trick: enemy.kind.shotTrick)
        events.append(.enemyShot(enemy.position))
    }

    private func updateBoss(_ boss: inout Enemy, dt: Double, speed: CGFloat, slowFactor: CGFloat) {
        if boss.position.y < boss.holdY {
            boss.position.y += max(speed, 40) * CGFloat(dt)
            return
        }
        let ratio = boss.health / boss.maxHealth
        let newPhase = ratio > 0.66 ? 1 : (ratio > 0.33 ? 2 : 3)
        if newPhase != boss.bossPhase {
            boss.bossPhase = newPhase
            boss.attackTimer = 1
            events.append(.bossPhase(newPhase))
            showBanner(title: newPhase == 2 ? "O CHEFE SE ENFURECE" : "FÚRIA TOTAL", subtitle: nil, style: .boss, duration: 1.4)
        }
        let strafe: CGFloat = (40 + 25 * CGFloat(newPhase) + 6 * CGFloat(bossTier - 1)) * slowFactor
        let tempo = bossTempo
        let shotSpeed = bulletSpeedScale
        let art = boss.bossVariant.shotArt
        boss.position.x += boss.strafeDirection * strafe * CGFloat(dt)
        if boss.position.x < boss.radius + 10 || boss.position.x > arenaSize.width - boss.radius - 10 {
            boss.strafeDirection *= -1
        }

        boss.attackTimer -= dt
        switch newPhase {
        case 1:
            if boss.attackTimer <= 0 {
                switch boss.bossVariant {
                case .void:
                    boss.attackTimer = 1.7 * tempo
                    fireAimed(from: boss.position, speed: 200 * shotSpeed, spread: 0.22, count: 3, art: art)
                case .hydra:
                    // One aimed spit from each head.
                    boss.attackTimer = 1.8 * tempo
                    for offset: CGFloat in [-30, 0, 30] {
                        fireAimed(from: CGPoint(x: boss.position.x + offset, y: boss.position.y + 10), speed: 190 * shotSpeed, spread: 0, count: 1, art: art)
                    }
                case .mecha:
                    boss.attackTimer = 2 * tempo
                    fireAimed(from: boss.position, speed: 250 * shotSpeed, spread: 0.1, count: 5, art: art)
                case .seraph:
                    boss.attackTimer = 2 * tempo
                    fireAimed(from: boss.position, speed: 175 * shotSpeed, spread: 0.55, count: 7, art: art)
                }
                events.append(.enemyShot(boss.position))
            }
        case 2:
            if boss.attackTimer <= 0 {
                boss.attackTimer = 2.3 * tempo
                fireRing(from: boss.position, count: min(24, 8 + Int(threat * 0.8)), speed: 150 * shotSpeed, offset: boss.spiralAngle, art: art)
                boss.spiralAngle += 0.2
                events.append(.enemyShot(boss.position))
                // From the second boss on, rings are chased by an aimed burst.
                if bossTier >= 2 {
                    fireAimed(from: boss.position, speed: 210 * shotSpeed, spread: 0.16, count: 3, art: art)
                }
            }
            boss.summonTimer -= dt
            if boss.summonTimer <= 0 {
                boss.summonTimer = max(4, 7 - 0.6 * Double(bossTier - 1))
                // Later bosses call in tougher minions.
                let minion: EnemyKind = bossTier >= 3 ? .shooter : (bossTier >= 2 ? .runner : .grunt)
                for side: CGFloat in [-1, 1] {
                    spawn(kind: minion, elite: false, at: CGPoint(x: boss.position.x + side * 50, y: boss.position.y + 30))
                }
            }
        default:
            boss.summonTimer -= dt
            if boss.summonTimer <= 0 {
                // The spiral tightens with the threat: sparse on the first boss, a wall later on.
                boss.summonTimer = max(0.09, 0.26 - 0.01 * threat)
                let angle = boss.spiralAngle
                boss.spiralAngle += 0.45
                fireBullet(from: boss.position, angle: CGFloat(angle), speed: 160 * shotSpeed, kind: rollBulletKind(allowLethal: false), art: art)
            }
            if boss.attackTimer <= 0 {
                boss.attackTimer = 2 * tempo
                fireAimed(from: boss.position, speed: 220 * shotSpeed, spread: 0.18, count: min(5, 2 + Int(threat / 3)), art: art)
                events.append(.enemyShot(boss.position))
            }
        }
    }

    private func tickStatus(_ enemy: inout Enemy, dt: Double) {
        var dot = 0.0
        if enemy.status.burnTime > 0 {
            enemy.status.burnTime -= dt
            dot += enemy.status.burnDPS * dt
            enemy.dotType = .fire
        }
        if enemy.status.poisonTime > 0 {
            enemy.status.poisonTime -= dt
            dot += enemy.status.poisonDPS * Double(enemy.status.poisonStacks) * dt
            if enemy.status.burnTime <= 0 { enemy.dotType = .poison }
            if enemy.status.poisonTime <= 0 { enemy.status.poisonStacks = 0 }
        }
        enemy.status.slowTime = max(0, enemy.status.slowTime - dt)
        enemy.status.freezeTime = max(0, enemy.status.freezeTime - dt)
        if dot > 0 {
            enemy.health -= dot
            enemy.dotBuffer += dot
            stats.damageDealt += dot
        }
        enemy.dotTick += dt
        if enemy.dotTick >= 0.45 {
            enemy.dotTick = 0
            if enemy.dotBuffer >= 0.5 {
                events.append(.dot(position: enemy.position, damage: enemy.dotBuffer, type: enemy.dotType))
            }
            enemy.dotBuffer = 0
        }
    }

    // MARK: Bullets

    /// Picks a shot type for the current threat. Armored and heavy shots fade in from a tiny
    /// share past their debut level and grow with every level after; lethal ones only appear
    /// past `lethalScoreThreshold`.
    private func rollBulletKind(allowLethal: Bool) -> BulletKind {
        let roll = rng.range(0...1.0)
        var threshold = 0.0
        if allowLethal, score >= Self.lethalScoreThreshold {
            threshold += min(0.1, 0.025 + 0.01 * Double(score - Self.lethalScoreThreshold) / 100_000)
            if roll < threshold { return .lethal }
        }
        threshold += min(0.22, max(0, 0.015 * (threat - BulletKind.heavyDebut)))
        if roll < threshold { return .heavy }
        threshold += min(0.3, max(0, 0.02 * (threat - BulletKind.armoredDebut)))
        if roll < threshold { return .armored }
        return .standard
    }

    private func fireBullet(from origin: CGPoint, angle: CGFloat, speed: CGFloat, kind: BulletKind, art: String, trick: ShotTrick = .none) {
        guard bullets.count < Self.maxBullets else { return }
        if let intro = kind.introSubtitle, introducedShots.insert(kind).inserted {
            showBanner(title: "NOVO TIRO", subtitle: intro, style: .boss, duration: 2.6)
        }
        // Tricks ride on standard shots only; the tougher kinds keep their plain, readable rules.
        let trick = kind == .standard ? trick : .none
        let tier = trickTier
        if trick != .none { announce(trick, tier: tier) }
        let speed = speed * kind.speedScale
        let launch: CGFloat = switch trick {
        case .fuse: 0.7
        case .surge: 0.45
        case .lunge: 0.35
        default: 1
        }
        let cruise: CGFloat = switch trick {
        case .surge: speed * (1.1 + 0.2 * CGFloat(tier))
        case .lunge: speed * (0.85 + 0.15 * CGFloat(tier))
        default: 0
        }
        bullets.append(Bullet(
            id: makeID(),
            kind: kind,
            position: origin,
            velocity: CGVector(dx: cos(angle) * speed * launch, dy: sin(angle) * speed * launch),
            radius: trick == .shatter || trick == .fuse ? Self.trickRadius : kind.radius,
            health: kind.health,
            art: kind == .standard ? art : kind.art,
            trick: trick,
            tier: tier,
            cruise: cruise
        ))
    }

    private static let trickRadius: CGFloat = 9
    private static let shardRadius: CGFloat = 4.5

    /// Introduces each trick the first time it fires, and calls out every new tier once.
    private func announce(_ trick: ShotTrick, tier: Int) {
        if tier > announcedTier {
            announcedTier = tier
            showBanner(title: "TIROS EVOLUÍRAM", subtitle: tier == 3 ? "NÍVEL MÁXIMO" : "MAIS ESTILHAÇOS, MAIS CURVAS", style: .boss, duration: 2.6)
        } else if let intro = trick.introSubtitle, introducedTricks.insert(intro).inserted {
            showBanner(title: "NOVO TIRO", subtitle: intro, style: .boss, duration: 2.6)
        }
    }

    /// Plain standard shots spawned from a trick shot: shards, forks and mortar rings.
    private func fragments(of bullet: Bullet, angles: [CGFloat], speed: CGFloat, radius: CGFloat, ballID: Int? = nil) -> [Bullet] {
        angles.map { angle in
            Bullet(
                id: makeID(),
                kind: .standard,
                position: bullet.position,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                radius: radius,
                health: 1,
                art: bullet.art,
                lastBallID: ballID
            )
        }
    }

    private func fan(_ count: Int, around angle: CGFloat, spread: CGFloat) -> [CGFloat] {
        let mid = CGFloat(count - 1) / 2
        return (0..<count).map { angle + (CGFloat($0) - mid) * spread }
    }

    /// A broken shatter shot bursts into shards fanned around its flight path, a little faster
    /// than the original. The ball that broke it can't swat them on the same pass.
    private func shatter(_ bullet: Bullet, by ballID: Int) {
        let heading = atan2(bullet.velocity.dy, bullet.velocity.dx)
        let speed = hypot(bullet.velocity.dx, bullet.velocity.dy) * 1.15
        let shards = fragments(of: bullet, angles: fan(2 + bullet.tier, around: heading, spread: 0.4),
                               speed: speed, radius: Self.shardRadius, ballID: ballID)
        bullets += shards.prefix(max(0, Self.maxBullets - bullets.count))
    }

    /// Runs a trick shot's timed behavior. Returns what it turns into when it detonates or
    /// forks (the shot itself is then removed), or nil while it keeps flying.
    private func advanceTrick(_ bullet: inout Bullet, dt: Double) -> [Bullet]? {
        bullet.age += dt
        let tier = CGFloat(bullet.tier)
        let speed = hypot(bullet.velocity.dx, bullet.velocity.dy)
        let heading = atan2(bullet.velocity.dy, bullet.velocity.dx)
        switch bullet.trick {
        case .none, .shatter:
            return nil
        case .fork:
            guard bullet.age >= 0.5 else { return nil }
            return fragments(of: bullet, angles: fan(bullet.tier + 1, around: heading, spread: 0.32),
                             speed: speed, radius: bullet.kind.radius)
        case .fuse:
            guard bullet.age >= ShotTrick.fuseTime else { return nil }
            let count = 4 + 2 * bullet.tier
            let offset = rng.range(0...1.0)
            let ring = (0..<count).map { CGFloat(offset) + .pi * 2 * CGFloat($0) / CGFloat(count) }
            return fragments(of: bullet, angles: ring, speed: 120 * bulletSpeedScale, radius: Self.shardRadius)
        case .homing:
            // Lets go once it's close, so a late sidestep still works.
            let target = atan2(heroY - bullet.position.y, heroX - bullet.position.x)
            guard bullet.age < 0.8 + 0.4 * Double(tier),
                  distance(bullet.position, heroPosition) > 140 else { return nil }
            let turn = remainder(target - heading, 2 * .pi)
            let step = min(abs(turn), (0.9 + 0.4 * tier) * CGFloat(dt))
            let angle = heading + (turn < 0 ? -step : step)
            bullet.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        case .surge:
            guard speed < bullet.cruise else { return nil }
            let boost = min(bullet.cruise / speed, 1 + 1.6 * CGFloat(dt))
            bullet.velocity.dx *= boost
            bullet.velocity.dy *= boost
        case .lunge:
            guard bullet.age >= 0.9 else {
                bullet.velocity.dx *= 1 - 1.5 * CGFloat(dt)
                bullet.velocity.dy *= 1 - 1.5 * CGFloat(dt)
                return nil
            }
            let angle = atan2(heroY - bullet.position.y, heroX - bullet.position.x)
            bullet.velocity = CGVector(dx: cos(angle) * bullet.cruise, dy: sin(angle) * bullet.cruise)
            bullet.trick = .none
        }
        return nil
    }

    /// One shot type per volley so a spread reads as a single threat. A lethal volley collapses
    /// to a single slow shot: it should be dodgeable, never a wall.
    private func fireAimed(from origin: CGPoint, speed: CGFloat, spread: CGFloat, count: Int, art: String, trick: ShotTrick = .none) {
        let kind = rollBulletKind(allowLethal: true)
        let count = kind == .lethal ? 1 : count
        let base = atan2(heroY - origin.y, heroX - origin.x)
        let mid = CGFloat(count - 1) / 2
        for i in 0..<count {
            fireBullet(from: origin, angle: base + (CGFloat(i) - mid) * spread, speed: speed, kind: kind, art: art, trick: trick)
        }
    }

    /// Rings mix shot types bullet by bullet, but never carry lethal shots.
    private func fireRing(from origin: CGPoint, count: Int, speed: CGFloat, offset: Double, art: String, trick: ShotTrick = .none) {
        for i in 0..<count {
            let angle = CGFloat(offset) + CGFloat.pi * 2 * CGFloat(i) / CGFloat(count)
            fireBullet(from: origin, angle: angle, speed: speed, kind: rollBulletKind(allowLethal: false), art: art, trick: trick)
        }
    }

    private func updateBullets(_ dt: Double) {
        let hero = heroPosition
        var damage = 0
        var lethal = false
        let bounds = CGRect(x: -20, y: -40, width: arenaSize.width + 40, height: arenaSize.height + 60)
        bullets.removeAll { !bounds.contains($0.position) }
        var spawned: [Bullet] = []
        for index in bullets.indices.reversed() {
            if bullets[index].trick != .none, let pieces = advanceTrick(&bullets[index], dt: dt) {
                events.append(.shotBurst(bullets[index].position, ring: bullets[index].trick == .fuse))
                bullets.remove(at: index)
                spawned += pieces
                continue
            }
            bullets[index].position.x += bullets[index].velocity.dx * CGFloat(dt)
            bullets[index].position.y += bullets[index].velocity.dy * CGFloat(dt)
            let bullet = bullets[index]
            if distance(bullet.position, hero) < Self.heroRadius + bullet.radius {
                bullets.remove(at: index)
                guard heroInvulnerability <= 0 else { continue }
                if bullet.kind == .lethal {
                    lethal = true
                } else {
                    damage = max(damage, bullet.kind.damage)
                }
            }
        }
        bullets += spawned.prefix(max(0, Self.maxBullets - bullets.count))
        if lethal || damage > 0 {
            let lost = lethal ? lives : min(damage, lives)
            heroInvulnerability = 1.5
            events.append(.heroHurt(damage: lost, lethal: lethal))
            loseLife(count: lost)
        }
    }

    private func loseLife(count: Int) {
        lives = max(0, lives - count)
        combo = 0
        comboTimer = 0
        if count > 0, heroInvulnerability <= 0 {
            heroInvulnerability = 0.6
        }
        if count > 0 {
            // Getting hurt eases the next spawns off right away.
            hurtThisWave = true
            edge = max(edgeFloor, edge - 0.6 * Double(min(count, 3)))
        }
    }

    // MARK: Balls

    private func updateLaunching(_ dt: Double) {
        launchTimer -= dt
        let visible = enemies.filter { $0.position.y + $0.radius > 0 }
        if let point = manualAimPoint {
            aimTargetID = nil
            aimAngle = atan2(point.y - heroY, point.x - heroX)
            guard launchTimer <= 0, !ammo.isEmpty, !visible.isEmpty else { return }
            launchTimer = mods.launchInterval
            let type = ammo.removeFirst()
            ammoCount = ammo.count
            launch(type: type, angle: aimAngle)
            return
        }
        let manual = manualTargetID.flatMap { id in visible.first { $0.id == id } }
        if manual == nil { manualTargetID = nil }
        // Auto-aim only covers the hero's own lane: to hit the rest, move or tap.
        guard let target = manual ?? visible.filter(isInLane).max(by: { $0.position.y < $1.position.y }) else {
            aimTargetID = nil
            aimAngle = -.pi / 2
            guard launchTimer <= 0, !ammo.isEmpty, !visible.isEmpty else { return }
            launchTimer = mods.launchInterval
            let type = ammo.removeFirst()
            ammoCount = ammo.count
            launch(type: type, angle: aimAngle + rng.range(-0.04...0.04))
            return
        }
        aimTargetID = target.id
        let dx = target.position.x - heroX
        let dy = min(target.position.y - heroY, -40)
        aimAngle = atan2(dy, dx)
        guard launchTimer <= 0, !ammo.isEmpty else { return }
        launchTimer = mods.launchInterval
        let type = ammo.removeFirst()
        ammoCount = ammo.count
        launch(type: type, angle: aimAngle + rng.range(-0.04...0.04))
    }

    /// A narrow column above the hero that widens a little with distance.
    private func isInLane(_ enemy: Enemy) -> Bool {
        let reach = enemy.radius + Self.autoAimLane + 0.06 * max(0, heroY - enemy.position.y)
        return abs(enemy.position.x - heroX) <= reach
    }

    private func launch(type: BallType, angle rawAngle: CGFloat) {
        let traits = type.traits(level: ballLevels[type] ?? 1)
        // Keep launches pointing upward even when the target is level with the hero.
        let angle = min(max(rawAngle, -.pi + 0.22), -0.22)
        let speed = mods.ballSpeed * CGFloat(traits.speed)
        let ball = Ball(
            id: makeID(),
            type: type,
            position: CGPoint(x: heroX, y: heroY - 18),
            velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
            pierceLeft: traits.pierce + mods.pierce
        )
        balls.append(ball)
        events.append(.ballLaunched(type: type, origin: ball.position, angle: angle))
    }

    private func updateBalls(_ dt: Double) {
        var returned: [Int] = []
        for index in balls.indices {
            var ball = balls[index]
            ball.age += dt
            ball.immunities.removeAll { $0.until <= time }
            let speed = hypot(ball.velocity.dx, ball.velocity.dy)
            let steps = max(1, Int(ceil(speed * CGFloat(dt) / 9)))
            let stepDT = CGFloat(dt) / CGFloat(steps)
            var didReturn = false

            for _ in 0..<steps {
                ball.position.x += ball.velocity.dx * stepDT
                ball.position.y += ball.velocity.dy * stepDT

                // Walls: left, right and top reflect. The bottom (hero line) returns the ball.
                if ball.position.x < ball.radius {
                    ball.position.x = ball.radius
                    ball.velocity.dx = abs(ball.velocity.dx)
                    ricochet(&ball)
                } else if ball.position.x > arenaSize.width - ball.radius {
                    ball.position.x = arenaSize.width - ball.radius
                    ball.velocity.dx = -abs(ball.velocity.dx)
                    ricochet(&ball)
                }
                if ball.position.y < ball.radius {
                    ball.position.y = ball.radius
                    ball.velocity.dy = abs(ball.velocity.dy)
                    ball.pierceLeft = max(ball.pierceLeft, ball.type.traits(level: ballLevels[ball.type] ?? 1).pierce + mods.pierce)
                    ricochet(&ball)
                }

                collideWithEnemies(&ball)

                // Balls swat breakable enemy bullets out of the air; armored and lethal ones pass through.
                if !bullets.isEmpty {
                    for b in bullets.indices.reversed() {
                        let bullet = bullets[b]
                        guard bullet.kind.isBreakable, bullet.lastBallID != ball.id else { continue }
                        let reach = ball.radius + bullet.radius - 1
                        guard abs(bullet.position.x - ball.position.x) < reach,
                              abs(bullet.position.y - ball.position.y) < reach else { continue }
                        events.append(.bulletBlocked(bullet.position))
                        if bullet.health > 1 {
                            bullets[b].health -= 1
                            bullets[b].lastBallID = ball.id
                        } else {
                            bullets.remove(at: b)
                            if bullet.trick == .shatter { shatter(bullet, by: ball.id) }
                        }
                    }
                }

                // A heated ball falling onto the hero burns them, then is caught as usual.
                if ball.isHot, ball.velocity.dy > 0,
                   distance(ball.position, heroPosition) < Self.heroRadius + ball.radius {
                    if heroInvulnerability <= 0 {
                        heroInvulnerability = 1.5
                        events.append(.heroHurt(damage: 1, lethal: false))
                        loseLife(count: 1)
                    }
                    didReturn = true
                    break
                }

                if ball.velocity.dy > 0, ball.position.y >= heroY {
                    didReturn = true
                    break
                }
            }

            enforceMinimumVertical(&ball)
            if didReturn || ball.age > 14 || ball.position.y > arenaSize.height + 30 {
                returned.append(ball.id)
                if !ball.isTemporary {
                    ammo.append(ball.type)
                }
            }
            balls[index] = ball
        }
        if !returned.isEmpty {
            balls.removeAll { returned.contains($0.id) }
            ammoCount = ammo.count
        }
    }

    private func ricochet(_ ball: inout Ball) {
        ball.wallBounces += 1
        events.append(.wallBounce(ball.position))
        guard !ball.isHot, rng.chance(ricochetHeatChance) else { return }
        ball.isHot = true
        if !hotBallsAnnounced {
            hotBallsAnnounced = true
            showBanner(title: "RICOCHETE EM BRASA", subtitle: "Balas vermelhas ferem você na volta", style: .boss, duration: 2.6)
        }
    }

    private func enforceMinimumVertical(_ ball: inout Ball) {
        let speed = hypot(ball.velocity.dx, ball.velocity.dy)
        guard speed > 0 else { return }
        let minimum = speed * 0.22
        if abs(ball.velocity.dy) < minimum {
            let sign: CGFloat = ball.velocity.dy >= 0 ? 1 : -1
            ball.velocity.dy = minimum * sign
            let dx = sqrt(max(0, speed * speed - minimum * minimum))
            ball.velocity.dx = ball.velocity.dx >= 0 ? dx : -dx
        }
    }

    private func collideWithEnemies(_ ball: inout Ball) {
        for index in enemies.indices {
            let enemy = enemies[index]
            guard enemy.isAlive else { continue }
            let reach = ball.radius + enemy.radius
            let dx = ball.position.x - enemy.position.x
            let dy = ball.position.y - enemy.position.y
            guard abs(dx) < reach, abs(dy) < reach else { continue }
            let dist = sqrt(dx * dx + dy * dy)
            guard dist < reach else { continue }
            if ball.immunities.contains(where: { $0.id == enemy.id }) { continue }

            ball.immunities.append((enemy.id, time + 0.2))
            hit(enemyIndex: index, with: ball)

            if ball.pierceLeft > 0 {
                ball.pierceLeft -= 1
            } else {
                let normal = dist > 0.001
                    ? CGVector(dx: dx / dist, dy: dy / dist)
                    : CGVector(dx: 0, dy: 1)
                let dot = ball.velocity.dx * normal.dx + ball.velocity.dy * normal.dy
                if dot < 0 {
                    ball.velocity.dx -= 2 * dot * normal.dx
                    ball.velocity.dy -= 2 * dot * normal.dy
                }
                ball.position = CGPoint(
                    x: enemy.position.x + normal.dx * (reach + 0.5),
                    y: enemy.position.y + normal.dy * (reach + 0.5)
                )
                return
            }
        }
    }

    // MARK: Damage

    private func hit(enemyIndex index: Int, with ball: Ball) {
        let traits = ball.type.traits(level: ballLevels[ball.type] ?? 1)
        var damage = baseDamage * mods.damage * traits.damage
        damage *= 1 + mods.bankShot * Double(min(5, ball.wallBounces))
        if lives == 1 { damage *= 1 + mods.lastStand }
        if ball.isTemporary { damage *= 0.6 }
        let critical = rng.chance(mods.critChance)
        if critical { damage *= mods.critMultiplier }

        let enemy = enemies[index]
        // Shielded enemies block shots coming from below (ball travelling upward).
        if enemy.kind == .shielded, ball.velocity.dy < 0, ball.position.y > enemy.position.y {
            damage *= 0.2
            events.append(.shieldBlock(CGPoint(x: enemy.position.x, y: enemy.position.y + enemy.radius)))
        }

        damageEnemy(at: index, amount: damage, type: ball.type)
        events.append(.hit(enemyID: enemy.id, position: ball.position, damage: damage, critical: critical, type: ball.type))
        applyStatus(traits, to: index, sourceDamage: baseDamage * mods.damage, type: ball.type)

        let origin = enemies[index].position
        let sourceDamage = baseDamage * mods.damage

        if traits.chains > 0 {
            var from = origin
            var visited: Set<Int> = [enemy.id]
            for _ in 0..<traits.chains {
                let candidate = enemies.indices
                    .filter { enemies[$0].isAlive && !visited.contains(enemies[$0].id) }
                    .map { ($0, distance(enemies[$0].position, from)) }
                    .filter { $0.1 < 150 }
                    .min { $0.1 < $1.1 }
                guard let (targetIndex, _) = candidate else { break }
                let target = enemies[targetIndex]
                visited.insert(target.id)
                let chainDamage = sourceDamage * traits.chainDamage
                damageEnemy(at: targetIndex, amount: chainDamage, type: ball.type)
                applyStatus(traits, to: targetIndex, sourceDamage: sourceDamage, type: ball.type)
                events.append(.chain(from: from, to: target.position, type: ball.type))
                events.append(.hit(enemyID: target.id, position: target.position, damage: chainDamage, critical: false, type: ball.type))
                from = target.position
            }
        }

        if traits.aoeRadius > 0 {
            let aoeDamage = sourceDamage * traits.aoeDamage * (critical ? 1.5 : 1)
            for other in enemies.indices where enemies[other].id != enemy.id && enemies[other].isAlive {
                let d = distance(enemies[other].position, origin)
                guard d < traits.aoeRadius + enemies[other].radius else { continue }
                damageEnemy(at: other, amount: aoeDamage, type: ball.type)
                if traits.aoeAppliesStatus {
                    applyStatus(traits, to: other, sourceDamage: sourceDamage, type: ball.type)
                }
                events.append(.hit(enemyID: enemies[other].id, position: enemies[other].position, damage: aoeDamage, critical: false, type: ball.type))
            }
            events.append(.explosion(position: origin, radius: traits.aoeRadius, type: ball.type))
        }
    }

    private func applyStatus(_ traits: BallTraits, to index: Int, sourceDamage: Double, type: BallType) {
        var enemy = enemies[index]
        if traits.burnFactor > 0 {
            enemy.status.burnDPS = max(enemy.status.isBurning ? enemy.status.burnDPS : 0, sourceDamage * traits.burnFactor)
            enemy.status.burnTime = max(enemy.status.burnTime, traits.burnDuration)
        }
        if traits.slow > 0 {
            enemy.status.slow = max(enemy.status.isSlowed ? enemy.status.slow : 0, min(0.85, traits.slow + mods.chill * 0.5))
            enemy.status.slowTime = max(enemy.status.slowTime, traits.slowDuration)
        }
        if traits.freezeChance > 0, enemy.kind != .boss, !enemy.status.isFrozen, rng.chance(traits.freezeChance) {
            enemy.status.freezeTime = traits.freezeDuration
            events.append(.freeze(enemy.position))
        }
        if traits.poisonStacks > 0 {
            enemy.status.poisonStacks = min(6, (enemy.status.isPoisoned ? enemy.status.poisonStacks : 0) + traits.poisonStacks)
            enemy.status.poisonDPS = max(enemy.status.poisonDPS, sourceDamage * traits.poisonFactor)
            enemy.status.poisonTime = 4
        }
        if traits.spreadsPoison {
            enemy.plagueCarrier = true
        }
        enemies[index] = enemy
    }

    private func damageEnemy(at index: Int, amount: Double, type: BallType) {
        guard enemies[index].isAlive else { return }
        enemies[index].health -= amount
        enemies[index].lastHitType = type
        stats.damageDealt += amount
    }

    private func processDeaths() {
        guard enemies.contains(where: { !$0.isAlive }) else { return }
        let dead = enemies.filter { !$0.isAlive }
        enemies.removeAll { !$0.isAlive }

        for enemy in dead {
            stats.kills += 1
            combo += 1
            comboTimer = 2.2
            if combo > bestCombo {
                bestCombo = combo
                stats.bestCombo = combo
            }
            if [10, 25, 50, 100, 200, 300, 500].contains(combo) {
                events.append(.comboMilestone(combo))
                showBanner(title: "COMBO x\(combo)", subtitle: comboTitle(combo), style: .combo, duration: 1.1)
            }

            let reward = Double(enemy.kind.reward) * (enemy.isElite ? 2.5 : 1)
            score += Int(reward * comboMultiplier * (1 + mods.scoreBonus))
            let xp = Int((Double(enemy.kind.experience) * (enemy.isElite ? 2.5 : 1)).rounded())
            gainExperience(xp)
            gainPulseEnergy((enemy.isElite || enemy.kind == .boss) ? 0.09 : 0.04)

            events.append(.enemyKilled(position: enemy.position, kind: enemy.kind, elite: enemy.isElite, radius: enemy.radius, experience: xp))

            switch enemy.kind {
            case .splitter:
                for side: CGFloat in [-1, 1] {
                    let id = spawn(kind: .runner, elite: false, at: CGPoint(x: enemy.position.x + side * 14, y: enemy.position.y))
                    if let i = enemies.firstIndex(where: { $0.id == id }) {
                        enemies[i].health *= 0.6
                    }
                }
            case .bomber:
                fireRing(from: enemy.position, count: 6 + 2 * trickTier, speed: 150, offset: rng.range(0...1.0),
                         art: enemy.kind.shotArt, trick: enemy.kind.shotTrick)
            case .boss:
                stats.bossesDefeated += 1
                bossHealthRatio = nil
                bullets.removeAll()
                events.append(.bossDefeated(enemy.position))
                showBanner(title: "CHEFE DERROTADO", subtitle: "+\(Int(reward))", style: .clear, duration: 2)
            default:
                break
            }

            if enemy.plagueCarrier || enemy.lastHitType == .plague {
                for other in enemies.indices where distance(enemies[other].position, enemy.position) < 95 {
                    enemies[other].status.poisonStacks = min(6, enemies[other].status.poisonStacks + 2)
                    enemies[other].status.poisonDPS = max(enemies[other].status.poisonDPS, baseDamage * mods.damage * 0.4)
                    enemies[other].status.poisonTime = 4
                    enemies[other].plagueCarrier = true
                }
            }

            let lifesteal = enemy.lastHitType.traits(level: ballLevels[enemy.lastHitType] ?? 1).lifestealKills
            if lifesteal > 0 {
                vampireKills += 1
                if vampireKills >= lifesteal {
                    vampireKills = 0
                    heal()
                }
            }
            if mods.lifeStealEvery > 0 {
                killsSinceHeal += 1
                if killsSinceHeal >= mods.lifeStealEvery {
                    killsSinceHeal = 0
                    heal()
                }
            }
        }
        // Splitter children or plague may have been killed by nothing yet, but chained deaths
        // (e.g. a pulse killing a splitter) are already handled because children spawn alive.
    }

    private func gainPulseEnergy(_ base: Double) {
        guard pulseCooldown <= 0, specialEnergy < 1 else { return }
        specialEnergy = min(1, specialEnergy + base * pulseChargeScale * mods.pulseGain)
        if specialEnergy >= 1 {
            events.append(.pulseReady)
        }
    }

    private func updatePulseCooldown(_ dt: Double) {
        guard pulseCooldown > 0 else { return }
        pulseCooldown = max(0, pulseCooldown - dt)
        let seconds = Int(pulseCooldown.rounded(.up))
        if seconds != pulseCooldownSeconds { pulseCooldownSeconds = seconds }
    }

    private func heal() {
        let cap = 3 + config.labLevel(.vitality) + (passiveLevels[.fortify] ?? 0) + 2
        guard lives < cap else { return }
        lives += 1
        events.append(.heal)
    }

    private func comboTitle(_ value: Int) -> String {
        switch value {
        case ..<25: "Aquecendo!"
        case ..<50: "Imparável!"
        case ..<100: "Massacre!"
        case ..<200: "LENDÁRIO!"
        default: "DIVINO!"
        }
    }

    private func updateCombo(_ dt: Double) {
        guard combo > 0 else { return }
        comboTimer -= dt
        if comboTimer <= 0 {
            combo = 0
        }
    }

    private func gainExperience(_ amount: Int) {
        experience += Int((Double(amount) * mods.xpGain).rounded())
        while experience >= experienceNeeded {
            experience -= experienceNeeded
            level += 1
            stats.level = level
            pendingLevelUps += 1
            events.append(.levelUp(level))
        }
    }

    private func updateBossBar() {
        guard let boss = enemies.first(where: { $0.kind == .boss }) else {
            if bossHealthRatio != nil { bossHealthRatio = nil }
            return
        }
        let ratio = max(0, boss.health / boss.maxHealth)
        if bossHealthRatio == nil || abs((bossHealthRatio ?? 0) - ratio) > 0.004 {
            bossHealthRatio = ratio
        }
    }

    // MARK: Banner

    private func showBanner(title: String, subtitle: String?, style: BannerStyle, duration: Double) {
        banner = Banner(id: nextBannerID, title: title, subtitle: subtitle, style: style)
        nextBannerID += 1
        bannerTimer = duration
    }

    private func updateBanner(_ dt: Double) {
        guard banner != nil else { return }
        bannerTimer -= dt
        if bannerTimer <= 0 { banner = nil }
    }

    private func updateBossIntro(_ dt: Double) {
        guard let elapsed = bossIntroElapsed else { return }
        bossIntroElapsed = elapsed + dt < Self.bossIntroDuration ? elapsed + dt : nil
    }

    // MARK: Upgrades

    private func presentUpgrade(_ context: UpgradeContext) {
        if context == .levelUp { pendingLevelUps = max(0, pendingLevelUps - 1) }
        let choices = makeChoices(context)
        guard !choices.isEmpty else {
            if phase != .playing { phase = .playing }
            return
        }
        upgradeContext = context
        upgradeChoices = choices
        upgradeLockRemaining = 0.35
        phase = .choosingUpgrade
        dragAnchor = nil
    }

    private func makeChoices(_ context: UpgradeContext) -> [UpgradeOption] {
        var result: [UpgradeOption] = []
        let chest = context == .bossChest

        // Fusions are always offered once both ingredients are maxed.
        let fusions = BallType.recipes.filter { a, b, fused in
            ballLevels[a] == BallType.maxLevel && ballLevels[b] == BallType.maxLevel && ballLevels[fused] == nil
        }
        if let fusion = fusions.randomElement(using: &rng) {
            result.append(.fuse(fusion.2))
        }

        var pool: [(UpgradeOption, Double)] = []
        for (type, lvl) in ballLevels where !type.isFusion && lvl < BallType.maxLevel {
            pool.append((.levelBall(type), chest ? 12 : 10))
        }
        if specialSlotsUsed < mods.maxSlots {
            for type in BallType.elemental where ballLevels[type] == nil {
                pool.append((.newBall(type), 5))
            }
        }

        // Early on, a new ball is the most exciting pick: always offer one.
        if specialSlotsUsed < min(2, mods.maxSlots), result.count < 3 {
            let newBalls = pool.indices.filter { if case .newBall = pool[$0].0 { true } else { false } }
            if let index = newBalls.randomElement(using: &rng) {
                result.append(pool.remove(at: index).0)
            }
        }
        for passive in Passive.allCases where (passiveLevels[passive] ?? 0) < passive.maxLevel {
            let weight: Double
            switch passive.rarity {
            case .common: weight = chest ? 3 : 8
            case .rare: weight = (wave >= 2 || chest) ? (chest ? 9 : 5) : 0
            case .legendary: weight = (wave >= 4 || chest) ? (chest ? 6 : 2) : 0
            case .fusion: weight = 0
            }
            if weight > 0 { pool.append((.passive(passive), weight)) }
        }

        while result.count < 3, !pool.isEmpty {
            let total = pool.reduce(0) { $0 + $1.1 }
            var roll = rng.range(0...total)
            var pickIndex = pool.count - 1
            for (i, entry) in pool.enumerated() {
                roll -= entry.1
                if roll <= 0 {
                    pickIndex = i
                    break
                }
            }
            result.append(pool.remove(at: pickIndex).0)
        }
        return result
    }

    private func apply(_ option: UpgradeOption) {
        switch option {
        case .passive(let passive):
            passiveLevels[passive, default: 0] += 1
            switch passive {
            case .fortify:
                lives += 1
                gainPulseEnergy(0.2 / pulseChargeScale)
                events.append(.heal)
            case .extraBall:
                basicBallCount += 1
            default:
                break
            }
            recomputeModifiers()
        case .newBall(let type):
            ballLevels[type] = 1
            stats.discoveredBalls.insert(type)
        case .levelBall(let type):
            ballLevels[type] = min(BallType.maxLevel, (ballLevels[type] ?? 1) + 1)
        case .fuse(let fused):
            guard let (a, b) = fused.recipe else { return }
            ballLevels[a] = nil
            ballLevels[b] = nil
            ballLevels[fused] = 1
            stats.fusions += 1
            stats.discoveredBalls.insert(fused)
            events.append(.fusion(fused))
            showBanner(title: "FUSÃO!", subtitle: fused.title, style: .fusion, duration: 2)
        }
        syncRoster()
    }

    private func recomputeModifiers() {
        var m = Modifiers()
        func lvl(_ p: Passive) -> Double { Double(passiveLevels[p] ?? 0) }

        m.damage *= pow(1.25, lvl(.heavyCore)) * pow(0.92, lvl(.rapidVolley))
        m.damage *= 1 + 0.08 * Double(config.labLevel(.power))
        m.ballSpeed *= CGFloat(pow(0.92, lvl(.heavyCore)) * pow(1.2, lvl(.overdrive)))
        m.launchInterval *= pow(0.9, lvl(.overdrive)) * pow(0.75, lvl(.rapidVolley))
        m.critChance += 0.12 * lvl(.criticalMass)
        m.pierce = Int(lvl(.piercingRounds))
        m.pulseDamage = pow(1.4, lvl(.pulseReactor))
        m.pulseGain = pow(1.2, lvl(.pulseReactor))
        m.chill = 0.15 * lvl(.cryoCore)
        m.enemyHealth = pow(1.1, lvl(.cryoCore))
        m.scoreBonus = 0.5 * lvl(.bountyHunter)
        m.coreGain = (1 + 0.25 * lvl(.bountyHunter)) * (1 + 0.1 * Double(config.labLevel(.fortune)))
        m.eliteBonus = 6 * lvl(.bountyHunter)
        if let steal = passiveLevels[.lifeSteal], steal > 0 {
            m.lifeStealEvery = max(12, 25 - 6 * (steal - 1))
        }
        m.lastStand = 0.8 * lvl(.lastStand)
        m.bankShot = 0.12 * lvl(.bankShot)
        m.xpGain = 1 + 0.1 * Double(config.labLevel(.wisdom))
        m.maxSlots = 4 + config.labLevel(.arsenal)

        switch config.character {
        case .vanguard, .pyra:
            break
        case .ricochet:
            m.bankShot += 0.12
            m.ballSpeed *= 1.15
            m.damage *= 0.9
        case .glacius:
            m.chill += 0.1
            m.pulseGain *= 1.15
        }
        mods = m
    }

    /// Reconciles the balls the player owns (ammo + in flight) with their inventory.
    private func syncRoster() {
        var desired: [BallType: Int] = [.basic: basicBallCount]
        for (type, lvl) in ballLevels {
            desired[type] = type.isFusion ? 3 : (lvl >= BallType.maxLevel ? 2 : 1)
        }
        var current: [BallType: Int] = [:]
        for type in ammo { current[type, default: 0] += 1 }
        for ball in balls where !ball.isTemporary { current[ball.type, default: 0] += 1 }

        var excessInFlight: [Int] = []
        var shortages: [BallType] = []
        for type in Set(desired.keys).union(current.keys) {
            var diff = (desired[type] ?? 0) - (current[type] ?? 0)
            while diff < 0 {
                if let i = ammo.firstIndex(of: type) {
                    ammo.remove(at: i)
                } else if let i = balls.firstIndex(where: { $0.type == type && !$0.isTemporary && !excessInFlight.contains($0.id) }) {
                    excessInFlight.append(balls[i].id)
                }
                diff += 1
            }
            if diff > 0 {
                shortages += Array(repeating: type, count: diff)
            }
        }
        // Balls already in the air morph into their new type (e.g. after a fusion).
        for type in shortages {
            if let id = excessInFlight.popLast(), let i = balls.firstIndex(where: { $0.id == id }) {
                balls[i].type = type
            } else {
                ammo.insert(type, at: min(ammo.count, Int(rng.range(0...Double(ammo.count)))))
            }
        }
        for id in excessInFlight {
            if let i = balls.firstIndex(where: { $0.id == id }) {
                balls[i].isTemporary = true
            }
        }
        ammoCount = ammo.count
    }

    // MARK: Hero gear

    /// The armor piece an upgrade grants. Its rarity is the upgrade's own, promoted to
    /// legendary when the pick maxes the passive or the ball.
    func gearPreview(for option: UpgradeOption) -> GearPreview {
        let slot = option.gearSlot
        var rarity = option.rarity
        let maxes: Bool = switch option {
        case .passive(let p): (passiveLevels[p] ?? 0) + 1 >= p.maxLevel
        case .levelBall(let b): (ballLevels[b] ?? 1) + 1 >= BallType.maxLevel
        case .newBall, .fuse: false
        }
        if maxes, rarity < .legendary {
            rarity = .legendary
        }
        let current = heroGear[slot]
        return GearPreview(slot: slot, rarity: rarity, isUpgrade: current.map { rarity > $0 } ?? true)
    }

    private func equipGear(_ slot: HeroGearSlot, rarity: UpgradeRarity) {
        heroGear[slot] = rarity
        events.append(.gearEquipped(slot: slot, rarity: rarity))
        guard heroGear.count == HeroGearSlot.allCases.count, let lowest = heroGear.values.min() else { return }
        if gearSetRarity.map({ lowest > $0 }) ?? true {
            gearSetRarity = lowest
            events.append(.gearSetCompleted(lowest))
            showBanner(title: "ARMADURA COMPLETA", subtitle: lowest.label, style: .fusion, duration: 2.2)
        }
    }

    // MARK: End of run

    private func finishRun() {
        stats.score = score
        stats.level = level
        stats.wave = wave
        stats.bestCombo = bestCombo
        let base = Double((wave - 1) * 6 + stats.kills / 3 + stats.bossesDefeated * 30)
        stats.coresEarned = Int((base * mods.coreGain).rounded())
        finalStats = stats
        bossHealthRatio = nil
        banner = nil
        bossIntroElapsed = nil
        upgradeChoices = []
        phase = .gameOver
        events.append(.gameOver)
    }

    // MARK: Helpers

    private func makeID() -> Int {
        nextID += 1
        return nextID
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
