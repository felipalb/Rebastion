import SwiftUI
import UIKit

enum GamePhase: Equatable {
    case menu
    case playing
    case paused
    case choosingUpgrade
    case gameOver
}

// MARK: - Enemies

enum EnemyKind: CaseIterable, Equatable {
    case grunt
    case runner
    case tank
    case splitter
    case shooter
    case shielded
    case bomber
    case boss

    var baseHealth: Double {
        switch self {
        case .grunt: 20
        case .runner: 12
        case .tank: 55
        case .splitter: 32
        case .shooter: 26
        case .shielded: 45
        case .bomber: 18
        case .boss: 760
        }
    }

    var speedScale: Double {
        switch self {
        case .grunt: 1
        case .runner: 1.8
        case .tank: 0.6
        case .splitter: 0.9
        case .shooter: 0.85
        case .shielded: 0.7
        case .bomber: 1.5
        case .boss: 0.5
        }
    }

    /// How a flyer travels down the arena. `surge` is how much each wingbeat speeds up and
    /// slows down the descent (the average speed stays the same), `beat` its rate in radians
    /// per second; `glide` is the peak sideways speed of a lazy weave and `weave` its rate.
    /// Shooters and bosses hold a post and move on their own.
    var flight: (surge: Double, beat: Double, glide: CGFloat, weave: Double) {
        switch self {
        case .grunt: (0.35, 5, 16, 1.3)
        case .runner: (0.2, 4, 46, 1.6)
        case .tank, .shielded: (0.12, 2, 10, 0.8)
        case .splitter: (0.5, 3.2, 12, 1)
        case .bomber: (0.25, 6, 34, 2.1)
        case .shooter, .boss: (0, 0, 0, 0)
        }
    }

    var radius: CGFloat {
        switch self {
        case .grunt: 18
        case .runner: 13
        case .tank: 24
        case .splitter: 19
        case .shooter: 17
        case .shielded: 22
        case .bomber: 15
        case .boss: 40
        }
    }

    var reward: Int {
        switch self {
        case .grunt: 25
        case .runner: 22
        case .tank: 48
        case .splitter: 42
        case .shooter: 45
        case .shielded: 55
        case .bomber: 35
        case .boss: 400
        }
    }

    var experience: Int {
        switch self {
        case .grunt: 4
        case .runner: 3
        case .tank: 8
        case .splitter: 6
        case .shooter: 6
        case .shielded: 8
        case .bomber: 5
        case .boss: 60
        }
    }

    /// Prefix of the animation frames (`<base>_<Action>_0N`). Bosses use `BossVariant.animationBase`.
    var animationBase: String {
        switch self {
        case .grunt: "SpriteGrunt"
        case .runner: "SpriteRunner"
        case .tank, .shielded: "SpriteTank"
        case .splitter: "SpriteSplitter"
        case .shooter: "SpriteShooter"
        case .bomber: "SpriteBomber"
        case .boss: "SpriteBoss"
        }
    }

    /// Tint applied over the shared sprite so variants read differently.
    var tint: UIColor? {
        switch self {
        case .shielded: UIColor(red: 0.35, green: 0.55, blue: 1, alpha: 1)
        default: nil
        }
    }

    var particleColor: UIColor {
        switch self {
        case .grunt: Neon.violet
        case .runner: Neon.coral
        case .tank: UIColor.orange
        case .splitter: Neon.lime
        case .shooter: Neon.cyan
        case .shielded: UIColor(red: 0.35, green: 0.55, blue: 1, alpha: 1)
        case .bomber: UIColor.orange
        case .boss: Neon.coral
        }
    }

    /// Art for this enemy's own shots (`Projectiles/Enemies`, frames `<art>_01…04`).
    var shotArt: String {
        switch self {
        case .grunt: "SpriteShot_Grunt"
        case .runner: "SpriteShot_Runner"
        case .tank, .shielded: "SpriteShot_Tank"
        case .splitter: "SpriteShot_Splitter"
        case .shooter: "SpriteShot_Shooter"
        case .bomber: "SpriteShot_Bomber"
        case .boss: "SpriteShot_BossVoid"
        }
    }

