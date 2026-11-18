import SpriteKit
import UIKit

extension UpgradeRarity {
    var uiColor: UIColor {
        switch self {
        case .common: UIColor(white: 0.85, alpha: 1)
        case .rare: Neon.cyan
        case .legendary: UIColor(red: 1, green: 0.62, blue: 0.15, alpha: 1)
        case .fusion: Neon.magenta
        }
    }
}

/// Gear frames (`HeroGear_<Slot>_<Rarity>_<Pose>_01…04`) are 512 px canvases registered
/// frame-for-frame to the hero's own animation. Each frame is downsampled once to the hero's
/// draw size and cached; frames can be queued and decoded one per game frame to avoid hitches.
@MainActor
enum GearTextures {
    private static var cache: [String: SKTexture] = [:]
    private static var warmUpQueue: [String] = []

    static func texture(_ name: String) -> SKTexture {
        if let cached = cache[name] { return cached }
        let texture: SKTexture
        if let image = UIImage(named: name) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let size = CGSize(width: 288, height: 288)
            texture = SKTexture(image: UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            })
        } else {
            texture = SKTexture(imageNamed: name)
        }
        cache[name] = texture
        return texture
    }

    static func frameName(_ slot: HeroGearSlot, _ rarity: UpgradeRarity, _ pose: HeroGearRig.Pose, _ index: Int) -> String {
        "HeroGear_\(slot.assetName)_\(rarity.assetSuffix)_\(pose.rawValue)_0\(index + 1)"
    }

    /// Queue every pose of a piece so `warmUp()` can decode it over the next frames.
    static func enqueue(_ slot: HeroGearSlot, _ rarity: UpgradeRarity) {
        for pose in HeroGearRig.Pose.allCases {
            for index in 0..<SpriteAnimations.frameCount {
                let name = frameName(slot, rarity, pose, index)
                if cache[name] == nil, !warmUpQueue.contains(name) {
                    warmUpQueue.append(name)
                }
            }
        }
    }

    /// Decodes one queued frame. Call once per game frame.
    static func warmUp() {
        guard !warmUpQueue.isEmpty else { return }
        _ = texture(warmUpQueue.removeFirst())
    }

    /// Drops the frames of a piece the hero no longer wears.
    static func evict(_ slot: HeroGearSlot, _ rarity: UpgradeRarity) {
        let prefix = "HeroGear_\(slot.assetName)_\(rarity.assetSuffix)_"
        for key in cache.keys where key.hasPrefix(prefix) {
            cache[key] = nil
        }
        warmUpQueue.removeAll { $0.hasPrefix(prefix) }
    }
}

/// Armor pieces layered on the hero sprite. Every piece has its own frames for each hero pose,
/// so it simply shows the frame the hero is showing; wings and halo sit behind the body.
@MainActor
final class HeroGearRig {
    /// Hero animation the gear follows; raw values match the asset names.
    enum Pose: String, CaseIterable {
        case idle = "Idle"
        case dashLeft = "DashLeft"
        case dashRight = "DashRight"
        case shoot = "Shoot"
        case hit = "Hit"
    }

    private final class Piece {
        let slot: HeroGearSlot
        let node = SKSpriteNode()
        /// Holds the previous pose's frame for a short cross-fade, like the hero's own ghost.
        let ghost = SKSpriteNode()
        var rarity: UpgradeRarity?
        var shown: String?
        var pop: CGFloat = 0
        var flash: CGFloat = 0

        init(slot: HeroGearSlot, size: CGFloat, anchorY: CGFloat) {
            self.slot = slot
            for sprite in [node, ghost] {
                sprite.size = CGSize(width: size, height: size)
                sprite.anchorPoint = CGPoint(x: 0.5, y: anchorY)
                sprite.alpha = 0
            }
        }
    }

    /// Below the hero sprite.
    let back = SKNode()
    /// Above the hero sprite and its cross-fade ghost.
    let front = SKNode()

    private var pieces: [Piece] = []
    private var pose: Pose = .idle
    private var frame = 0

