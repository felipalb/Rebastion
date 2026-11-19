import SpriteKit
import UIKit

/// Enemy visual. The root follows the engine position;
/// `body` holds everything that wobbles, recoils and squashes so those offsets never leak into gameplay.
/// The sprite itself is driven by a small state machine over the frame sets
/// (Idle, Move, Dash, Dodge, Attack, Hit), reading the engine state to anticipate attacks.
final class EnemyNode: SKNode {
    /// Moments the scene may want to punctuate with screen effects.
    enum Cue {
        case landed
    }

    private enum State {
        case entrance
        case landing
        case move
        case idle
        case windup
        case attack
        case lunge
        case dodge
        case hurt
        case enrage
    }

    let enemyID: Int
    let kind: EnemyKind
    var onCue: ((Cue, EnemyNode) -> Void)?
    private let body = SKNode()
    private let sprite: SKSpriteNode
    private let flashSprite: SKSpriteNode
    private let animator: FrameAnimator
    private let base: String
    private let accent: UIColor
    private let radius: CGFloat
    private var aura: SKSpriteNode?
    private var shield: SKShapeNode?
    private let baseTint: UIColor?

    private var state: State = .entrance
    private var stateTime = 0.0
    private var lastEnginePosition: CGPoint?
    private var velocity = CGVector.zero
    private var lastStrafe: CGFloat = 0
    private var facing: CGFloat = 1
    private var targetFacing: CGFloat = 1
    private var hurtCooldown = 0.0
    private var lungeCooldown = 0.0
    private var afterimageTimer = 0.0
    private var isFrozen = false

    private var flashTime = 0.0
    private var animTime: Double
    private var knock = CGVector.zero
    private var tilt: CGFloat = 0
    private var bank: CGFloat = 0
    private var squashTime = 1.0
    private var squashAmount: CGFloat = 0
    private var attackTime = 1.0
    private(set) var isDying = false

    /// Seconds before the engine fires that the wind-up starts, so the strike frame lands on the shot.
    private static let windupLead = 0.24

    init(enemy: Enemy) {
        enemyID = enemy.id
        kind = enemy.kind
        baseTint = enemy.kind.tint
        radius = enemy.radius
        animTime = Double(enemy.id % 17) * 0.37
        base = enemy.kind == .boss ? enemy.bossVariant.animationBase : enemy.kind.animationBase
        accent = enemy.kind == .boss ? enemy.bossVariant.color : enemy.kind.particleColor
        // Frames carry transparent padding around the character, so they are drawn larger than the hit circle.
        let side = enemy.radius * 2.9 * (enemy.kind == .boss ? 1.15 : 1.35)
        sprite = SKSpriteNode(color: .clear, size: CGSize(width: side, height: side))
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.42)
        flashSprite = SKSpriteNode(color: .clear, size: sprite.size)
        flashSprite.anchorPoint = sprite.anchorPoint
        flashSprite.color = .white
        flashSprite.colorBlendFactor = 1
        flashSprite.blendMode = .add
        flashSprite.alpha = 0
        flashSprite.zPosition = 0.1
        animator = FrameAnimator(sprite: sprite)
        animator.followers = [flashSprite]
        super.init()