    /// Signature behavior of this enemy's standard shots.
    var shotTrick: ShotTrick {
        switch self {
        case .grunt: .shatter
        case .tank: .fuse
        case .splitter: .fork
        case .shielded: .homing
        case .shooter: .surge
        case .bomber: .lunge
        case .runner, .boss: .none
        }
    }

    /// Enemies that stop at a given height and attack instead of marching down.
    var holdsPosition: Bool { self == .shooter || self == .boss }
}

/// Bosses rotate every boss wave; each has its own art and opening attack.
enum BossVariant: CaseIterable, Equatable {
    case void
    case hydra
    case mecha
    case seraph

    static func forWave(_ wave: Int) -> BossVariant {
        allCases[max(0, wave / 5 - 1) % allCases.count]
    }

    var title: String {
        switch self {
        case .void: "SOBERANO DO VAZIO"
        case .hydra: "HIDRA NEON"
        case .mecha: "COLOSSO MECHA"
        case .seraph: "SERAFIM DE LÂMINAS"
        }
    }

    var animationBase: String {
        switch self {
        case .void: "SpriteBoss"
        case .hydra: "SpriteBossHydra"
        case .mecha: "SpriteBossMecha"
        case .seraph: "SpriteBossSeraph"
        }
    }

    var shotArt: String {
        switch self {
        case .void: "SpriteShot_BossVoid"
        case .hydra: "SpriteShot_BossHydra"
        case .mecha: "SpriteShot_BossMecha"
        case .seraph: "SpriteShot_BossSeraph"
        }
    }

    var color: UIColor {
        switch self {
        case .void: Neon.magenta
        case .hydra: Neon.lime
        case .mecha: UIColor.orange
        case .seraph: Neon.cyan
        }
    }
}

enum WaveModifier: CaseIterable, Equatable {
    case standard
    case frenzy
    case armored
    case swarm

    var title: String {
        switch self {
        case .standard: "INVASÃO"
        case .frenzy: "FRENESI"
        case .armored: "BLINDADOS"
        case .swarm: "ENXAME"
        }
    }
}

// MARK: - Enemy shots

/// What an enemy's own standard shot does besides flying straight. Every trick grows a tier as
/// the threat climbs (see `GameEngine.trickTier`), so the same enemy keeps getting nastier.
enum ShotTrick: Equatable {
    case none
    /// Grunt. Bursts into 3/4/5 shards when a ball breaks it.
    case shatter
    /// Tank. Slow mortar that blows into a ring of 6/8/10 shards unless broken first.
    case fuse
    /// Splitter. Forks into 2/3/4 shots mid-flight.
    case fork
    /// Shielded. Steers toward the hero for a while, harder each tier.
    case homing
    /// Shooter. Leaves slow, then accelerates well past normal speed.
    case surge
    /// Bomber's death ring. Drifts out, stops, then darts at the hero.
    case lunge

    /// Seconds before a mortar blows.
    static let fuseTime = 1.3

    /// Banner shown the first time a run meets this trick.
    var introSubtitle: String? {
        switch self {
        case .none: nil
        case .shatter: "SE ESTILHAÇA AO SER ATINGIDO"
        case .fuse: "EXPLODE EM ANEL: ACERTE ANTES!"
        case .fork: "SE BIFURCA NO AR"
        case .homing: "TELEGUIADO: PERSEGUE VOCÊ"
        case .surge: "ACELERA NO CAMINHO"
        case .lunge: "PARA E DISPARA EM VOCÊ"
        }
    }
}