    init(heroSize: CGFloat, anchorY: CGFloat) {
        back.zPosition = -0.3
        front.zPosition = 0.2
        for slot in HeroGearSlot.allCases {
            let piece = Piece(slot: slot, size: heroSize, anchorY: anchorY)
            let layer = slot == .voidCape || slot == .reactorHalo ? back : front
            layer.addChild(piece.ghost)
            layer.addChild(piece.node)
            pieces.append(piece)
        }
    }

    /// Full-body frame of the equipped hero in the pose and frame currently shown.
    func equippedHeroName(_ rarity: UpgradeRarity) -> String {
        "SpriteHero_Equipped_\(rarity.assetSuffix)_\(pose.rawValue)_0\(frame + 1)"
    }

    /// Shows the gear without fanfare (new run, restored state).
    func set(_ gear: [HeroGearSlot: UpgradeRarity]) {
        for piece in pieces {
            let rarity = gear[piece.slot]
            if let old = piece.rarity, old != rarity {
                GearTextures.evict(piece.slot, old)
            }
            piece.rarity = rarity
            piece.shown = nil
            if let rarity {
                GearTextures.enqueue(piece.slot, rarity)
                show(piece)
                piece.node.alpha = 1
            } else {
                piece.node.alpha = 0
                piece.ghost.alpha = 0
            }
        }
    }

    /// Swaps in the new piece with a pop, a white flash and a ghost in the rarity color.
    func equip(_ slot: HeroGearSlot, rarity: UpgradeRarity) {
        guard let piece = pieces.first(where: { $0.slot == slot }) else { return }
        if let old = piece.rarity, old != rarity {
            GearTextures.evict(slot, old)
        }
        piece.rarity = rarity
        piece.shown = nil
        GearTextures.enqueue(slot, rarity)
        show(piece)
        piece.node.alpha = 1
        piece.pop = rarity >= .legendary ? 0.7 : 0.5
        piece.flash = 1

        let ghost = SKSpriteNode(texture: piece.node.texture, size: piece.node.size)
        ghost.anchorPoint = piece.node.anchorPoint
        ghost.color = rarity.uiColor
        ghost.colorBlendFactor = 1
        ghost.blendMode = .add
        ghost.zPosition = 0.1
        piece.node.parent?.addChild(ghost)
        let grow = SKAction.scale(to: 1.7, duration: 0.45)
        grow.timingMode = .easeOut
        ghost.run(.sequence([.group([grow, .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
    }

    /// `frame` is the hero's texture index (`FrameAnimator.frame`).
    func update(pose: Pose, frame rawFrame: Int, dt: Double, tint: UIColor?, tintAmount: CGFloat) {
        GearTextures.warmUp()
        let poseChanged = pose != self.pose
        self.pose = pose
        frame = max(0, min(SpriteAnimations.frameCount - 1, rawFrame))

        for piece in pieces where piece.rarity != nil {
            if poseChanged, piece.node.alpha > 0.01 {
                piece.ghost.texture = piece.node.texture
                piece.ghost.removeAllActions()
                piece.ghost.alpha = piece.node.alpha
                piece.ghost.run(.fadeOut(withDuration: 0.06))
            }
            show(piece)

            piece.pop *= CGFloat(exp(-dt * 9))
            piece.flash = max(0, piece.flash - CGFloat(dt) * 3.5)
            piece.node.setScale(1 + piece.pop)

            if piece.flash > 0 {
                piece.node.color = .white
                piece.node.colorBlendFactor = piece.flash
            } else if let tint, tintAmount > 0 {
                piece.node.color = tint
                piece.node.colorBlendFactor = tintAmount
            } else {
                piece.node.colorBlendFactor = 0
            }
            piece.ghost.color = piece.node.color
            piece.ghost.colorBlendFactor = piece.node.colorBlendFactor
        }
    }

    private func show(_ piece: Piece) {
        guard let rarity = piece.rarity else { return }
        let name = GearTextures.frameName(piece.slot, rarity, pose, frame)
        guard name != piece.shown else { return }
        piece.shown = name
        piece.node.texture = GearTextures.texture(name)
    }
}
