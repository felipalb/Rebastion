import SpriteKit
import UIKit

/// Frame textures for every character action (`<base>_<Action>_01…04` in the asset catalog).
/// Source frames are 512 px; each set is downsampled once to the size it is drawn at, which keeps
/// memory sane, and the cache can be warmed up a few frames at a time so no spawn ever hitches.
@MainActor
enum SpriteAnimations {
    static let frameCount = 4

    private static var cache: [String: [SKTexture]] = [:]
    private static var warmUpQueue: [(base: String, action: String)] = []

    nonisolated static let enemyActions = ["Idle", "Move", "Dash", "Dodge", "Attack", "Hit"]
    nonisolated static let heroActions = ["Idle", "DashLeft", "DashRight", "Shoot", "Hit"]

    static func frames(_ base: String, _ action: String) -> [SKTexture] {
        let key = "\(base)_\(action)"
        if let cached = cache[key] { return cached }
        let pixels = pixelSize(for: base)
        let textures = (1...frameCount).map { index -> SKTexture in
            let name = "\(key)_0\(index)"
            guard let image = UIImage(named: name) else { return SKTexture(imageNamed: name) }
            return SKTexture(image: downsample(image, to: pixels))
        }
        cache[key] = textures
        return textures
    }

    /// Projectile frames (`<art>_01…04`, `Projectiles` in the asset catalog). Shots are drawn
    /// small, so their 256 px sources are cut down hard.
    static func projectileFrames(_ art: String) -> [SKTexture] {
        if let cached = cache[art] { return cached }
        let textures = (1...frameCount).map { index -> SKTexture in
            let name = "\(art)_0\(index)"
            guard let image = UIImage(named: name) else { return SKTexture(imageNamed: name) }
            return SKTexture(image: downsample(image, to: 128))
        }
        cache[art] = textures
        return textures
    }

    /// Queue a projectile so `warmUp()` decodes it before its first shot.
    static func enqueueProjectile(_ art: String) {
        if cache[art] == nil, !warmUpQueue.contains(where: { $0.base == art && $0.action.isEmpty }) {
            warmUpQueue.append((art, ""))
        }
    }

    /// Queue every action of a character so `warmUp()` can decode it in the background of normal frames.
    static func enqueue(_ base: String, actions: [String] = enemyActions) {
        for action in actions where cache["\(base)_\(action)"] == nil {
            if !warmUpQueue.contains(where: { $0.base == base && $0.action == action }) {
                warmUpQueue.append((base, action))
            }
        }
    }

    /// Decodes one queued action. Call once per frame.
    static func warmUp() {
        guard !warmUpQueue.isEmpty else { return }
        let next = warmUpQueue.removeFirst()
        _ = next.action.isEmpty ? projectileFrames(next.base) : frames(next.base, next.action)
    }

    /// Bosses are big; only the one currently in play is kept around.
    static func evictBosses(except base: String) {
        for key in cache.keys where key.hasPrefix("SpriteBoss") && !key.hasPrefix(base + "_") {
            cache[key] = nil
        }
    }

    private static func pixelSize(for base: String) -> Int {
        if base.hasPrefix("SpriteBoss") { return 400 }
        if base == "SpriteHero" { return 288 }
        if base == "SpriteTank" { return 320 }
        return 256
    }

    private static func downsample(_ image: UIImage, to pixels: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: pixels, height: pixels)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Plays frame sequences on a sprite. Time is pushed in from outside so hit-stop, freeze and
/// slow effects can scale or stop it. Switching clips can cross-fade through a ghost of the old frame.
@MainActor
final class FrameAnimator {
    enum Playback {
        /// Repeats the sequence.
        case loop
        /// Plays once and then reports `isFinished`, staying on the last frame.
        case once
    }

    let sprite: SKSpriteNode
    /// Extra sprites (e.g. the white hit-flash overlay) that must always show the same frame.
    var followers: [SKSpriteNode] = []

    private(set) var clip = ""
    private(set) var playback: Playback = .loop
    private(set) var isFinished = false
    private var frames: [SKTexture] = []
    private var sequence: [Int] = []
    private var fps = 10.0
    private var time = 0.0
    private var shownFrame = -1
    private let ghost = SKSpriteNode()

    init(sprite: SKSpriteNode) {
        self.sprite = sprite
        ghost.anchorPoint = sprite.anchorPoint
        ghost.size = sprite.size
        ghost.alpha = 0
        ghost.zPosition = 0.05
        sprite.addChild(ghost)
    }

    /// Index into the current sequence.
    var step: Int { min(sequence.count - 1, Int(time * fps)) }
    /// Texture index currently shown (follows `sequence`), -1 before the first frame.
    var frame: Int { shownFrame }
    /// Seconds since the clip started.
    var elapsed: Double { time }

    func play(_ clip: String, frames: [SKTexture], sequence: [Int]? = nil, fps: Double, playback: Playback, fade: Double = 0, restart: Bool = true) {
        if !restart, clip == self.clip {
            self.fps = fps
            return
        }
        if fade > 0, let texture = sprite.texture {
            ghost.texture = texture
            ghost.size = sprite.size
            ghost.color = sprite.color
            ghost.colorBlendFactor = sprite.colorBlendFactor
            ghost.removeAllActions()
            ghost.alpha = 1
            ghost.run(.fadeOut(withDuration: fade))
        }
        self.clip = clip
        self.frames = frames
        self.sequence = sequence ?? Array(frames.indices)
        self.fps = fps
        self.playback = playback
        time = 0
        isFinished = false
        shownFrame = -1
        apply()
    }

    func setRate(fps: Double) {
        // Keep the current frame when the speed changes mid-loop.
        let position = time * self.fps
        self.fps = max(0.01, fps)
        time = position / self.fps
    }

    func update(_ dt: Double) {
        guard !sequence.isEmpty else { return }
        time += dt
        let duration = Double(sequence.count) / fps
        if time >= duration {
            switch playback {
            case .loop:
                time = time.truncatingRemainder(dividingBy: duration)
            case .once:
                time = duration
                isFinished = true
            }
        }
        apply()
    }

    private func apply() {
        guard !sequence.isEmpty else { return }
        let frame = sequence[min(sequence.count - 1, Int(time * fps))]
        guard frame != shownFrame, frames.indices.contains(frame) else { return }
        shownFrame = frame
        sprite.texture = frames[frame]
        for follower in followers {
            follower.texture = frames[frame]
        }
    }
}