/// Enemy projectile types. Tougher kinds unlock as the run goes deeper.
enum BulletKind: CaseIterable, Equatable {
    /// Red star. Balls swat it out of the air.
    case standard
    /// Violet, blunt star. Balls pass straight through it: dodge it or clear it with the Pulse.
    case armored
    /// Big orange star. Takes two ball hits to break and costs two lives.
    case heavy
    /// Black star seen only past `GameEngine.lethalScoreThreshold`. Unbreakable and ends the run.
    case lethal

    /// Threat level (see `GameEngine.threat`) where each kind starts creeping into volleys; its
    /// share then grows a little with every level. Lethal is gated by score instead.
    static let armoredDebut = 5.0
    static let heavyDebut = 11.0

    /// Banner shown the first time a run meets this kind.
    var introSubtitle: String? {
        switch self {
        case .standard: nil
        case .armored: "ROXOS: INQUEBRÁVEIS, DESVIE!"
        case .heavy: "LARANJA: 2 GOLPES · −2 ♥"
        case .lethal: nil
        }
    }

    var isBreakable: Bool { self == .standard || self == .heavy }

    /// Art for the tougher kinds (`Projectiles/Bullets`). Standard shots use the shooter's own
    /// art instead; the others keep a shared look so their rules read at a glance.
    var art: String {
        switch self {
        case .standard: "SpriteBullet_Standard"
        case .armored: "SpriteBullet_Armored"
        case .heavy: "SpriteBullet_Heavy"
        case .lethal: "SpriteBullet_Lethal"
        }
    }

    var damage: Int {
        switch self {
        case .standard, .armored: 1
        case .heavy: 2
        case .lethal: 0
        }
    }

    var health: Int { self == .heavy ? 2 : 1 }

    var radius: CGFloat {
        switch self {
        case .standard: 7
        case .armored: 8
        case .heavy: 10
        case .lethal: 11
        }
    }

    var speedScale: CGFloat {
        switch self {
        case .standard: 1
        case .armored: 0.9
        case .heavy: 0.75
        case .lethal: 0.6
        }
    }
}

// MARK: - Balls

struct BallTraits {
    var damage = 1.0
    var speed = 1.0
    var pierce = 0
    var burnFactor = 0.0
    var burnDuration = 0.0
    var slow = 0.0
    var slowDuration = 0.0
    var freezeChance = 0.0
    var freezeDuration = 0.0
    var chains = 0
    var chainDamage = 0.0
    var poisonStacks = 0
    var poisonFactor = 0.0
    var aoeRadius: CGFloat = 0
    var aoeDamage = 0.0
    var aoeAppliesStatus = false
    var lifestealKills = 0
    var spreadsPoison = false
}

enum BallType: String, CaseIterable, Codable, Identifiable {
    case basic
    case fire
    case ice
    case lightning
    case poison
    case explosive
    case ghost
    case vampire
    case steam
    case plasma
    case glacier
    case toxicBomb
    case specter
    case napalm
    case plague

    var id: String { rawValue }

    static let elemental: [BallType] = [.fire, .ice, .lightning, .poison, .explosive, .ghost, .vampire]
    static let maxLevel = 3

    var gearSlot: HeroGearSlot {
        switch self {
        case .lightning, .glacier: .ionCrown
        case .fire, .explosive, .napalm: .shoulderPods
        case .basic, .steam: .starCore
        case .ghost, .vampire, .specter: .voidCape
        case .ice, .plasma: .reactorHalo
        case .poison, .toxicBomb, .plague: .plasmaOrbit
        }
    }

    /// (ingredient A, ingredient B, result). Both ingredients must be at max level.
    static let recipes: [(BallType, BallType, BallType)] = [
        (.fire, .ice, .steam),
        (.fire, .lightning, .plasma),
        (.ice, .lightning, .glacier),
        (.poison, .explosive, .toxicBomb),
        (.ghost, .vampire, .specter),
        (.fire, .explosive, .napalm),
        (.poison, .ghost, .plague),
    ]

    var isFusion: Bool { BallType.recipes.contains { $0.2 == self } }

