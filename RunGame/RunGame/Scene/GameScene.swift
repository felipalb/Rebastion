import SpriteKit
import UIKit

/// Renders the engine state and turns engine events into juice (particles, numbers, shake, sound, haptics).
/// The engine uses a y-down coordinate system; `point(_:)` converts to SpriteKit's y-up space.
final class GameScene: SKScene {
    let engine: GameEngine
    let feedback: FeedbackHub
    var showDamageNumbers = true

    private let cameraNode = SKCameraNode()
    private let background = SKSpriteNode()
    private let enemyLayer = SKNode()
    private let ballLayer = SKNode()
    private let bulletLayer = SKNode()
    private let fxLayer = SKNode()
    private let textLayer = SKNode()
    private let heroLayer = SKNode()
    private let overlay = SKSpriteNode(color: .white, size: .zero)

    private let hero = SKSpriteNode(color: .clear, size: CGSize(width: 88, height: 88))
    private let heroGlow = SKSpriteNode(texture: SceneTextures.glow)
    private let heroShadow = SKSpriteNode(texture: SceneTextures.glow)
    private lazy var gearRig = HeroGearRig(heroSize: hero.size.width, anchorY: hero.anchorPoint.y)
    private var renderedGear: [HeroGearSlot: UpgradeRarity] = [:]
    private var renderedCharacter: HeroCharacter?
    private var aimDots: [SKSpriteNode] = []
    private let reticle = SKShapeNode(circleOfRadius: 10)
    private let reticleTicks = SKShapeNode()
    /// Reticle turns orange while the player has locked a target by tapping it.
    private var reticleManual = false
    /// Crosshair left where the player tapped empty arena to free-aim.
    private let aimMarker = SKShapeNode(circleOfRadius: 12)
    private static let aimDotCount = 16
    private static let autoAimDots = 7
    private var touchStart: (point: CGPoint, time: TimeInterval)?
    /// Breathing ring around the hero while the ultimate is charged.
    private let pulseAura = SKShapeNode(circleOfRadius: 40)
    /// Soft glows on the side walls during a boss fight, where a shot would bank straight back
    /// into the boss. Teaches wall aiming without a word.
    private let bankHints = [SKSpriteNode(texture: SceneTextures.glow), SKSpriteNode(texture: SceneTextures.glow)]
    private var bankHintAmount: CGFloat = 0
    /// Three orange chevrons behind the fight while the ultimate is charged, lighting one at a
    /// time from the bottom up: the upward swipe that fires it.
    private let ultimateArrows = SKNode()
    private var ultimateArrowAmount: CGFloat = 0
    private static let ultimateArrowCycle = 0.9
    /// Slow neon motes drifting up the empty arena while it doubles as the home screen.
    private let menuMotes = SKEmitterNode()
    private static let menuMoteRate: CGFloat = 1.6

    private var enemyNodes: [Int: EnemyNode] = [:]
    private var ballNodes: [Int: BallNode] = [:]
    private var bulletNodes: [Int: (node: SKSpriteNode, art: String)] = [:]
    private var ballPool: [BallNode] = []
    private var bulletPools: [String: [SKSpriteNode]] = [:]
    private var labelPool: [SKLabelNode] = []
    private var activeLabels = 0
    private var activeEmitters = 0

    private var lastUpdate: TimeInterval?
    private var hitStop = 0.0
    private var slowMotion = 0.0
    private var trauma: CGFloat = 0
    private var sceneTime = 0.0

    // Procedural hero animation state.
    private var heroPrevX: CGFloat?
    private var heroVelocity: CGFloat = 0
    private var runPhase = 0.0
    private var heroFacing: CGFloat = 1
    private var heroTargetFacing: CGFloat = 1
    private var heroRecoil = CGVector.zero
    private var heroRecoilSquash: CGFloat = 0
    private var heroHurtTime = 0.0

    // Frame animation: movement uses the dash frames, launches drive the shoot cycle, damage plays the hit frames.
    private enum HeroPose {
        case idle
        case dashIn
        case dash
        case dashOut
        case shoot
        case shootOut
        case hurt
    }
    private lazy var heroAnimator = FrameAnimator(sprite: hero)
    private var heroPose: HeroPose = .idle
    private var heroDashDirection: CGFloat = 1
    private var heroSlowTime = 0.0
    private var heroLastShot = -10.0
    private var heroAfterimageTimer = 0.0