        addChild(body)
        if enemy.isElite {
            let aura = SKSpriteNode(texture: SceneTextures.glow, size: CGSize(width: side * 1.2, height: side * 1.2))
            aura.color = Neon.gold
            aura.colorBlendFactor = 1
            aura.blendMode = .add
            aura.alpha = 0.45
            aura.zPosition = -1
            aura.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.2, duration: 0.5),
                .fadeAlpha(to: 0.5, duration: 0.5),
            ])))
            body.addChild(aura)
            self.aura = aura
        }
        body.addChild(sprite)
        sprite.addChild(flashSprite)

        if enemy.kind == .shielded {
            let path = UIBezierPath(arcCenter: .zero, radius: enemy.radius + 6, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: true)
            let shield = SKShapeNode(path: path.cgPath)
            shield.strokeColor = UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
            shield.lineWidth = 4
            shield.glowWidth = 3
            shield.lineCap = .round
            body.addChild(shield)
            self.shield = shield
        }

        // Everyone drops in with a dash; the boss keeps dashing until it reaches its post.
        if enemy.kind == .boss {
            animator.play("entrance", frames: frames("Dash"), sequence: [1, 2], fps: 10, playback: .loop)
        } else {
            animator.play("entrance", frames: frames("Dash"), fps: 14, playback: .once)
            // Pop in with a little overshoot.
            setScale(0.1)
            alpha = 0
            let grow = SKAction.scale(to: 1.15, duration: 0.14)
            grow.timingMode = .easeOut
            let settle = SKAction.scale(to: 1, duration: 0.1)
            settle.timingMode = .easeInEaseOut
            run(.group([.sequence([grow, settle]), .fadeIn(withDuration: 0.1)]), withKey: "spawn")
        }
        lastStrafe = enemy.strafeDirection
        applyTint()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError() }

    /// `lineY` is the defense line in engine space; melee enemies lunge at it as they arrive.
    func sync(_ enemy: Enemy, dt: Double, lineY: CGFloat) {
        guard !isDying else { return }
        isFrozen = enemy.status.isFrozen && enemy.kind != .boss
        updateMotion(enemy, dt: dt)
        updateState(enemy, dt: dt, lineY: lineY)
        updateBody(enemy, dt: dt)
        updateTint(enemy, dt: dt)
    }

    /// Called for every hit. `direction` points from the impact towards the enemy (scene space, normalized).
    func takeHit(direction: CGVector, critical: Bool) {
        guard !isDying else { return }
        let strength: CGFloat = kind == .boss ? 2.5 : (critical ? 9 : 5)
        knock.dx += direction.dx * strength
        knock.dy += direction.dy * strength
        let cap: CGFloat = kind == .boss ? 4 : 12
        let length = hypot(knock.dx, knock.dy)
        if length > cap {
            knock.dx *= cap / length
            knock.dy *= cap / length
        }
        // Tilt away from the side that got hit.
        tilt += (direction.dx >= 0 ? -1 : 1) * (critical ? 0.32 : 0.18) * (kind == .boss ? 0.3 : 1)
        tilt = max(-0.5, min(0.5, tilt))
        squashTime = 0
        squashAmount = critical ? 0.26 : 0.18
        if kind == .boss { squashAmount *= 0.45 }
        flashTime = critical ? 0.12 : 0.07
        flashSprite.removeAllActions()
        flashSprite.alpha = critical ? 1 : 0.85
        flashSprite.run(.fadeOut(withDuration: critical ? 0.16 : 0.1))

        // Recoil with the hit frames. Never cuts into an entrance, wind-up or attack, and a stream
        // of hits replays it at most every so often; the boss flinches more rarely than minions.
        if !isFrozen, hurtCooldown <= 0, state == .move || state == .idle || state == .dodge {
            enter(.hurt)
            animator.play("hurt", frames: frames("Hit"), fps: kind == .boss ? 12 : 16, playback: .once, fade: 0.03)
            hurtCooldown = kind == .boss ? Double.random(in: 0.9...1.4) : Double.random(in: 0.35...0.6)
        }
    }

    /// The engine fired: snap to the strike frame (after the wind-up, if it had time to play).
    func attack() {
        guard !isDying else { return }
        attackTime = 0
        enter(.attack)
        animator.play("attack", frames: frames("Attack"), sequence: [2, 3], fps: 8, playback: .once)
        let muzzle = SKSpriteNode(texture: SceneTextures.flare, size: CGSize(width: radius * 1.6, height: radius * 1.6))
        muzzle.color = accent
        muzzle.colorBlendFactor = 0.7
        muzzle.blendMode = .add
        muzzle.position = CGPoint(x: 0, y: -radius * 0.9)
        muzzle.setScale(0.3)
        muzzle.zPosition = 2
        body.addChild(muzzle)
        muzzle.run(.sequence([
            .group([.scale(to: 1.1, duration: 0.05), .rotate(byAngle: 0.5, duration: 0.12)]),
            .group([.scale(to: 0.6, duration: 0.08), .fadeOut(withDuration: 0.08)]),
            .removeFromParent(),
        ]))
    }

    /// Boss phase change: a full dash in place, trailing afterimages.
    func enrage() {
        guard !isDying else { return }
        enter(.enrage)
        animator.play("enrage", frames: frames("Dash"), fps: 9, playback: .once, fade: 0.08)
        flashSprite.removeAllActions()
        flashSprite.alpha = 1
        flashSprite.run(.fadeOut(withDuration: 0.35))
    }

    /// Flash white, swell and fade, then remove itself.
    func die() {
        guard !isDying else { return }
        isDying = true
        removeAction(forKey: "spawn")
        flashSprite.removeAllActions()
        flashSprite.alpha = 1
        let swell = SKAction.scale(to: 1.35, duration: 0.14)
        swell.timingMode = .easeOut
        body.run(.group([swell, .fadeOut(withDuration: 0.14)]))
        run(.sequence([.wait(forDuration: 0.15), .removeFromParent()]))
    }

    // MARK: State machine

    private func frames(_ action: String) -> [SKTexture] {
        SpriteAnimations.frames(base, action)
    }

    private func enter(_ newState: State) {
        state = newState
        stateTime = 0
    }

    private var moveFPS: Double {
        switch kind {
        case .runner: 14
        case .bomber: 12
        case .tank, .shielded: 6
        case .boss: 7
        default: 9
        }
    }

    private func updateMotion(_ enemy: Enemy, dt: Double) {
        if let last = lastEnginePosition, dt > 0 {
            let instant = CGVector(dx: (enemy.position.x - last.x) / dt, dy: (enemy.position.y - last.y) / dt)
            let blend = CGFloat(min(1, dt * 10))
            velocity.dx += (instant.dx - velocity.dx) * blend
            velocity.dy += (instant.dy - velocity.dy) * blend
        }
        lastEnginePosition = enemy.position

        // Flyers bank into their sideways drift; the boss is heavier and leans less.
        let bankTarget = max(-0.2, min(0.2, -velocity.dx / 260)) * (kind == .boss ? 0.5 : 1)
        bank += (bankTarget - bank) * CGFloat(min(1, dt * 6))

        // The runner and bomber art dives towards the lower left; it turns to face the way it
        // weaves, but only once the weave is well under way so it doesn't flicker at the turn.
        guard kind == .runner || kind == .bomber else { return }
        if abs(velocity.dx) > kind.flight.glide * 0.5 {
            targetFacing = velocity.dx > 0 ? -1 : 1
        }
        facing += (targetFacing - facing) * CGFloat(min(1, dt * 9))
        sprite.xScale = (facing >= 0 ? 1 : -1) * max(0.08, abs(facing))
    }

    private func updateState(_ enemy: Enemy, dt: Double, lineY: CGFloat) {
        let rate: Double = isFrozen ? 0 : (enemy.status.isSlowed ? 0.5 : 1)
        stateTime += dt
        hurtCooldown -= dt
        lungeCooldown -= dt
        let atPost = kind.holdsPosition && enemy.position.y >= enemy.holdY - 0.5

        switch state {
        case .entrance:
            if kind == .boss {
                if atPost { land() }
            } else if animator.isFinished {
                settle(enemy, fade: 0.06)
            }
        case .windup:
            // The engine resets its timer on phase changes; never hang in the wind-up pose.
            if stateTime > Self.windupLead + 0.35 { settle(enemy, fade: 0.08) }
        case .landing, .attack, .lunge, .dodge, .hurt, .enrage:
            if animator.isFinished { settle(enemy, fade: 0.08) }
        case .move, .idle:
            if atPost, !isFrozen, enemy.attackTimer > 0, enemy.attackTimer < Self.windupLead {
                enter(.windup)
                animator.play("windup", frames: frames("Attack"), sequence: [0, 1], fps: 2 / Self.windupLead, playback: .once, fade: 0.05)
            } else if atPost, enemy.strafeDirection != lastStrafe, !isFrozen {
                // Turning at the arena edge reads as a sidestep.
                dodge(leanRight: enemy.strafeDirection > 0, fps: kind == .boss ? 10 : 12)
            } else if !kind.holdsPosition, lungeCooldown <= 0, !isFrozen, enemy.position.y + enemy.radius > lineY - 40 {
                enter(.lunge)
                lungeCooldown = 0.55
                animator.play("lunge", frames: frames("Attack"), fps: 12, playback: .once, fade: 0.05)
            } else {
                locomotion(enemy)
            }
        }
        lastStrafe = enemy.strafeDirection

        // Afterimages while dashing or dodging.
        let trailing = (state == .entrance && (kind == .boss || animator.step == 1 || animator.step == 2))
            || state == .enrage || (state == .dodge && animator.step == 1)
        if trailing, rate > 0 {
            afterimageTimer -= dt
            if afterimageTimer <= 0 {
                afterimageTimer = kind == .boss ? 0.06 : 0.04
                spawnAfterimage()
            }
        }

        animator.update(dt * rate)
    }

    private func settle(_ enemy: Enemy, fade: Double) {
        state = .move
        locomotion(enemy, fade: fade, force: true)
    }

    private func locomotion(_ enemy: Enemy, fade: Double = 0.12, force: Bool = false) {
        let moving: Bool
        if kind.holdsPosition {
            // Shooters hover while they strafe slowly; the boss strides when it sweeps.
            moving = enemy.position.y < enemy.holdY - 0.5 || abs(velocity.dx) > 30
        } else {
            moving = true
        }
        let target: State = moving ? .move : .idle
        guard force || target != state else { return }
        enter(target)
        if moving {
            animator.play("move", frames: frames("Move"), fps: moveFPS, playback: .loop, fade: fade)
        } else {
            animator.play("idle", frames: frames("Idle"), fps: kind == .boss ? 6 : 7, playback: .loop, fade: fade)
        }
    }

    private func land() {
        enter(.landing)
        animator.play("landing", frames: frames("Dash"), sequence: [3, 3, 0], fps: 7, playback: .once)
        squashTime = 0
        squashAmount = 0.22
        onCue?(.landed, self)
    }

    /// Dodge frames swerve right (frame 2) or left (frame 3); only the requested side is played.
    private func dodge(leanRight: Bool, fps: Double) {
        enter(.dodge)
        afterimageTimer = 0
        animator.play("dodge", frames: frames("Dodge"), sequence: [0, leanRight ? 1 : 2, 3], fps: fps, playback: .once, fade: 0.04)
    }

    private func spawnAfterimage() {
        guard let parent, let texture = sprite.texture else { return }
        let ghost = SKSpriteNode(texture: texture, size: sprite.size)
        ghost.anchorPoint = sprite.anchorPoint
        ghost.position = CGPoint(x: position.x + body.position.x, y: position.y + body.position.y)
        ghost.zRotation = body.zRotation
        ghost.xScale = sprite.xScale * body.xScale * xScale
        ghost.yScale = body.yScale * yScale
        ghost.color = accent
        ghost.colorBlendFactor = 1
        ghost.blendMode = .add
        ghost.alpha = 0.4
        ghost.zPosition = zPosition - 0.5
        parent.addChild(ghost)
        ghost.run(.sequence([
            .group([.fadeOut(withDuration: 0.24), .scale(by: 1.06, duration: 0.24)]),
            .removeFromParent(),
        ]))
    }

    // MARK: Procedural layer

    private func updateBody(_ enemy: Enemy, dt: Double) {
        let rate: Double = enemy.status.isFrozen ? 0 : (enemy.status.isSlowed ? 0.5 : 1)
        animTime += dt * rate
        let t = animTime

        // The frames carry the wingbeat; this adds a soft hover on top (everyone flies now, so
        // no footstep bounce), and the jelly-like splitter pulses as it swims.
        var bob: CGFloat = 0
        var breathe: CGFloat = 0
        switch kind {
        case .runner, .bomber:
            bob = CGFloat(sin(t * 3)) * 1.5
        case .grunt:
            bob = CGFloat(sin(t * 2.4)) * 2.5
        case .splitter:
            bob = CGFloat(sin(t * 3.2)) * 3
            breathe = CGFloat(sin(t * 3.2)) * 0.035
        case .tank, .shielded:
            bob = CGFloat(sin(t * 1.8)) * 2
            breathe = CGFloat(sin(t * 2.2)) * 0.02
        case .shooter:
            bob = CGFloat(sin(t * 3)) * 2.5
        case .boss:
            bob = CGFloat(sin(t * 1.6)) * 3
            breathe = CGFloat(sin(t * 2)) * 0.02
        }

        // Spring-damped hit reactions.
        let decay = CGFloat(exp(-dt * 16))
        knock.dx *= decay
        knock.dy *= decay
        tilt *= CGFloat(exp(-dt * 12))

        squashTime += dt
        let squash = squashAmount * CGFloat(exp(-squashTime * 13) * cos(squashTime * 38))

        // Recoil kick on the shot itself.
        attackTime += dt
        var attackScale: CGFloat = 0
        var attackLift: CGFloat = 0
        if attackTime < 0.2 {
            let p = attackTime / 0.2
            attackScale = CGFloat(sin(p * .pi)) * 0.08
            attackLift = CGFloat(sin(p * .pi)) * 3
        }

        body.position = CGPoint(x: knock.dx, y: knock.dy + bob + attackLift)
        body.zRotation = tilt + bank
        body.xScale = 1 + breathe + squash + attackScale
        body.yScale = 1 - breathe * 0.6 - squash + attackScale * 0.4
    }

    private func updateTint(_ enemy: Enemy, dt: Double) {
        if flashTime > 0 {
            flashTime -= dt
            sprite.color = .white
            sprite.colorBlendFactor = 0.6
        } else if enemy.status.isFrozen {
            sprite.color = UIColor(red: 0.6, green: 0.9, blue: 1, alpha: 1)
            sprite.colorBlendFactor = 0.75
        } else if enemy.status.isBurning {
            let flicker = 0.4 + 0.2 * sin(CACurrentMediaTime() * 20)
            sprite.color = UIColor(red: 1, green: 0.45, blue: 0.1, alpha: 1)
            sprite.colorBlendFactor = flicker
        } else if enemy.status.isPoisoned {
            sprite.color = UIColor(red: 0.45, green: 1, blue: 0.3, alpha: 1)
            sprite.colorBlendFactor = 0.5
        } else if enemy.status.isSlowed {
            sprite.color = UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1)
            sprite.colorBlendFactor = 0.4
        } else {
            applyTint()
        }
    }

    private func applyTint() {
        if let baseTint {
            sprite.color = baseTint
            sprite.colorBlendFactor = 0.55
        } else {
            sprite.colorBlendFactor = 0
        }
    }
}