    var recipe: (BallType, BallType)? {
        BallType.recipes.first { $0.2 == self }.map { ($0.0, $0.1) }
    }

    var title: String {
        switch self {
        case .basic: "Tiro Básico"
        case .fire: "Tiro Ígneo"
        case .ice: "Tiro Glacial"
        case .lightning: "Tiro Voltaico"
        case .poison: "Tiro Tóxico"
        case .explosive: "Tiro Detonador"
        case .ghost: "Tiro Fantasma"
        case .vampire: "Tiro Vampírico"
        case .steam: "Névoa Escaldante"
        case .plasma: "Núcleo de Plasma"
        case .glacier: "Tempestade Glacial"
        case .toxicBomb: "Bomba Tóxica"
        case .specter: "Espectro Faminto"
        case .napalm: "Napalm Neon"
        case .plague: "Praga Errante"
        }
    }

    var detail: String {
        switch self {
        case .basic: "Ricocheteia e volta. Simples e confiável."
        case .fire: "Incendeia o alvo: dano contínuo por 3s."
        case .ice: "Desacelera inimigos e pode congelá-los."
        case .lightning: "Raios saltam para inimigos próximos."
        case .poison: "Acumula veneno que corrói com o tempo."
        case .explosive: "Explode no impacto, atingindo a área."
        case .ghost: "Atravessa vários inimigos antes de quicar."
        case .vampire: "Abates com ele restauram vida."
        case .steam: "Explosões de vapor que queimam e desaceleram."
        case .plasma: "Raios em cadeia que incendeiam e explodem."
        case .glacier: "Raios congelantes que saltam entre alvos."
        case .toxicBomb: "Explosões que espalham veneno pesado."
        case .specter: "Atravessa quase tudo e drena vida."
        case .napalm: "Explosões enormes que deixam tudo em chamas."
        case .plague: "Veneno que contagia ao matar o hospedeiro."
        }
    }

