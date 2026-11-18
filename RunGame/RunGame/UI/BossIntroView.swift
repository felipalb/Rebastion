import SwiftUI
import UIKit

/// Decoded boss intro frames (`<base>_Intro_01…04`, drawn at iPhone screen size). A full-screen
/// frame is about 12 MB decoded, so only one boss's set is held: decoded in the background during
/// the wave before the boss, dropped once the intro is over.
@MainActor
enum BossIntroArt {
    private static var loaded: (variant: BossVariant, frames: [UIImage])?
    private static var preparing: BossVariant?

    static func frames(for variant: BossVariant) -> [UIImage] {
        if let loaded, loaded.variant == variant { return loaded.frames }
        // Not prepared in time: fall back to lazy images, decoded on first draw.
        let frames = names(variant).compactMap { UIImage(named: $0) }
        loaded = (variant, frames)
        return frames
    }

    static func prepare(_ variant: BossVariant) {
        guard loaded?.variant != variant, preparing != variant else { return }
        preparing = variant
        let names = names(variant)
        Task {
            var frames: [UIImage] = []
            for name in names {
                guard let image = UIImage(named: name) else { continue }
                frames.append(await image.byPreparingForDisplay() ?? image)
            }
            guard preparing == variant else { return }
            preparing = nil
            loaded = (variant, frames)
        }
    }

    static func release() {
        loaded = nil
    }

    private static func names(_ variant: BossVariant) -> [String] {
        (1...SpriteAnimations.frameCount).map { "\(variant.animationBase)_Intro_0\($0)" }
    }
}

/// Reads the engine's intro clock on its own, so only this layer redraws every frame of the intro.
struct BossIntroLayer: View {
    let engine: GameEngine

    var body: some View {
        if let time = engine.bossIntroElapsed {
            BossIntroCard(frames: BossIntroArt.frames(for: engine.bossVariant), time: time)
                .onDisappear { BossIntroArt.release() }
        }
    }
}

/// The boss's cutscene over the whole screen: fades in, plays the four frames once, holds the last
/// one with a slow push-in, then fades out.
private struct BossIntroCard: View {
    let frames: [UIImage]
    let time: Double

    private static let frameStep = 0.13
    private static let fadeIn = 0.15
    private static let fadeOut = 0.3

    var body: some View {
        let duration = GameEngine.bossIntroDuration
        let holdUntil = duration - Self.fadeOut
        let enter = min(1, time / Self.fadeIn)
        let exit = max(0, (time - holdUntil) / Self.fadeOut)
        Color.black
            .overlay {
                if !frames.isEmpty {
                    Image(uiImage: frames[min(frames.count - 1, Int(time / Self.frameStep))])
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1 + 0.04 * min(time, holdUntil) / holdUntil)
                }
            }
            .clipped()
            .opacity(min(enter, 1 - exit))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