/// Player shot: its type's animated art over a tinted glow, stretched along its velocity, squashing on impacts.
final class BallNode: SKNode {
    private(set) var ballID = 0
    private(set) var type: BallType = .basic
    /// Soft additive halo in the shot's color, so the player's shots glow and enemy shots don't.
    private let glow = SKSpriteNode(texture: SceneTextures.glow)
    /// Every type flies with the basic shot's art so the screen stays readable; the glow color
    /// still tells the types apart. Only basic (or hot) shots leave a trail.
    static let shotArt = "SpriteShot_Hero_Basic"

    /// Animated projectile art, nose along the flight path.
    private let shot = SKSpriteNode()
    let trail = SKEmitterNode()
    private var squashTime = 1.0
    private var spawnTime = 1.0
    /// Heated by a ricochet: glows red and throbs so the hero sees it coming back.
    private(set) var isHot = false
    private var hotTime = 0.0
    private var radius: CGFloat = 7
    static let hotColor = UIColor(red: 1, green: 0.22, blue: 0.12, alpha: 1)

    override init() {
        super.init()
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.alpha = 0.6

        trail.particleTexture = SceneTextures.spark
        trail.particleLifetime = 0.22
        trail.particleAlpha = 0.75
        trail.particleAlphaSpeed = -3.4
        trail.particleScale = 0.55
        trail.particleScaleSpeed = -2.2
        trail.particleColorBlendFactor = 1
        trail.particleBlendMode = .add
        trail.zPosition = -1
        addChild(trail)
        addChild(glow)
        addChild(shot)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError() }