    var symbol: String {
        switch self {
        case .basic: "circle.fill"
        case .fire: "flame.fill"
        case .ice: "snowflake"
        case .lightning: "bolt.fill"
        case .poison: "drop.fill"
        case .explosive: "burst.fill"
        case .ghost: "circle.dashed"
        case .vampire: "heart.fill"
        case .steam: "cloud.fill"
        case .plasma: "atom"
        case .glacier: "tornado"
        case .toxicBomb: "aqi.high"
        case .specter: "sparkles"
        case .napalm: "flame.circle.fill"
        case .plague: "allergens"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .basic: Neon.cyan
        case .fire: UIColor(red: 1, green: 0.48, blue: 0.12, alpha: 1)
        case .ice: UIColor(red: 0.55, green: 0.88, blue: 1, alpha: 1)
        case .lightning: UIColor(red: 1, green: 0.93, blue: 0.25, alpha: 1)
        case .poison: UIColor(red: 0.45, green: 1, blue: 0.3, alpha: 1)
        case .explosive: UIColor(red: 1, green: 0.28, blue: 0.3, alpha: 1)
        case .ghost: UIColor(red: 0.85, green: 0.85, blue: 1, alpha: 1)
        case .vampire: UIColor(red: 0.85, green: 0.1, blue: 0.45, alpha: 1)
        case .steam: UIColor(red: 1, green: 0.75, blue: 0.85, alpha: 1)
        case .plasma: UIColor(red: 1, green: 0.35, blue: 1, alpha: 1)
        case .glacier: UIColor(red: 0.3, green: 0.75, blue: 1, alpha: 1)
        case .toxicBomb: UIColor(red: 0.75, green: 1, blue: 0.1, alpha: 1)
        case .specter: UIColor(red: 0.7, green: 0.45, blue: 1, alpha: 1)
        case .napalm: UIColor(red: 1, green: 0.6, blue: 0, alpha: 1)
        case .plague: UIColor(red: 0.2, green: 0.9, blue: 0.6, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    func traits(level: Int) -> BallTraits {
        let lvl = max(1, level)
        let scale = 1 + 0.35 * Double(lvl - 1)
        var t = BallTraits()
        switch self {
        case .basic:
            t.damage = 1
        case .fire:
            t.damage = 0.9 * scale
            t.burnFactor = 0.45 * scale
            t.burnDuration = 3
        case .ice:
            t.damage = 0.85 * scale
            t.slow = 0.35 + 0.08 * Double(lvl - 1)
            t.slowDuration = 2
            t.freezeChance = 0.08 + 0.06 * Double(lvl - 1)
            t.freezeDuration = 1
        case .lightning:
            t.damage = 0.8 * scale
            t.chains = 1 + lvl
            t.chainDamage = 0.55 * scale
        case .poison:
            t.damage = 0.7 * scale
            t.poisonStacks = lvl >= 3 ? 2 : 1
            t.poisonFactor = 0.28 * scale
        case .explosive:
            t.damage = 0.9 * scale
            t.aoeRadius = 52 + 8 * CGFloat(lvl)
            t.aoeDamage = 0.55 * scale
        case .ghost:
            t.damage = 0.85 * scale
            t.pierce = 2 + lvl
        case .vampire:
            t.damage = 0.95 * scale
            t.lifestealKills = max(6, 14 - 3 * (lvl - 1))
        case .steam:
            t.damage = 1.3
            t.burnFactor = 0.6
            t.burnDuration = 3
            t.slow = 0.45
            t.slowDuration = 2.5
            t.aoeRadius = 60
            t.aoeDamage = 0.5
            t.aoeAppliesStatus = true
        case .plasma:
            t.damage = 1.4
            t.chains = 4
            t.chainDamage = 0.8
            t.burnFactor = 0.5
            t.burnDuration = 2.5
            t.aoeRadius = 40
            t.aoeDamage = 0.6
        case .glacier:
            t.damage = 1.2
            t.chains = 4
            t.chainDamage = 0.7
            t.slow = 0.5
            t.slowDuration = 2.5
            t.freezeChance = 0.35
            t.freezeDuration = 1.4
        case .toxicBomb:
            t.damage = 1.1
            t.aoeRadius = 80
            t.aoeDamage = 0.6
            t.poisonStacks = 2
            t.poisonFactor = 0.4
            t.aoeAppliesStatus = true
        case .specter:
            t.damage = 1.5
            t.pierce = 8
            t.lifestealKills = 5
        case .napalm:
            t.damage = 1.3
            t.aoeRadius = 85
            t.aoeDamage = 0.7
            t.burnFactor = 0.8
            t.burnDuration = 4
            t.aoeAppliesStatus = true
        case .plague:
            t.damage = 1.1
            t.pierce = 4
            t.poisonStacks = 2
            t.poisonFactor = 0.4
            t.spreadsPoison = true
        }
        return t
    }
}

// MARK: - Passive upgrades

enum UpgradeRarity: Int, Comparable {
    case common
    case rare
    case legendary
    case fusion

    static func < (lhs: UpgradeRarity, rhs: UpgradeRarity) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .common: "COMUM"
        case .rare: "RARO"
        case .legendary: "LENDÁRIO"
        case .fusion: "FUSÃO"
        }
    }

    var color: Color {
        switch self {
        case .common: .secondary
        case .rare: GamePalette.cyan
        case .legendary: .orange
        case .fusion: GamePalette.magenta
        }
    }

    var assetSuffix: String {
        switch self {
        case .common: "Common"
        case .rare: "Rare"
        case .legendary: "Legendary"
        case .fusion: "Fusion"
        }
    }
}

enum Passive: String, CaseIterable, Identifiable {
    case extraBall
    case heavyCore
    case overdrive
    case fortify
    case criticalMass
    case piercingRounds
    case rapidVolley
    case bankShot
    case lifeSteal
    case pulseReactor
    case cryoCore
    case bountyHunter
    case lastStand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extraBall: "Tiro Gêmeo"
        case .heavyCore: "Núcleo Pesado"
        case .overdrive: "Sobrecarga"
        case .fortify: "Escudo de Pulso"
        case .criticalMass: "Massa Crítica"
        case .piercingRounds: "Perfuração Quântica"
        case .rapidVolley: "Gatilho Neural"
        case .bankShot: "Tabela Perfeita"
        case .lifeSteal: "Sifão Vital"
        case .pulseReactor: "Reator de Pulso"
        case .cryoCore: "Núcleo Criogênico"
        case .bountyHunter: "Caçador de Recompensa"
        case .lastStand: "Última Resistência"
        }
    }

    var detail: String {
        switch self {
        case .extraBall: "+1 tiro básico no arsenal"
        case .heavyCore: "+25% de dano · tiros 8% mais lentos"
        case .overdrive: "+20% velocidade dos tiros · lançamento 10% mais rápido"
        case .fortify: "+1 vida e recarrega 20% da Ultimate"
        case .criticalMass: "+12% de chance de crítico (dano x2,5)"
        case .piercingRounds: "Todos os tiros atravessam +1 inimigo"
        case .rapidVolley: "Lançamento 25% mais rápido · −8% de dano"
        case .bankShot: "+12% de dano por ricochete na parede (até 5)"
        case .lifeSteal: "Cure 1 vida a cada 25 abates"
        case .pulseReactor: "+40% de dano e +20% de recarga da Ultimate"
        case .cryoCore: "Inimigos 15% mais lentos · mas ganham 10% de vida"
        case .bountyHunter: "+50% pontos, +25% núcleos · mais elites"
        case .lastStand: "+80% de dano quando resta apenas 1 vida"
        }
    }

    var symbol: String {
        switch self {
        case .extraBall: "circle.grid.2x2.fill"
        case .heavyCore: "scope"
        case .overdrive: "bolt.fill"
        case .fortify: "shield.lefthalf.filled"
        case .criticalMass: "burst.fill"
        case .piercingRounds: "arrow.up.and.down.and.arrow.left.and.right"
        case .rapidVolley: "timer"
        case .bankShot: "arrow.triangle.swap"
        case .lifeSteal: "heart.text.clipboard.fill"
        case .pulseReactor: "bolt.circle.fill"
        case .cryoCore: "thermometer.snowflake"
        case .bountyHunter: "target"
        case .lastStand: "flame.fill"
        }
    }

    var rarity: UpgradeRarity {
        switch self {
        case .lastStand, .lifeSteal: .legendary
        case .criticalMass, .pulseReactor, .cryoCore, .bountyHunter, .bankShot: .rare
        default: .common
        }
    }

    var maxLevel: Int {
        switch self {
        case .extraBall: 6
        case .criticalMass, .piercingRounds: 4
        case .rapidVolley, .heavyCore, .overdrive: 5
        case .cryoCore, .lifeSteal, .bankShot, .pulseReactor, .bountyHunter: 3
        case .lastStand: 2
        case .fortify: 99
        }
    }

    var gearSlot: HeroGearSlot {
        switch self {
        case .criticalMass, .rapidVolley, .bountyHunter: .ionCrown
        case .heavyCore, .piercingRounds: .shoulderPods
        case .overdrive, .bankShot: .starCore
        case .lifeSteal, .lastStand: .voidCape
        case .fortify, .pulseReactor, .cryoCore: .reactorHalo
        case .extraBall: .plasmaOrbit
        }
    }

    var color: Color {
        switch self {
        case .extraBall, .piercingRounds: GamePalette.cyan
        case .heavyCore, .lifeSteal: GamePalette.coral
        case .overdrive, .rapidVolley: GamePalette.lime
        case .fortify, .pulseReactor: GamePalette.violet
        case .criticalMass: .orange
        case .bankShot: GamePalette.magenta
        case .cryoCore: .blue
        case .bountyHunter: .yellow
        case .lastStand: .red
        }
    }
}