    init(engine: GameEngine, feedback: FeedbackHub) {
        self.engine = engine
        self.feedback = feedback
        super.init(size: CGSize(width: 390, height: 640))
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = Neon.background
        buildGraph()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: Setup

    private func buildGraph() {
        addChild(cameraNode)
        camera = cameraNode

        background.zPosition = -10
        background.anchorPoint = .zero
        addChild(background)

        for (layer, z) in [(enemyLayer, 1), (ballLayer, 3), (bulletLayer, 4), (fxLayer, 5), (heroLayer, 6), (textLayer, 8)] as [(SKNode, CGFloat)] {
            layer.zPosition = z
            addChild(layer)
        }

        heroShadow.size = CGSize(width: 54, height: 16)
        heroShadow.color = .black
        heroShadow.colorBlendFactor = 1
        heroShadow.alpha = 0.55
        heroShadow.zPosition = -1
        heroLayer.addChild(heroShadow)

        pulseAura.strokeColor = Neon.primary
        pulseAura.lineWidth = 3
        pulseAura.glowWidth = 6
        pulseAura.fillColor = Neon.primary.withAlphaComponent(0.08)
        pulseAura.blendMode = .add
        pulseAura.zPosition = -0.5
        pulseAura.isHidden = true
        heroLayer.addChild(pulseAura)

        for hint in bankHints {
            hint.size = CGSize(width: 40, height: 120)
            hint.color = Neon.primary
            hint.colorBlendFactor = 1
            hint.blendMode = .add
            hint.isHidden = true
            fxLayer.addChild(hint)
        }

        let chevron = UIBezierPath()
        chevron.move(to: CGPoint(x: -44, y: -18))
        chevron.addLine(to: CGPoint(x: 0, y: 18))
        chevron.addLine(to: CGPoint(x: 44, y: -18))
        for i in 0..<3 {
            let arrow = SKShapeNode(path: chevron.cgPath)
            arrow.strokeColor = Neon.heroOrange
            arrow.lineWidth = 11
            arrow.lineCap = .round
            arrow.lineJoin = .round
            arrow.glowWidth = 4
            arrow.blendMode = .add
            arrow.position = CGPoint(x: 0, y: CGFloat(i - 1) * 52)
            ultimateArrows.addChild(arrow)
        }
        ultimateArrows.zPosition = -4
        ultimateArrows.isHidden = true
        addChild(ultimateArrows)

        heroGlow.size = CGSize(width: 110, height: 110)
        heroGlow.color = Neon.primary
        heroGlow.colorBlendFactor = 1
        heroGlow.blendMode = .add
        heroGlow.alpha = 0.25
        heroLayer.addChild(heroGlow)

        // Frames are 512 px with padding; 88 pt keeps the character the size the single sprite had.
        hero.anchorPoint = CGPoint(x: 0.5, y: 0.36)
        heroLayer.addChild(hero)
        hero.addChild(gearRig.back)
        hero.addChild(gearRig.front)
        renderedGear = engine.heroGear
        gearRig.set(renderedGear)
        heroAnimator.play("idle", frames: SpriteAnimations.frames("SpriteHero", "Idle"), fps: 6, playback: .loop)

        SpriteAnimations.enqueue("SpriteHero", actions: SpriteAnimations.heroActions)
        for kind in EnemyKind.allCases {
            SpriteAnimations.enqueue(kind.animationBase)
        }
        let shotArt = [BallNode.shotArt] + EnemyKind.allCases.map(\.shotArt)
            + BossVariant.allCases.map(\.shotArt) + BulletKind.allCases.map(\.art)
        for art in shotArt {
            SpriteAnimations.enqueueProjectile(art)
        }

        for i in 0..<Self.aimDotCount {
            let dot = SKSpriteNode(texture: SceneTextures.spark, size: CGSize(width: 8, height: 8))
            dot.color = Neon.primary
            dot.colorBlendFactor = 1
            dot.blendMode = .add
            dot.alpha = max(0.2, 0.75 - CGFloat(i) * 0.04)
            aimDots.append(dot)
            heroLayer.addChild(dot)
        }

        reticle.strokeColor = Neon.primary.withAlphaComponent(0.8)
        reticle.lineWidth = 2
        reticle.glowWidth = 2
        reticle.zPosition = 2
        reticle.isHidden = true
        let tick = UIBezierPath()
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            tick.move(to: CGPoint(x: cos(angle) * 6, y: sin(angle) * 6))
            tick.addLine(to: CGPoint(x: cos(angle) * 14, y: sin(angle) * 14))
        }
        reticleTicks.path = tick.cgPath
        reticleTicks.strokeColor = Neon.primary
        reticleTicks.lineWidth = 2
        reticle.addChild(reticleTicks)
        reticle.run(.repeatForever(.rotate(byAngle: .pi, duration: 1.4)))
        fxLayer.addChild(reticle)

        aimMarker.strokeColor = Neon.accent
        aimMarker.lineWidth = 3
        aimMarker.glowWidth = 3
        aimMarker.fillColor = Neon.accent.withAlphaComponent(0.15)
        aimMarker.zPosition = 2
        aimMarker.isHidden = true
        let cross = UIBezierPath()
        for (from, to) in [(CGPoint(x: -20, y: 0), CGPoint(x: -6, y: 0)), (CGPoint(x: 6, y: 0), CGPoint(x: 20, y: 0)),
                           (CGPoint(x: 0, y: -20), CGPoint(x: 0, y: -6)), (CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 20))] {
            cross.move(to: from)
            cross.addLine(to: to)
        }
        let crossNode = SKShapeNode(path: cross.cgPath)
        crossNode.strokeColor = Neon.accent
        crossNode.lineWidth = 2
        aimMarker.addChild(crossNode)
        aimMarker.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.45), .scale(to: 1, duration: 0.45)])))
        fxLayer.addChild(aimMarker)

        menuMotes.particleTexture = SceneTextures.spark
        menuMotes.particleBirthRate = Self.menuMoteRate
        menuMotes.particleLifetime = 16
        menuMotes.particleLifetimeRange = 6
        menuMotes.particleSpeed = 34
        menuMotes.particleSpeedRange = 18
        menuMotes.emissionAngle = .pi / 2
        menuMotes.emissionAngleRange = 0.25
        menuMotes.xAcceleration = 0
        menuMotes.particleScale = 0.22
        menuMotes.particleScaleRange = 0.14
        menuMotes.particleBlendMode = .add
        menuMotes.particleColorBlendFactor = 1
        menuMotes.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [Neon.heroBlue, Neon.heroNavy, Neon.heroOrange],
            times: [0, 0.5, 1]
        )
        menuMotes.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0, 0.55, 0.4, 0] as [NSNumber],
            times: [0, 0.15, 0.7, 1]
        )
        menuMotes.zPosition = -5
        addChild(menuMotes)

        overlay.anchorPoint = .zero
        overlay.alpha = 0
        overlay.zPosition = 20
        overlay.blendMode = .alpha
        addChild(overlay)
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        layoutForSize()
        feedback.haptics.prepare()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutForSize()
    }

    private func layoutForSize() {
        guard size.width > 10, size.height > 10 else { return }
        engine.setArenaSize(size)
        background.texture = SceneTextures.background(size: size, dangerLineY: engine.heroY)
        background.size = size
        background.position = .zero
        overlay.size = CGSize(width: size.width + 80, height: size.height + 80)
        overlay.position = CGPoint(x: -40, y: -40)
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        ultimateArrows.position = CGPoint(x: size.width / 2, y: size.height / 2)
        // Motes rise from just under the defense line and fill the arena from the first frame.
        menuMotes.position = CGPoint(x: size.width / 2, y: size.height - engine.heroY - 30)
        menuMotes.particlePositionRange = CGVector(dx: size.width, dy: 0)
        menuMotes.resetSimulation()
        menuMotes.advanceSimulationTime(12)
    }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: size.height - p.y)
    }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        let raw = min(1.0 / 30.0, currentTime - (lastUpdate ?? currentTime))
        lastUpdate = currentTime
        var dt = raw
        if slowMotion > 0 {
            slowMotion -= raw
            dt *= 0.35
        }
        sceneTime += raw
        // Leaving the home screen stops new motes; the ones in flight drift away on their own.
        menuMotes.particleBirthRate = engine.phase == .menu ? Self.menuMoteRate : 0

        if hitStop > 0 {
            hitStop -= raw
        } else {
            engine.update(deltaTime: dt)
        }

        // Hit-stop freezes the procedural animation too, so impacts read as a beat.
        let animDT = hitStop > 0 ? 0 : dt
        SpriteAnimations.warmUp()
        handle(engine.drainEvents())
        syncEnemies(animDT)
        syncBalls(animDT)
        syncBullets()
        syncHero(raw)
        syncBankHints(raw)
        syncUltimateArrows(raw)
        updateShake(raw)
    }

    // MARK: Sync

    private func syncEnemies(_ dt: Double) {
        var alive = Set<Int>()
        for enemy in engine.enemies {
            alive.insert(enemy.id)
            let node: EnemyNode
            if let existing = enemyNodes[enemy.id] {
                node = existing
            } else {
                node = EnemyNode(enemy: enemy)
                node.onCue = { [weak self] cue, node in self?.enemyCue(cue, node: node) }
                enemyNodes[enemy.id] = node
                enemyLayer.addChild(node)
            }
            node.position = point(enemy.position)
            node.sync(enemy, dt: dt, lineY: engine.heroY)
        }
        for (id, node) in enemyNodes where !alive.contains(id) {
            node.die()
            enemyNodes[id] = nil
        }
    }

    private func syncBalls(_ dt: Double) {
        var alive = Set<Int>()
        for ball in engine.balls {
            alive.insert(ball.id)
            let node: BallNode
            if let existing = ballNodes[ball.id] {
                node = existing
                if node.type != ball.type { node.setType(ball.type, radius: ball.radius) }
            } else {
                node = ballPool.popLast() ?? BallNode()
                node.configure(ball: ball, trailTarget: fxLayer)
                ballNodes[ball.id] = node
                ballLayer.addChild(node)
            }
            node.setHot(ball.isHot)
            node.position = point(ball.position)
            node.update(velocity: ball.velocity, dt: dt)
        }
        for (id, node) in ballNodes where !alive.contains(id) {
            fadeGhost(at: node.position, color: node.isHot ? BallNode.hotColor : node.type.uiColor, size: 22)
            node.removeFromParent()
            ballNodes[id] = nil
            if ballPool.count < 64 { ballPool.append(node) }
        }
    }

    private func syncBullets() {
        var alive = Set<Int>()
        for bullet in engine.bullets {
            alive.insert(bullet.id)
            let node: SKSpriteNode
            if let existing = bulletNodes[bullet.id] {
                node = existing.node
            } else {
                node = bulletPools[bullet.art]?.popLast() ?? makeBulletNode(bullet.kind, art: bullet.art)
                // Splitting shots read bigger, their shards smaller.
                node.setScale(bullet.radius / bullet.kind.radius)
                bulletNodes[bullet.id] = (node, bullet.art)
                bulletLayer.addChild(node)
            }
            node.position = point(bullet.position)
            if let shot = node.childNode(withName: Self.aimedShotName) {
                // Shooter art points up; turn its nose along the flight path (engine space is y-down).
                shot.zRotation = atan2(-bullet.velocity.dy, bullet.velocity.dx) - .pi / 2
            }
            // A cracked heavy shot shrinks so the player sees it is one hit from breaking.
            if bullet.health < bullet.kind.health { node.setScale(0.75) }
            // A mortar throbs faster and faster as its fuse runs out.
            if bullet.trick == .fuse {
                let fuse = min(1, bullet.age / ShotTrick.fuseTime)
                let throb = 1 + 0.2 * fuse * sin(bullet.age * (8 + 30 * fuse))
                node.setScale(bullet.radius / bullet.kind.radius * CGFloat(throb))
            }
        }
        for (id, entry) in bulletNodes where !alive.contains(id) {
            entry.node.removeFromParent()
            bulletNodes[id] = nil
            if bulletPools[entry.art, default: []].count < 160 { bulletPools[entry.art, default: []].append(entry.node) }
        }
    }

    private static let aimedShotName = "aimedShot"

    /// Enemy shots: animated projectile art over a flashing halo, sized well above the player's
    /// balls so the eye can single them out in a crowded screen. Standard shots wear the
    /// shooter's own art and fly nose-first; the tougher kinds keep a shared, spinning look and
    /// halo color so unbreakable and dangerous shots read at a glance.
    private func makeBulletNode(_ kind: BulletKind, art: String) -> SKSpriteNode {
        let (haloColor, side, spin, beat): (UIColor, CGFloat, Double, Double) = switch kind {
        case .standard: (UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 1), art.contains("Boss") ? 42 : 36, 0, 0.14)
        case .armored: (UIColor(red: 0.6, green: 0.2, blue: 1, alpha: 1), 40, 1.6, 0.2)
        case .heavy: (UIColor(red: 1, green: 0.5, blue: 0, alpha: 1), 50, 1.1, 0.18)
        case .lethal: (UIColor(red: 1, green: 0, blue: 0.25, alpha: 1), 55, 0.5, 0.09)
        }
        let node = SKSpriteNode(color: .clear, size: CGSize(width: side + 2, height: side + 2))
        let halo = SKSpriteNode(texture: SceneTextures.glow, size: CGSize(width: side * 1.6, height: side * 1.6))
        halo.color = haloColor
        halo.colorBlendFactor = 1
        halo.blendMode = .add
        halo.alpha = 0.7
        halo.run(.repeatForever(.sequence([
            .group([.scale(to: 1.2, duration: beat), .fadeAlpha(to: 0.95, duration: beat)]),
            .group([.scale(to: 0.85, duration: beat), .fadeAlpha(to: 0.45, duration: beat)]),
        ])))
        node.addChild(halo)
        if kind == .lethal {
            // Contracting warning ring so the run-ending shot is impossible to miss.
            let warning = SKShapeNode(circleOfRadius: side * 0.75)
            warning.strokeColor = .white
            warning.lineWidth = 2
            warning.fillColor = .clear
            warning.run(.repeatForever(.sequence([
                .group([.scale(to: 1.5, duration: 0), .fadeAlpha(to: 0, duration: 0)]),
                .group([.scale(to: 1, duration: 0.35), .fadeAlpha(to: 0.9, duration: 0.35)]),
            ])))
            node.addChild(warning)
        }
        let frames = SpriteAnimations.projectileFrames(art)
        let shot = SKSpriteNode(texture: frames[0], size: CGSize(width: side, height: side))
        shot.zPosition = 1
        shot.run(.repeatForever(.animate(with: frames, timePerFrame: 1.0 / 12)))
        if spin > 0 {
            shot.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: spin)))
        } else {
            shot.name = Self.aimedShotName
        }
        node.addChild(shot)
        return node
    }

    private func syncHero(_ dt: Double) {
        let position = point(engine.heroPosition)

        // Horizontal velocity drives lean, run bob and facing.
        let instant = heroPrevX.map { (engine.heroX - $0) / CGFloat(max(dt, 0.001)) } ?? 0
        heroPrevX = engine.heroX
        heroVelocity += (instant - heroVelocity) * CGFloat(min(1, dt * 12))
        let moving = min(1, abs(heroVelocity) / 220)
        runPhase += dt * 14 * Double(moving)

        updateHeroPose(dt)

        // Idle art faces left: flip when aiming (or moving) right. Dash and shoot frames are already directional.
        let aimX = cos(engine.aimAngle)
        if engine.aimTargetID != nil, abs(aimX) > 0.3 {
            heroTargetFacing = aimX > 0 ? -1 : 1
        } else if abs(heroVelocity) > 40 {
            heroTargetFacing = heroVelocity > 0 ? -1 : 1
        }
        heroFacing += (heroTargetFacing - heroFacing) * CGFloat(min(1, dt * 22))
        // Keep some width mid-turn so the flip reads as a quick turn, not a paper-thin sprite.
        let facingScale = heroPose == .idle ? (heroFacing >= 0 ? 1 : -1) * max(0.45, abs(heroFacing)) : 1

        let recoilDecay = CGFloat(exp(-dt * 14))
        heroRecoil.dx *= recoilDecay
        heroRecoil.dy *= recoilDecay
        heroRecoilSquash *= CGFloat(exp(-dt * 12))
        heroHurtTime = max(0, heroHurtTime - dt)

        // The frames carry gait and breathing; these only add weight on top.
        let breath = CGFloat(sin(sceneTime * 2.6))
        let breathAmount: CGFloat = heroPose == .idle ? 0.015 : 0
        let bob = heroPose == .idle ? CGFloat(abs(sin(runPhase))) * 2 * moving : 0
        let hurtWobble = CGFloat(sin(heroHurtTime * 60) * heroHurtTime / 0.35) * 0.2
        let lean: CGFloat = heroPose == .dash ? 0.06 : 0.12

        hero.position = CGPoint(x: position.x + heroRecoil.dx, y: position.y + heroRecoil.dy + bob)
        hero.xScale = facingScale * (1 - breath * breathAmount * 0.5 + heroRecoilSquash * 0.75)
        hero.yScale = 1 + breath * breathAmount - heroRecoilSquash
        hero.zRotation = max(-0.18, min(0.18, -heroVelocity / 220 * lean)) + hurtWobble

        let stretch = heroPose == .dash ? min(0.35, abs(heroVelocity) / 900) : 0
        heroShadow.position = CGPoint(x: position.x + heroRecoil.dx * 0.5 - heroVelocity * 0.02, y: position.y - 19)
        heroShadow.xScale = 1 - bob * 0.05 - breath * 0.03 + stretch
        heroShadow.yScale = 1 - bob * 0.05 - breath * 0.03
        heroShadow.alpha = 0.55 - bob * 0.04

        heroGlow.position = CGPoint(x: position.x, y: position.y + bob)
        hero.alpha = engine.heroInvulnerability > 0 ? (sin(sceneTime * 32) > 0 ? 0.35 : 1) : 1
        heroGlow.alpha = 0.18 + 0.04 * breath + 0.1 * CGFloat(engine.specialEnergy) + (engine.canPulse ? 0.15 * CGFloat(sin(sceneTime * 6) + 1) : 0)
        heroGlow.setScale(1 + breath * 0.04)
        pulseAura.isHidden = !engine.canPulse
        if engine.canPulse {
            let beat = CGFloat(sin(sceneTime * 7))
            pulseAura.position = CGPoint(x: position.x, y: position.y + 14 + bob)
            pulseAura.setScale(1 + 0.08 * beat)
            pulseAura.alpha = 0.7 + 0.3 * beat
            pulseAura.strokeColor = beat > 0 ? engine.config.ultimate.tint : .white
        }

        if renderedCharacter != engine.config.character {
            let swapped = renderedCharacter != nil
            renderedCharacter = engine.config.character
            heroGlow.color = engine.config.character.tint
            if swapped { heroTransform() }
        }
        if heroHurtTime > 0 {
            hero.color = Neon.coral
            hero.colorBlendFactor = 0.75 * CGFloat(heroHurtTime / 0.35)
        } else {
            hero.color = engine.config.character.tint
            hero.colorBlendFactor = engine.config.character == .vanguard ? 0 : 0.35
        }
        updateGear(dt)

        let freeAim = engine.manualAimPoint
        let showAim = engine.phase == .playing && (engine.aimTargetID != nil || freeAim != nil)
        // Same clamp the engine applies at launch, so the guide shows where balls really go.
        let angle = min(max(engine.aimAngle, -.pi + 0.22), -0.22)
        let origin = CGPoint(x: engine.heroX, y: engine.heroY - 18)
        let width = engine.arenaSize.width
        let visibleDots = freeAim == nil ? Self.autoAimDots : Self.aimDotCount
        for (i, dot) in aimDots.enumerated() {
            dot.isHidden = !showAim || i >= visibleDots
            let distance = 34 + CGFloat(i) * 17 + CGFloat(fmod(sceneTime * 40, 17))
            // Free aim previews the bank shot: the guide folds back off the side walls.
            var x = origin.x + cos(angle) * distance
            if freeAim != nil, width > 0 {
                x = x.truncatingRemainder(dividingBy: 2 * width)
                if x < 0 { x += 2 * width }
                if x > width { x = 2 * width - x }
            }
            dot.position = point(CGPoint(x: x, y: origin.y + sin(angle) * distance))
        }
        if engine.phase == .playing, let freeAim {
            aimMarker.isHidden = false
            aimMarker.position = point(freeAim)
        } else {
            aimMarker.isHidden = true
        }
        let manual = engine.manualTargetID != nil || freeAim != nil
        if manual != reticleManual {
            reticleManual = manual
            let color = manual ? Neon.accent : Neon.primary
            reticle.strokeColor = color.withAlphaComponent(manual ? 1 : 0.8)
            reticle.lineWidth = manual ? 3 : 2
            reticleTicks.strokeColor = color
            reticleTicks.lineWidth = manual ? 3 : 2
            aimDots.forEach { $0.color = color }
        }
        if showAim, let id = engine.aimTargetID, let target = engine.enemies.first(where: { $0.id == id }) {
            reticle.isHidden = false
            reticle.position = point(target.position)
            reticle.setScale((target.radius + (manual ? 14 : 8)) / 10)
        } else {
            reticle.isHidden = true
        }
    }

    private func syncBankHints(_ dt: Double) {
        let boss = engine.phase == .playing ? engine.enemies.first { $0.kind == .boss } : nil
        bankHintAmount += ((boss == nil ? 0 : 1) - bankHintAmount) * CGFloat(min(1, dt * 3))
        let visible = bankHintAmount > 0.01
        bankHints.forEach { $0.isHidden = !visible }
        guard visible else { return }
        if let boss {
            // Mirror the boss across each side wall: the line from the launch point to the mirror
            // crosses the wall exactly where the ball must hit to fly back into the boss.
            let origin = CGPoint(x: engine.heroX, y: engine.heroY - 18)
            let width = engine.arenaSize.width
            let toWall = [origin.x, width - origin.x]
            let bossToWall = [boss.position.x, width - boss.position.x]
            for (i, hint) in bankHints.enumerated() {
                let t = toWall[i] / max(1, toWall[i] + bossToWall[i])
                let y = origin.y + t * (boss.position.y - origin.y)
                hint.position = point(CGPoint(x: i == 0 ? 0 : width, y: y))
            }
        }
        let breath = 0.75 + 0.25 * CGFloat(sin(sceneTime * 3))
        bankHints.forEach { $0.alpha = 0.5 * bankHintAmount * breath }
    }

    private func syncUltimateArrows(_ dt: Double) {
        ultimateArrowAmount += ((engine.canPulse ? 1 : 0) - ultimateArrowAmount) * CGFloat(min(1, dt * 6))
        let visible = ultimateArrowAmount > 0.01
        ultimateArrows.isHidden = !visible
        guard visible else { return }
        let phase = sceneTime.truncatingRemainder(dividingBy: Self.ultimateArrowCycle) / Self.ultimateArrowCycle
        // Children run bottom to top; each flares on its third of the cycle and fades over the next.
        for (i, arrow) in ultimateArrows.children.enumerated() {
            let since = (phase - Double(i) / 3 + 1).truncatingRemainder(dividingBy: 1)
            let lit = CGFloat(max(0, 1 - since * 3))
            arrow.alpha = (0.12 + 0.48 * lit) * ultimateArrowAmount
        }
    }

    // MARK: Hero frame animation

    private func heroFrames(_ action: String) -> [SKTexture] {
        SpriteAnimations.frames("SpriteHero", action)
    }

    private var heroIsDashing: Bool { heroPose == .dashIn || heroPose == .dash }

    /// Movement → dash (anticipation, blur loop, brake); launches → shoot cycle; otherwise idle.
    private func updateHeroPose(_ dt: Double) {
        let speed = abs(heroVelocity)
        let direction: CGFloat = heroVelocity >= 0 ? 1 : -1
        let shooting = sceneTime - heroLastShot < 0.32

        // Taking damage holds the hit frames to the end before anything else takes over.
        if heroPose == .hurt {
            guard heroAnimator.isFinished else {
                heroAnimator.update(hitStop > 0 ? 0 : dt)
                return
            }
            if shooting {
                enterHeroShoot(fade: 0.05)
            } else {
                enterHeroIdle(fade: 0.08)
            }
        }

        if heroIsDashing {
            heroSlowTime = speed < 40 ? heroSlowTime + dt : 0
        }
        let wantsDash = heroIsDashing ? heroSlowTime < 0.06 : speed > 75

        if wantsDash {
            if !heroIsDashing || direction != heroDashDirection {
                startHeroDash(direction: direction, reversing: heroIsDashing)
            } else if heroPose == .dashIn, heroAnimator.isFinished {
                heroPose = .dash
                heroAnimator.play("dash", frames: heroFrames(heroDashDirection > 0 ? "DashRight" : "DashLeft"), sequence: [1, 2], fps: 16, playback: .loop)
            }
            heroAfterimageTimer -= dt
            if heroAfterimageTimer <= 0 {
                heroAfterimageTimer = 0.035
                spawnHeroAfterimage()
            }
        } else if heroIsDashing {
            // Brake on the landing frame and kick up dust ahead of the feet.
            heroPose = .dashOut
            heroAnimator.play("dashOut", frames: heroFrames(heroDashDirection > 0 ? "DashRight" : "DashLeft"), sequence: [3], fps: 9, playback: .once)
            heroDust(direction: heroDashDirection, count: 8)
            // Come out of the dash facing the way it went (idle art faces left).
            heroFacing = heroDashDirection > 0 ? -1 : 1
            heroTargetFacing = heroFacing
        } else {
            switch heroPose {
            case .dashOut where heroAnimator.isFinished:
                if shooting {
                    enterHeroShoot(fade: 0.05)
                } else {
                    enterHeroIdle(fade: heroFacing >= 0 ? 0.1 : 0)
                }
            case .shoot where !shooting:
                heroPose = .shootOut
                heroAnimator.play("shootOut", frames: heroFrames("Shoot"), sequence: [0], fps: 9, playback: .once, fade: 0.06)
            case .shootOut where heroAnimator.isFinished:
                enterHeroIdle(fade: heroFacing >= 0 ? 0.12 : 0)
            default:
                break
            }
        }
        heroAnimator.update(hitStop > 0 ? 0 : dt)
    }

    private func startHeroDash(direction: CGFloat, reversing: Bool) {
        heroPose = .dashIn
        heroDashDirection = direction
        heroSlowTime = 0
        heroAfterimageTimer = 0
        heroAnimator.play("dashIn", frames: heroFrames(direction > 0 ? "DashRight" : "DashLeft"), sequence: [0], fps: 20, playback: .once, fade: reversing ? 0 : 0.05)
        heroDust(direction: -direction, count: reversing ? 12 : 8)
        if reversing {
            // Hard cut back: a squash and a flare at the feet.
            heroRecoilSquash = 0.12
            flare(at: CGPoint(x: hero.position.x, y: hero.position.y - 14), color: engine.config.character.tint, size: 30, duration: 0.12)
        }
    }

    private func enterHeroIdle(fade: Double) {
        heroPose = .idle
        heroAnimator.play("idle", frames: heroFrames("Idle"), fps: 6, playback: .loop, fade: fade)
    }

    private func enterHeroHurt() {
        heroPose = .hurt
        heroAnimator.play("hurt", frames: heroFrames("Hit"), fps: 14, playback: .once, fade: 0.03)
    }

    private func enterHeroShoot(fade: Double) {
        heroPose = .shoot
        // Fire → recoil → charge, then hold the charge until the next launch restarts it.
        heroAnimator.play("shoot", frames: heroFrames("Shoot"), sequence: [2, 3, 1], fps: 22, playback: .once, fade: fade)
    }

    /// Called for every launch, in sync with the muzzle flash.
    private func heroDidShoot(color: UIColor) {
        heroLastShot = sceneTime
        guard !heroIsDashing, heroPose != .dashOut, heroPose != .hurt else { return }
        enterHeroShoot(fade: heroPose == .shoot ? 0 : 0.04)
        // Twin shoulder cannons flare on the firing frame.
        for side: CGFloat in [-1, 1] {
            let tip = CGPoint(x: hero.position.x + side * 20, y: hero.position.y + 38)
            flare(at: tip, color: color, size: 22, duration: 0.08, rotation: .pi / 2)
        }
    }

    /// Picking another character on the home screen: the hero flashes into the new color.
    private func heroTransform() {
        let tint = engine.config.character.tint
        let center = CGPoint(x: hero.position.x, y: hero.position.y + 14)
        heroRecoilSquash = 0.14
        flare(at: center, color: tint, size: 110, duration: 0.3)
        ring(at: center, color: tint, from: 12, to: 90, duration: 0.4, width: 4)
        burst(at: center, color: tint, count: 22, speed: 170, lifetime: 0.5, scale: 0.4, angle: .pi / 2, spread: .pi)
        feedback.sound.play(.select, volume: 0.6)
        feedback.haptics.impact(.medium)
    }

    private func spawnHeroAfterimage() {
        guard let texture = hero.texture else { return }
        let ghost = SKSpriteNode(texture: texture, size: hero.size)
        ghost.anchorPoint = hero.anchorPoint
        ghost.position = hero.position
        ghost.zRotation = hero.zRotation
        ghost.xScale = hero.xScale
        ghost.yScale = hero.yScale
        ghost.color = engine.config.character.tint
        ghost.colorBlendFactor = 1
        ghost.blendMode = .add
        ghost.alpha = 0.35
        ghost.zPosition = -0.5
        heroLayer.addChild(ghost)
        ghost.run(.sequence([
            .group([.fadeOut(withDuration: 0.2), .scaleX(to: hero.xScale * 0.9, duration: 0.2)]),
            .removeFromParent(),
        ]))
    }

    /// Dust kicked from the hero's feet; `direction` is where it flies (±1 horizontally).
    private func heroDust(direction: CGFloat, count: Int) {
        let feet = CGPoint(x: hero.position.x, y: point(engine.heroPosition).y - 17)
        burst(at: feet, color: UIColor(white: 0.85, alpha: 1), count: count, speed: 110, lifetime: 0.3, scale: 0.35, angle: direction > 0 ? 0.25 : .pi - 0.25, spread: 0.9)
    }

    private func enemyCue(_ cue: EnemyNode.Cue, node: EnemyNode) {
        switch cue {
        case .landed:
            let feet = CGPoint(x: node.position.x, y: node.position.y - node.kind.radius * 0.9)
            ring(at: feet, color: .white, from: 20, to: 140, duration: 0.35, width: 5)
            burst(at: feet, color: UIColor(white: 0.85, alpha: 1), count: 18, speed: 200, lifetime: 0.4, scale: 0.5, angle: 0, spread: .pi * 2)
            addTrauma(0.3)
            feedback.haptics.impact(.heavy)
        }
    }

    // MARK: Hero gear

    private func updateGear(_ dt: Double) {
        // Equip events keep this in step; a new run clears the armor without one.
        if renderedGear != engine.heroGear {
            renderedGear = engine.heroGear
            gearRig.set(renderedGear)
        }
        let pose: HeroGearRig.Pose = switch heroPose {
        case .idle: .idle
        case .dashIn, .dash, .dashOut: heroDashDirection > 0 ? .dashRight : .dashLeft
        case .shoot, .shootOut: .shoot
        case .hurt: .hit
        }
        let hurt = heroHurtTime > 0 ? 0.75 * CGFloat(heroHurtTime / 0.35) : 0
        gearRig.update(
            pose: pose,
            frame: heroAnimator.frame,
            dt: hitStop > 0 ? 0 : dt,
            tint: Neon.coral,
            tintAmount: hurt
        )
    }

    private func gearEquipped(_ slot: HeroGearSlot, rarity: UpgradeRarity) {
        renderedGear[slot] = rarity
        gearRig.equip(slot, rarity: rarity)
        let color = rarity.uiColor
        let center = CGPoint(x: hero.position.x, y: hero.position.y + 16)
        let big = rarity >= .legendary
        ring(at: center, color: color, from: 8, to: big ? 150 : 100, duration: 0.5, width: big ? 6 : 4)
        burst(at: center, color: color, count: big ? 34 : 18, speed: big ? 260 : 180, lifetime: 0.6, scale: 0.55)
        flare(at: center, color: color, size: big ? 90 : 60, duration: 0.2)
        if rarity == .fusion {
            // Fusion pieces get the whole spectrum.
            for (i, hue) in stride(from: 0.0, to: 1.0, by: 1.0 / 6).enumerated() {
                let tint = UIColor(hue: hue, saturation: 0.8, brightness: 1, alpha: 1)
                run(.wait(forDuration: Double(i) * 0.05)) { [weak self] in
                    guard let self else { return }
                    ring(at: center, color: tint, from: 10, to: 70 + CGFloat(i) * 22, duration: 0.45, width: 3)
                }
            }
        }
        gearLabel("\(slot.title) · \(rarity.label)", color: color, at: CGPoint(x: hero.position.x, y: hero.position.y + 66))
        switch rarity {
        case .common, .rare:
            feedback.sound.play(.select)
            feedback.haptics.impact(.medium)
        case .legendary:
            feedback.sound.play(.levelUp)
            feedback.haptics.impact(.heavy)
            addTrauma(0.25)
        case .fusion:
            feedback.sound.play(.fusion)
            feedback.haptics.notify(.success)
            addTrauma(0.35)
        }
    }

    private func gearSetCompleted(_ rarity: UpgradeRarity) {
        let color = rarity.uiColor
        let ghost = SKSpriteNode(texture: GearTextures.texture(gearRig.equippedHeroName(rarity)), size: hero.size)
        ghost.anchorPoint = hero.anchorPoint
        ghost.position = hero.position
        ghost.xScale = hero.xScale < 0 ? -1 : 1
        ghost.color = color
        ghost.colorBlendFactor = 0.6
        ghost.blendMode = .add
        ghost.alpha = 0.9
        ghost.zPosition = 1
        heroLayer.addChild(ghost)
        let grow = SKAction.scaleX(to: ghost.xScale * 2.4, y: 2.4, duration: 0.8)
        grow.timingMode = .easeOut
        ghost.run(.sequence([.group([grow, .fadeOut(withDuration: 0.8)]), .removeFromParent()]))

        let center = CGPoint(x: hero.position.x, y: hero.position.y + 16)
        ring(at: center, color: color, from: 10, to: max(size.width, size.height) * 0.6, duration: 0.8, width: 8)
        ring(at: center, color: .white, from: 10, to: 200, duration: 0.5, width: 4)
        burst(at: center, color: color, count: 60, speed: 340, lifetime: 0.9, scale: 0.7)
        screenFlash(color: color, alpha: 0.3)
        feedback.sound.play(.fusion)
        feedback.haptics.notify(.success)
        addTrauma(0.4)
    }

    /// Big floating text above the hero for things the player must notice (lives, ultimate).
    private func ultimateBlast(_ kind: UltimateKind, at p: CGPoint) {
        let reach = max(size.width, size.height)
        heroCallout(kind.title.uppercased(), color: kind.tint, size: 28)
        switch kind {
        case .pulse:
            ring(at: p, color: .white, from: 20, to: reach * 1.1, duration: 0.55, width: 10)
            ring(at: p, color: kind.tint, from: 10, to: reach * 0.8, duration: 0.45, width: 6)
            screenFlash(color: .white, alpha: 0.45)
            addTrauma(0.55)
        case .stasis:
            ring(at: p, color: kind.tint, from: 20, to: reach * 1.2, duration: 0.8, width: 14)
            ring(at: p, color: .white, from: 10, to: reach * 0.6, duration: 0.5, width: 4)
            screenFlash(color: kind.tint, alpha: 0.4)
            addTrauma(0.25)
        case .storm:
            screenFlash(color: kind.tint, alpha: 0.35)
            addTrauma(0.7)
        case .swarm:
            ring(at: p, color: kind.tint, from: 10, to: 140, duration: 0.4, width: 6)
            burst(at: p, color: kind.tint, count: 40, speed: 280, lifetime: 0.5, scale: 0.5, angle: .pi / 2, spread: .pi * 0.8)
            addTrauma(0.35)
        }
        feedback.sound.play(.pulse)
        feedback.haptics.impact(.heavy)
    }

    private func heroCallout(_ text: String, color: UIColor, size fontSize: CGFloat) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.text = text
        label.fontSize = fontSize
        label.fontColor = color
        label.position = CGPoint(x: min(max(hero.position.x, 70), size.width - 70), y: hero.position.y + 80)
        label.setScale(0.4)
        label.zPosition = 2
        let shadow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        shadow.verticalAlignmentMode = .center
        shadow.horizontalAlignmentMode = .center
        shadow.text = text
        shadow.fontSize = fontSize
        shadow.fontColor = .black
        shadow.alpha = 0.7
        shadow.position = CGPoint(x: 1.5, y: -2)
        shadow.zPosition = -1
        label.addChild(shadow)
        textLayer.addChild(label)
        let pop = SKAction.sequence([.scale(to: 1.25, duration: 0.12), .scale(to: 1, duration: 0.1)])
        let rise = SKAction.moveBy(x: 0, y: 36, duration: 1.2)
        rise.timingMode = .easeOut
        label.run(.sequence([
            .group([pop, rise, .sequence([.wait(forDuration: 0.85), .fadeOut(withDuration: 0.35)])]),
            .removeFromParent(),
        ]))
    }

    private func gearLabel(_ text: String, color: UIColor, at position: CGPoint) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.text = text
        label.fontSize = 14
        label.fontColor = color
        label.position = position
        label.setScale(0.5)
        textLayer.addChild(label)
        let rise = SKAction.moveBy(x: 0, y: 30, duration: 1.1)
        rise.timingMode = .easeOut
        label.run(.sequence([
            .group([rise, .sequence([.scale(to: 1.15, duration: 0.1), .scale(to: 1, duration: 0.1)])]),
            .removeFromParent(),
        ]))
        label.run(.sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.4)]))
    }

    // MARK: Events → juice

    private func handle(_ events: [GameEvent]) {
        let sound = feedback.sound
        let haptics = feedback.haptics
        for event in events {
            switch event {
            case let .ballLaunched(type, origin, angle):
                muzzleFlash(at: point(origin), angle: -angle, color: type.uiColor)
                heroDidShoot(color: type.uiColor)
                sound.play(.launch, volume: 0.3)
            case let .wallBounce(position):
                wallImpact(at: position)
                sound.play(.bounce, volume: 0.25)
            case let .hit(enemyID, position, damage, critical, type):
                let p = point(position)
                hitImpact(at: p, enemy: enemyNodes[enemyID], color: type.uiColor, critical: critical)
                damageLabel(damage, at: p, color: critical ? Neon.gold : .white, critical: critical)
                if critical {
                    sound.play(.crit, volume: 0.7)
                    haptics.impact(.rigid, intensity: 0.7, minInterval: 0.08)
                    addTrauma(0.06)
                } else {
                    sound.play(.hit, variant: min(11, engine.combo / 3), volume: 0.55)
                    haptics.impact(.light, intensity: 0.45, minInterval: 0.07)
                }
            case let .dot(position, damage, type):
                damageLabel(damage, at: point(position), color: type.uiColor, critical: false, small: true)
            case let .shieldBlock(position):
                burst(at: point(position), color: Neon.cyan, count: 6, speed: 140, lifetime: 0.2, scale: 0.3)
                sound.play(.shield, volume: 0.6)
            case let .chain(from, to, type):
                lightning(from: point(from), to: point(to), color: type.uiColor)
                sound.play(.zap, volume: 0.5)
            case let .explosion(position, radius, type):
                explosion(at: point(position), radius: radius, color: type.uiColor)
                sound.play(.explosion, volume: 0.7)
                haptics.impact(.medium, intensity: 0.7, minInterval: 0.08)
                addTrauma(0.12)
            case let .freeze(position):
                burst(at: point(position), color: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 1), count: 10, speed: 90, lifetime: 0.4, scale: 0.4)
                sound.play(.freeze, volume: 0.6)
            case let .enemyKilled(position, kind, elite, radius, _):
                let p = point(position)
                burst(at: p, color: kind.particleColor, count: elite ? 40 : 18, speed: elite ? 260 : 170, lifetime: elite ? 0.7 : 0.45, scale: elite ? 0.8 : 0.55)
                ring(at: p, color: kind.particleColor, from: radius * 0.6, to: radius * 2.2, duration: 0.25, width: 3)
                if elite || kind == .boss {
                    sound.play(.eliteKill)
                    haptics.impact(.heavy, minInterval: 0.08)
                    hitStop = max(hitStop, 0.045)
                    addTrauma(0.18)
                } else {
                    sound.play(.kill, volume: 0.6)
                    haptics.impact(.medium, intensity: 0.5, minInterval: 0.06)
                }
            case let .enemyEscaped(position):
                screenFlash(color: Neon.coral, alpha: 0.35)
                burst(at: point(position), color: Neon.coral, count: 20, speed: 200, lifetime: 0.5, scale: 0.6)
                sound.play(.hurt)
                haptics.notify(.error)
                addTrauma(0.35)
            case let .enemyShot(position):
                nearestEnemyNode(to: point(position), within: 80)?.attack()
                sound.play(.enemyShot, volume: 0.4)
            case let .bulletBlocked(position):
                let p = point(position)
                flare(at: p, color: Neon.coral, size: 26, duration: 0.1)
                burst(at: p, color: Neon.coral, count: 4, speed: 80, lifetime: 0.18, scale: 0.25)
                nearestBallNode(to: p, within: 24)?.squash()
            case let .shotBurst(position, ring):
                let p = point(position)
                flare(at: p, color: Neon.coral, size: ring ? 44 : 22, duration: ring ? 0.18 : 0.1)
                burst(at: p, color: Neon.coral, count: ring ? 10 : 4, speed: ring ? 120 : 70, lifetime: 0.22, scale: 0.25)
                if ring { addTrauma(0.12) }
            case let .heroHurt(damage, lethal):
                heroHurtTime = 0.35
                enterHeroHurt()
                heroRecoil = CGVector(dx: 0, dy: lethal ? -12 : -6)
                heroRecoilSquash = 0.14
                screenFlash(color: lethal ? .white : Neon.coral, alpha: lethal ? 0.8 : (damage > 1 ? 0.6 : 0.45))
                burst(at: hero.position, color: Neon.coral, count: lethal ? 60 : 24 * damage, speed: 220, lifetime: 0.5, scale: 0.6)
                heroCallout(lethal ? "FATAL!" : "−\(damage) ♥", color: Neon.coral, size: lethal ? 34 : (damage > 1 ? 30 : 26))
                sound.play(.hurt)
                haptics.notify(.error)
                addTrauma(lethal ? 1 : (damage > 1 ? 0.7 : 0.5))
            case .heal:
                ring(at: hero.position, color: Neon.lime, from: 10, to: 70, duration: 0.45, width: 4)
                heroCallout("+1 ♥", color: Neon.lime, size: 24)
                sound.play(.heal)
                haptics.notify(.success)
            case let .ultimate(kind, position):
                ultimateBlast(kind, at: point(position))
            case .pulseReady:
                let center = CGPoint(x: hero.position.x, y: hero.position.y + 14)
                let tint = engine.config.ultimate.tint
                ring(at: center, color: tint, from: 10, to: 110, duration: 0.5, width: 5)
                ring(at: center, color: .white, from: 10, to: 160, duration: 0.7, width: 3)
                burst(at: center, color: tint, count: 24, speed: 200, lifetime: 0.5, scale: 0.5)
                if engine.config.coachUltimate {
                    heroCallout("ULTIMATE PRONTA!", color: tint, size: 22)
                }
                sound.play(.combo, variant: 3)
                haptics.notify(.success)
            case .targetLocked(_, let position):
                let center = point(position)
                ring(at: center, color: Neon.accent, from: 60, to: 14, duration: 0.25, width: 4)
                burst(at: center, color: Neon.accent, count: 10, speed: 120, lifetime: 0.3, scale: 0.35)
                sound.play(.select)
                haptics.impact(.rigid, intensity: 0.8)
            case let .aimPointSet(position):
                let center = point(position)
                ring(at: center, color: Neon.accent, from: 44, to: 10, duration: 0.22, width: 3)
                sound.play(.select, volume: 0.7)
                haptics.impact(.rigid, intensity: 0.6)
            case .targetReleased:
                sound.play(.select, volume: 0.5)
                haptics.impact(.light, intensity: 0.5)
            case let .levelUp(level):
                ring(at: hero.position, color: Neon.primary, from: 10, to: 120, duration: 0.5, width: 5)
                ring(at: hero.position, color: Neon.accent, from: 10, to: 180, duration: 0.7, width: 3)
                burst(at: hero.position, color: Neon.primary, count: 30, speed: 240, lifetime: 0.6, scale: 0.5)
                heroCallout("NÍVEL \(level)!", color: Neon.primary, size: 30)
                sound.play(.levelUp)
                haptics.notify(.success)
            case let .comboMilestone(value):
                let tier = [10, 25, 50, 100, 200].firstIndex { value <= $0 } ?? 4
                sound.play(.combo, variant: tier)
                haptics.impact(.medium)
            case let .waveStarted(wave, isBoss):
                if isBoss {
                    let base = engine.bossVariant.animationBase
                    SpriteAnimations.evictBosses(except: base)
                    SpriteAnimations.enqueue(base)
                    sound.play(.bossAlarm)
                    haptics.notify(.warning)
                } else {
                    sound.play(.waveStart, volume: 0.7)
                    if (wave + 1) % 5 == 0 { BossIntroArt.prepare(BossVariant.forWave(wave + 1)) }
                }
            case .waveCleared:
                sound.play(.waveClear)
                haptics.notify(.success)
            case .bossSpawned:
                addTrauma(0.4)
                haptics.impact(.heavy)
                sound.play(.eliteKill, volume: 0.8)
            case .bossPhase:
                enemyNodes.values.first { $0.kind == .boss }?.enrage()
                addTrauma(0.35)
                screenFlash(color: Neon.coral, alpha: 0.25)
                sound.play(.bossAlarm, volume: 0.8)
                haptics.impact(.heavy)
            case let .bossDefeated(position):
                bossDeath(at: point(position))
                sound.play(.bossDown)
                haptics.notify(.success)
                hitStop = 0.25
                slowMotion = 0.9
                addTrauma(0.9)
            case .upgradeChosen:
                sound.play(.select)
                haptics.impact(.light)
            case let .fusion(type):
                ring(at: hero.position, color: type.uiColor, from: 10, to: 220, duration: 0.7, width: 8)
                ring(at: hero.position, color: .white, from: 10, to: 160, duration: 0.5, width: 4)
                burst(at: hero.position, color: type.uiColor, count: 50, speed: 300, lifetime: 0.8, scale: 0.7)
                screenFlash(color: type.uiColor, alpha: 0.35)
                sound.play(.fusion)
                haptics.notify(.success)
            case let .gearEquipped(slot, rarity):
                gearEquipped(slot, rarity: rarity)
            case let .gearSetCompleted(rarity):
                gearSetCompleted(rarity)
            case .gameOver:
                sound.play(.gameOver)
                haptics.notify(.error)
                addTrauma(0.6)
            case .runStarted:
                // The hero powers up where the home screen left them and the arena goes live.
                let center = CGPoint(x: hero.position.x, y: hero.position.y + 14)
                let tint = engine.config.character.tint
                heroRecoilSquash = 0.16
                flare(at: center, color: .white, size: 120, duration: 0.28)
                ring(at: center, color: tint, from: 12, to: 200, duration: 0.5, width: 5)
                ring(at: center, color: Neon.primary, from: 12, to: 340, duration: 0.85, width: 2)
                burst(at: center, color: tint, count: 28, speed: 280, lifetime: 0.55, scale: 0.45, angle: .pi / 2, spread: 1.3)
                heroDust(direction: -1, count: 8)
                heroDust(direction: 1, count: 8)
                haptics.impact(.heavy)
                addTrauma(0.18)
            }
        }
    }

    // MARK: Animated impacts

    /// Muzzle flash, cone sparks and hero recoil. `angle` is in scene space.
    private func muzzleFlash(at origin: CGPoint, angle: CGFloat, color: UIColor) {
        let direction = CGVector(dx: cos(angle), dy: sin(angle))
        let tip = CGPoint(x: origin.x + direction.dx * 14, y: origin.y + direction.dy * 14)

        heroRecoil = CGVector(dx: -direction.dx * 5, dy: -direction.dy * 5)
        heroRecoilSquash = 0.08

        flare(at: tip, color: color, size: 34, duration: 0.09, rotation: angle)
        let glow = SKSpriteNode(texture: SceneTextures.glow, size: CGSize(width: 30, height: 30))
        glow.color = color
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.position = tip
        fxLayer.addChild(glow)
        glow.run(.sequence([
            .group([.scale(to: 1.5, duration: 0.1), .fadeOut(withDuration: 0.1)]),
            .removeFromParent(),
        ]))
        burst(at: tip, color: color, count: 6, speed: 160, lifetime: 0.16, scale: 0.28, angle: angle, spread: 0.55)
    }

    /// Directional sparks, a spinning flare, a small ring, ball squash and the enemy's own hit reaction.
    private func hitImpact(at p: CGPoint, enemy: EnemyNode?, color: UIColor, critical: Bool) {
        // Direction from the impact into the enemy (balls mostly come from below).
        var into = CGVector(dx: 0, dy: 1)
        if let enemy {
            let dx = enemy.position.x - p.x
            let dy = enemy.position.y - p.y
            let length = hypot(dx, dy)
            if length > 2 { into = CGVector(dx: dx / length, dy: dy / length) }
            enemy.takeHit(direction: into, critical: critical)
        }
        let outward = atan2(-into.dy, -into.dx)
        burst(at: p, color: color, count: critical ? 14 : 6, speed: critical ? 220 : 140, lifetime: critical ? 0.3 : 0.22, scale: critical ? 0.45 : 0.32, angle: outward, spread: critical ? 2.2 : 1.3)
        flare(at: p, color: critical ? .white : color, size: critical ? 64 : 34, duration: critical ? 0.16 : 0.1, rotation: .random(in: 0...(.pi)))
        ring(at: p, color: critical ? Neon.gold : color, from: 4, to: critical ? 34 : 18, duration: critical ? 0.22 : 0.14, width: critical ? 3 : 2)
        nearestBallNode(to: p, within: 22)?.squash()
    }

    /// Engine-space position of a ball touching the left, right or top wall.
    private func wallImpact(at position: CGPoint) {
        let p = point(position)
        let inward: CGFloat
        if position.x < 14 {
            inward = 0
        } else if position.x > size.width - 14 {
            inward = .pi
        } else {
            inward = -.pi / 2
        }
        let ball = nearestBallNode(to: p, within: 24)
        let color = ball?.type.uiColor ?? .white
        ball?.squash()
        flare(at: p, color: color, size: 22, duration: 0.08, rotation: inward)
        burst(at: p, color: color, count: 4, speed: 120, lifetime: 0.16, scale: 0.25, angle: inward, spread: 1.2)
        ring(at: p, color: color, from: 3, to: 12, duration: 0.12, width: 1.5)
    }

    private func flare(at position: CGPoint, color: UIColor, size side: CGFloat, duration: Double, rotation: CGFloat = 0) {
        let flare = SKSpriteNode(texture: SceneTextures.flare, size: CGSize(width: side, height: side))
        flare.color = color
        flare.colorBlendFactor = color == .white ? 0 : 0.65
        flare.blendMode = .add
        flare.position = position
        flare.zRotation = rotation
        flare.setScale(0.3)
        fxLayer.addChild(flare)
        let pop = SKAction.scale(to: 1.1, duration: duration * 0.35)
        pop.timingMode = .easeOut
        flare.run(.sequence([
            .group([pop, .rotate(byAngle: 0.6, duration: duration)]),
            .group([.scale(to: 0.5, duration: duration * 0.65), .fadeOut(withDuration: duration * 0.65)]),
            .removeFromParent(),
        ]))
    }

    private func fadeGhost(at position: CGPoint, color: UIColor, size side: CGFloat) {
        let ghost = SKSpriteNode(texture: SceneTextures.glow, size: CGSize(width: side, height: side))
        ghost.color = color
        ghost.colorBlendFactor = 1
        ghost.blendMode = .add
        ghost.position = position
        ghost.alpha = 0.8
        ballLayer.addChild(ghost)
        ghost.run(.sequence([
            .group([.scale(to: 0.2, duration: 0.14), .fadeOut(withDuration: 0.14)]),
            .removeFromParent(),
        ]))
    }

    private func nearestBallNode(to p: CGPoint, within limit: CGFloat) -> BallNode? {
        var best: BallNode?
        var bestDistance = limit
        for node in ballNodes.values {
            let distance = hypot(node.position.x - p.x, node.position.y - p.y)
            if distance < bestDistance {
                bestDistance = distance
                best = node
            }
        }
        return best
    }

    private func nearestEnemyNode(to p: CGPoint, within limit: CGFloat) -> EnemyNode? {
        var best: EnemyNode?
        var bestDistance = limit
        for node in enemyNodes.values {
            let distance = hypot(node.position.x - p.x, node.position.y - p.y)
            if distance < bestDistance {
                bestDistance = distance
                best = node
            }
        }
        return best
    }

    // MARK: Effects

    private func burst(at position: CGPoint, color: UIColor, count: Int, speed: CGFloat, lifetime: CGFloat, scale: CGFloat, angle: CGFloat = 0, spread: CGFloat = .pi * 2) {
        guard activeEmitters < 48 else { return }
        let emitter = SKEmitterNode()
        emitter.particleTexture = SceneTextures.spark
        emitter.numParticlesToEmit = count
        emitter.particleBirthRate = CGFloat(count) * 40
        emitter.particleLifetime = lifetime
        emitter.particleLifetimeRange = lifetime * 0.6
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.7
        emitter.emissionAngle = angle
        emitter.emissionAngleRange = spread
        emitter.particleAlphaSpeed = -1 / lifetime
        emitter.particleScale = scale
        emitter.particleScaleRange = scale * 0.5
        emitter.particleScaleSpeed = -scale / lifetime
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.position = position
        fxLayer.addChild(emitter)
        activeEmitters += 1
        emitter.run(.sequence([.wait(forDuration: Double(lifetime) * 1.7), .removeFromParent()])) { [weak self] in
            self?.activeEmitters -= 1
        }
    }

    private func ring(at position: CGPoint, color: UIColor, from start: CGFloat, to end: CGFloat, duration: Double, width: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.strokeColor = color
        ring.lineWidth = width / max(1, start / 10)
        ring.glowWidth = width
        ring.fillColor = .clear
        ring.position = position
        ring.setScale(start / 10)
        ring.blendMode = .add
        fxLayer.addChild(ring)
        ring.run(.sequence([
            .group([
                .scale(to: end / 10, duration: duration),
                .fadeOut(withDuration: duration),
            ]),
            .removeFromParent(),
        ]))
    }

    private func explosion(at position: CGPoint, radius: CGFloat, color: UIColor) {
        let flash = SKSpriteNode(texture: SceneTextures.glow, size: CGSize(width: radius * 2.6, height: radius * 2.6))
        flash.color = color
        flash.colorBlendFactor = 1
        flash.blendMode = .add
        flash.position = position
        flash.setScale(0.4)
        fxLayer.addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1, duration: 0.12), .fadeAlpha(to: 0.9, duration: 0.05)]),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))
        ring(at: position, color: color, from: radius * 0.3, to: radius, duration: 0.3, width: 4)
        burst(at: position, color: color, count: 22, speed: radius * 3.2, lifetime: 0.4, scale: 0.6)
    }

    private func lightning(from start: CGPoint, to end: CGPoint, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: start)
        let segments = 6
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        for i in 1..<segments {
            let t = CGFloat(i) / CGFloat(segments)
            let offset = CGFloat.random(in: -12...12)
            path.addLine(to: CGPoint(x: start.x + dx * t + normal.x * offset, y: start.y + dy * t + normal.y * offset))
        }
        path.addLine(to: end)
        let bolt = SKShapeNode(path: path.cgPath)
        bolt.strokeColor = color
        bolt.lineWidth = 2.5
        bolt.glowWidth = 4
        bolt.blendMode = .add
        fxLayer.addChild(bolt)
        bolt.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
    }

    private func bossDeath(at position: CGPoint) {
        for i in 0..<6 {
            let offset = CGPoint(x: CGFloat.random(in: -50...50), y: CGFloat.random(in: -40...40))
            let p = CGPoint(x: position.x + offset.x, y: position.y + offset.y)
            run(.sequence([
                .wait(forDuration: Double(i) * 0.12),
                .run { [weak self] in
                    self?.explosion(at: p, radius: 70, color: i.isMultiple(of: 2) ? Neon.coral : Neon.gold)
                    self?.feedback.sound.play(.explosion)
                    self?.addTrauma(0.2)
                },
            ]))
        }
        ring(at: position, color: .white, from: 20, to: max(size.width, size.height), duration: 0.8, width: 10)
        screenFlash(color: .white, alpha: 0.6)
    }

    private func screenFlash(color: UIColor, alpha: CGFloat) {
        overlay.removeAllActions()
        overlay.color = color
        overlay.alpha = alpha
        overlay.run(.fadeOut(withDuration: 0.3))
    }

    private func damageLabel(_ amount: Double, at position: CGPoint, color: UIColor, critical: Bool, small: Bool = false) {
        guard showDamageNumbers, activeLabels < 60 else { return }
        let label = labelPool.popLast() ?? {
            let l = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            l.verticalAlignmentMode = .center
            l.horizontalAlignmentMode = .center
            return l
        }()
        label.removeAllActions()
        label.text = amount >= 10 ? "\(Int(amount.rounded()))" : String(format: "%.0f", max(1, amount))
        label.fontSize = critical ? 26 : (small ? 13 : 17)
        label.fontColor = color
        label.alpha = 1
        label.position = CGPoint(x: position.x + CGFloat.random(in: -10...10), y: position.y + 8)
        label.setScale(critical ? 0.4 : 0.7)
        textLayer.addChild(label)
        activeLabels += 1

        let rise = SKAction.moveBy(x: CGFloat.random(in: -14...14), y: critical ? 46 : 30, duration: critical ? 0.7 : 0.5)
        rise.timingMode = .easeOut
        let pop = SKAction.sequence([
            .scale(to: critical ? 1.35 : 1.1, duration: 0.07),
            .scale(to: 1, duration: 0.1),
        ])
        label.run(.sequence([
            .group([rise, pop, .sequence([.wait(forDuration: critical ? 0.4 : 0.25), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent(),
        ])) { [weak self, weak label] in
            guard let self, let label else { return }
            self.activeLabels -= 1
            if self.labelPool.count < 80 { self.labelPool.append(label) }
        }
    }

    // MARK: Shake

    private func addTrauma(_ amount: CGFloat) {
        guard feedback.screenShake else { return }
        trauma = min(1, trauma + amount)
    }

    private func updateShake(_ dt: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard trauma > 0 else {
            cameraNode.position = center
            return
        }
        trauma = max(0, trauma - CGFloat(dt) * 1.7)
        let magnitude = 16 * trauma * trauma
        cameraNode.position = CGPoint(
            x: center.x + CGFloat.random(in: -1...1) * magnitude,
            y: center.y + CGFloat.random(in: -1...1) * magnitude
        )
        cameraNode.zRotation = CGFloat.random(in: -1...1) * 0.02 * trauma * trauma
    }

    // MARK: Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        let location = touch.location(in: view)
        touchStart = (location, touch.timestamp)
        engine.beginDrag(at: location.x)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        engine.drag(to: touch.location(in: view).x)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine.endDrag()
        // A short tap that barely moved picks a target; anything else was a drag.
        if let start = touchStart, let touch = touches.first, let view {
            let location = touch.location(in: view)
            let dx = location.x - start.point.x
            let dy = location.y - start.point.y
            let elapsed = touch.timestamp - start.time
            if hypot(dx, dy) < 14, elapsed < 0.35 {
                engine.selectTarget(at: location)
            } else if dy < -70, abs(dx) < abs(dy) * 0.7, elapsed < 0.45 {
                // A quick flick upward fires the ultimate.
                engine.activatePulse()
            }
        }
        touchStart = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine.endDrag()
        touchStart = nil
    }
}