    func configure(ball: Ball, trailTarget: SKNode) {
        ballID = ball.id
        setType(ball.type, radius: ball.radius)
        trail.targetNode = trailTarget
        trail.resetSimulation()
        alpha = 1
        setScale(1)
        removeAllActions()
        spawnTime = 0
        squashTime = 1
        setHot(ball.isHot)
    }

    func setType(_ newType: BallType, radius: CGFloat) {
        type = newType
        self.radius = radius
        let frames = SpriteAnimations.projectileFrames(Self.shotArt)
        shot.texture = frames[0]
        shot.size = CGSize(width: radius * 6, height: radius * 6)
        shot.run(.repeatForever(.animate(with: frames, timePerFrame: 1.0 / 14)), withKey: "frames")
        applyTint()
    }

    func setHot(_ hot: Bool) {
        guard hot != isHot else { return }
        isHot = hot
        hotTime = 0
        applyTint()
    }

    private func applyTint() {
        let color = isHot ? Self.hotColor : type.uiColor
        glow.color = color
        glow.size = CGSize(width: radius * (isHot ? 6 : 4), height: radius * (isHot ? 6 : 4))
        glow.alpha = isHot ? 0.9 : 0.6
        shot.color = Self.hotColor
        shot.colorBlendFactor = isHot ? 0.7 : 0
        trail.particleColor = color
        trail.particleBirthRate = (type == .basic || isHot) ? 70 : 0
        trail.particleScale = radius / 12 * (isHot ? 1.3 : 0.9)
    }