/// One card offered on level-up or by a boss chest.
enum UpgradeOption: Hashable, Identifiable {
    case passive(Passive)
    case newBall(BallType)
    case levelBall(BallType)
    case fuse(BallType)

    var id: String {
        switch self {
        case .passive(let p): "p-\(p.rawValue)"
        case .newBall(let b): "n-\(b.rawValue)"
        case .levelBall(let b): "l-\(b.rawValue)"
        case .fuse(let b): "f-\(b.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .passive(let p): p.title
        case .newBall(let b), .levelBall(let b), .fuse(let b): b.title
        }
    }

    var symbol: String {
        switch self {
        case .passive(let p): p.symbol
        case .newBall(let b), .levelBall(let b), .fuse(let b): b.symbol
        }
    }

    var color: Color {
        switch self {
        case .passive(let p): p.color
        case .newBall(let b), .levelBall(let b), .fuse(let b): b.color
        }
    }

    var rarity: UpgradeRarity {
        switch self {
        case .passive(let p): p.rarity
        case .newBall: .rare
        case .levelBall: .common
        case .fuse: .fusion
        }
    }

    var tag: String {
        switch self {
        case .passive: "PASSIVA"
        case .newBall: "NOVO TIRO"
        case .levelBall: "EVOLUIR TIRO"
        case .fuse: "FUSÃO"
        }
    }

