import SwiftUI
import UIKit

enum HeroCharacter: String, CaseIterable, Codable, Identifiable {
    case vanguard
    case ricochet
    case pyra
    case glacius

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vanguard: "Vanguarda"
        case .ricochet: "Ricochete"
        case .pyra: "Pyra"
        case .glacius: "Glacius"
        }
    }

    var detail: String {
        switch self {
        case .vanguard: "Equilibrado. Começa com 2 tiros básicos."
        case .ricochet: "+12% de dano por ricochete na parede, tiros 15% mais rápidos, −10% de dano."
        case .pyra: "Começa com Tiro Ígneo e Detonador, mas com 1 vida a menos."
        case .glacius: "Começa com Tiro Glacial. Inimigos 10% mais lentos, Ultimate recarrega 15% mais rápido."
        }
    }

    var symbol: String {
        switch self {
        case .vanguard: "shield.fill"
        case .ricochet: "arrow.triangle.swap"
        case .pyra: "flame.fill"
        case .glacius: "snowflake"
        }
    }

    var cost: Int {
        switch self {
        case .vanguard: 0
        case .ricochet: 450
        case .pyra: 900
        case .glacius: 900
        }
    }

    /// Waves of extra enemy threat this hero's starting kit is worth (see `RunConfig.loadoutThreat`).
    /// Starting elementals count about as much as Vantagem; a missing life or basic ball takes some back.
    var threat: Double {
        switch self {
        case .vanguard: 0
        case .ricochet: 0.4
        case .pyra: 0.6
        case .glacius: 0.6
        }
    }

    var tint: UIColor {
        switch self {
        case .vanguard: Neon.heroBlue
        case .ricochet: Neon.magenta
        case .pyra: UIColor(red: 1, green: 0.5, blue: 0.15, alpha: 1)
        case .glacius: UIColor(red: 0.55, green: 0.88, blue: 1, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: tint) }
}

/// The run's ultimate, fired with an upward swipe once the reactor is charged. The Pulse is
/// free; the others are bought with cores and equipped like a character.
enum UltimateKind: String, CaseIterable, Codable, Identifiable {
    case pulse
    case stasis
    case storm
    case swarm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pulse: "Pulso Nova"
        case .stasis: "Estase"
        case .storm: "Tempestade"
        case .swarm: "Revoada"
        }
    }

    var detail: String {
        switch self {
        case .pulse: "Onda de choque que fere todos os inimigos, empurra a horda para trás e apaga os tiros inimigos."
        case .stasis: "Congela todos os inimigos por 4s e apaga os tiros inimigos. Chefes ficam apenas lentos."
        case .storm: "Três raios caem sobre cada inimigo da tela. A mais forte contra chefes."
        case .swarm: "Dispara uma revoada de 24 tiros perfurantes na direção da sua mira."
        }
    }

    var symbol: String {
        switch self {
        case .pulse: "burst.fill"
        case .stasis: "hourglass"
        case .storm: "cloud.bolt.fill"
        case .swarm: "circle.hexagongrid.fill"
        }
    }

    var cost: Int {
        switch self {
        case .pulse: 0
        case .stasis: 500
        case .storm: 750
        case .swarm: 1000
        }
    }

    /// Waves of extra enemy threat this ultimate is worth over the free Pulse.
    var threat: Double {
        switch self {
        case .pulse: 0
        case .stasis: 0.3
        case .storm: 0.5
        case .swarm: 0.4
        }
    }

    var tint: UIColor {
        switch self {
        case .pulse: Neon.heroBlue
        case .stasis: UIColor(red: 0.6, green: 0.92, blue: 1, alpha: 1)
        case .storm: Neon.gold
        case .swarm: Neon.heroOrange
        }
    }

    var color: Color { Color(uiColor: tint) }
}

enum LabUpgrade: String, CaseIterable, Codable, Identifiable {
    case vitality
    case power
    case reactor
    case wisdom
    case arsenal
    case fortune
    case headStart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vitality: "Vitalidade"
        case .power: "Potência"
        case .reactor: "Reator Inicial"
        case .wisdom: "Sabedoria"
        case .arsenal: "Arsenal"
        case .fortune: "Fortuna"
        case .headStart: "Vantagem"
        }
    }

    var detail: String {
        switch self {
        case .vitality: "+1 vida inicial"
        case .power: "+8% de dano"
        case .reactor: "Começa com +15% de carga da Ultimate"
        case .wisdom: "+10% de experiência"
        case .arsenal: "+1 espaço para tiros especiais"
        case .fortune: "+10% de núcleos por run"
        case .headStart: "Começa cada run com um tiro elemental aleatório"
        }
    }

    var symbol: String {
        switch self {
        case .vitality: "heart.fill"
        case .power: "bolt.fill"
        case .reactor: "bolt.circle.fill"
        case .wisdom: "book.fill"
        case .arsenal: "square.grid.3x3.fill"
        case .fortune: "dollarsign.circle.fill"
        case .headStart: "gift.fill"
        }
    }

    var maxLevel: Int {
        switch self {
        case .vitality: 3
        case .power: 5
        case .reactor: 4
        case .wisdom: 5
        case .arsenal: 2
        case .fortune: 5
        case .headStart: 1
        }
    }

    /// Waves of extra enemy threat each level adds (see `GameEngine.threat`), so a run starts
    /// as hard as the hero is strong. Fortune only changes the payout, so it adds none.
    var threatPerLevel: Double {
        switch self {
        case .vitality: 0.6
        case .power: 0.3
        case .reactor: 0.15
        case .wisdom: 0.2
        case .arsenal: 0.5
        case .fortune: 0
        case .headStart: 0.5
        }
    }

    func cost(forLevel level: Int) -> Int {
        let base: Int
        switch self {
        case .vitality: base = 300
        case .power: base = 150
        case .reactor: base = 125
        case .wisdom: base = 125
        case .arsenal: base = 600
        case .fortune: base = 175
        case .headStart: base = 1000
        }
        return Int(Double(base) * pow(1.75, Double(level)))
    }
}

/// Everything the engine needs to know about the meta layer when starting a run.
struct RunConfig: Equatable {
    var character: HeroCharacter = .vanguard
    var ultimate: UltimateKind = .pulse
    var lab: [LabUpgrade: Int] = [:]
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    /// First run ever: spell out how to fire the ultimate. Later runs rely on the hero's aura alone.
    var coachUltimate = false

    func labLevel(_ upgrade: LabUpgrade) -> Int { lab[upgrade] ?? 0 }

    /// How much stronger than a bare Vanguard with the Pulse this run starts, in waves of enemy
    /// threat: the lab, the hero's starting kit and the equipped ultimate. Only what is equipped
    /// counts; owning a hero or ultimate without using it changes nothing.
    var loadoutThreat: Double {
        let lab = LabUpgrade.allCases.reduce(0) { $0 + $1.threatPerLevel * Double(labLevel($1)) }
        return lab + character.threat + ultimate.threat
    }
}