    /// Velocity is in engine space (y-down).
    func update(velocity: CGVector, dt: Double) {
        let speed = hypot(velocity.dx, velocity.dy)
        // The art points up; turn its nose along the velocity.
        shot.zRotation = atan2(-velocity.dy, velocity.dx) - .pi / 2

        let stretch = min(0.3, speed / 2400)
        squashTime += dt
        let impact = 0.32 * CGFloat(exp(-squashTime * 18) * cos(squashTime * 42))

        spawnTime += dt
        var pop: CGFloat = 1
        if spawnTime < 0.18 {
            // 0.2 → 1.3 overshoot, then settle to 1.
            let p = CGFloat(spawnTime / 0.18)
            pop = p < 0.6 ? 0.2 + 1.1 * (1 - pow(1 - p / 0.6, 2)) : 1.3 - 0.3 * (p - 0.6) / 0.4
        }

        // Local y is the travel direction once rotated.
        shot.yScale = (1 + stretch - impact) * pop
        shot.xScale = (1 - stretch * 0.6 + impact) * pop
        var throb: CGFloat = 1
        if isHot {
            hotTime += dt
            throb = 1 + 0.25 * CGFloat(sin(hotTime * 18))
        }
        glow.setScale(pop * throb)
    }

    /// Impact squash (flattens along the travel direction, then springs back).
    func squash() {
        squashTime = 0
    }
}
