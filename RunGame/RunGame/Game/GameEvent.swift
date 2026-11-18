import CoreGraphics

/// Things that happened during a simulation step. The engine only records them;
/// the scene drains the queue every frame and turns them into particles, sound and haptics.
enum GameEvent {
    case ballLaunched(type: BallType, origin: CGPoint, angle: CGFloat)
    case wallBounce(CGPoint)
    case hit(enemyID: Int, position: CGPoint, damage: Double, critical: Bool, type: BallType)
    case dot(position: CGPoint, damage: Double, type: BallType)
    case shieldBlock(CGPoint)
    case chain(from: CGPoint, to: CGPoint, type: BallType)
    case explosion(position: CGPoint, radius: CGFloat, type: BallType)
    case freeze(CGPoint)
    case enemyKilled(position: CGPoint, kind: EnemyKind, elite: Bool, radius: CGFloat, experience: Int)
    case enemyEscaped(CGPoint)
    case enemyShot(CGPoint)
    case bulletBlocked(CGPoint)
    /// A trick shot forked or a mortar blew; `ring` is true for the mortar.
    case shotBurst(CGPoint, ring: Bool)
    case heroHurt(damage: Int, lethal: Bool)
    case heal
    case ultimate(UltimateKind, CGPoint)
    case pulseReady
    case targetLocked(enemyID: Int, position: CGPoint)
    case targetReleased
    case aimPointSet(CGPoint)
    case levelUp(Int)
    case comboMilestone(Int)
    case waveStarted(wave: Int, isBoss: Bool)
    case waveCleared
    case bossSpawned
    case bossPhase(Int)
    case bossDefeated(CGPoint)
    case upgradeChosen
    case fusion(BallType)
    case gearEquipped(slot: HeroGearSlot, rarity: UpgradeRarity)
    case gearSetCompleted(UpgradeRarity)
    case gameOver
    case runStarted
}