    var gearSlot: HeroGearSlot {
        switch self {
        case .passive(let p): p.gearSlot
        case .newBall(let b), .levelBall(let b), .fuse(let b): b.gearSlot
        }
    }
}

enum UpgradeContext: Equatable {
    case levelUp
    case bossChest
}

// MARK: - Hero gear

/// Armor pieces drawn on the hero. Every upgrade belongs to one slot; picking it equips that
/// slot's piece at the upgrade's rarity (art: `HeroGear_<asset>_<Rarity>`).
enum HeroGearSlot: String, CaseIterable, Identifiable, Hashable {
    case ionCrown
    case voidCape
    case shoulderPods
    case plasmaOrbit
    case reactorHalo
    case starCore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ionCrown: "Coroa de Íons"
        case .voidCape: "Capa do Vazio"
        case .shoulderPods: "Pods de Combate"
        case .plasmaOrbit: "Satélites de Plasma"
        case .reactorHalo: "Halo de Reator"
        case .starCore: "Núcleo Estelar"
        }
    }

    var symbol: String {
        switch self {
        case .ionCrown: "crown.fill"
        case .voidCape: "wind"
        case .shoulderPods: "capsule.fill"
        case .plasmaOrbit: "atom"
        case .reactorHalo: "circle.hexagongrid.fill"
        case .starCore: "star.fill"
        }
    }

    var assetName: String {
        switch self {
        case .ionCrown: "IonCrown"
        case .voidCape: "VoidCape"
        case .shoulderPods: "ShoulderPods"
        case .plasmaOrbit: "PlasmaOrbit"
        case .reactorHalo: "ReactorHalo"
        case .starCore: "StarCore"
        }
    }
}

/// What picking an upgrade would do to the hero's armor.
struct GearPreview: Equatable {
    let slot: HeroGearSlot
    let rarity: UpgradeRarity
    /// False when the slot already holds a piece of this rarity or better.
    let isUpgrade: Bool
}

// MARK: - Banners

enum BannerStyle: Equatable {
    case wave
    case boss
    case combo
    case fusion
    case clear
}

struct Banner: Equatable, Identifiable {
    let id: Int
    let title: String
    let subtitle: String?
    let style: BannerStyle
}

// MARK: - Run summary

struct RunStats: Equatable {
    var score = 0
    var wave = 1
    var level = 1
    var bestCombo = 0
    var kills = 0
    var bossesDefeated = 0
    var fusions = 0
    var damageDealt = 0.0
    var discoveredBalls: Set<BallType> = []
    var coresEarned = 0
}
