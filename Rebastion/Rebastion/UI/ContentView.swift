import SwiftUI
import SpriteKit

/// Owns the long-lived game objects so the SpriteKit scene survives SwiftUI view updates.
@MainActor
@Observable
final class GameSession {
    let engine: GameEngine
    let feedback: FeedbackHub
    let profile: ProfileStore
    let gameCenter: GameCenterService
    @ObservationIgnored let scene: GameScene
    var lastReward: RunReward?
    /// True for the brief beat between tapping "Começar run" and the run going live,
    /// while the home screen chrome fades off the arena.
    private(set) var isLaunching = false

    init() {
        let engine = GameEngine()
        let feedback = FeedbackHub()
        let profile = ProfileStore()
        self.engine = engine
        self.feedback = feedback
        self.profile = profile
        self.gameCenter = GameCenterService()
        self.scene = GameScene(engine: engine, feedback: feedback)
        feedback.apply(profile.profile.settings)
        scene.showDamageNumbers = profile.profile.settings.damageNumbers
        profile.onSave = { [gameCenter] in gameCenter.sync($0) }
        previewHero()
    }

    /// Home screen → run: let the menu fade off the arena first, then start.
    func launchRun() {
        guard engine.phase == .menu, !isLaunching else { return }
        isLaunching = true
        feedback.sound.play(.select)
        feedback.haptics.impact(.light)
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            start()
            isLaunching = false
        }
    }

    func previewHero() {
        engine.preview(profile.runConfig())
    }

    func start() {
        lastReward = nil
        engine.start(config: profile.runConfig())
    }

    func restart() {
        start()
    }

    func commitRun() {
        guard let stats = engine.finalStats, lastReward == nil else { return }
        lastReward = profile.record(stats)
        gameCenter.submitScores(stats)
    }

    func updateSettings(_ settings: GameSettings) {
        profile.updateSettings(settings)
        feedback.apply(settings)
        scene.showDamageNumbers = settings.damageNumbers
    }
}

struct ContentView: View {
    @State private var session = GameSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            GamePalette.background.ignoresSafeArea()
            GameView(session: session)
        }
        .preferredColorScheme(.dark)
        .onChange(of: session.engine.phase) { _, phase in
            if phase == .gameOver { session.commitRun() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.engine.pause() }
        }
        .task {
            session.gameCenter.authenticate(syncing: session.profile.profile)
        }
    }
}

/// The arena is also the home screen: on the menu the same scene shows the idle hero with no
/// enemies, and the header, arena and footer slots hold menu chrome instead of the HUD. Both
/// layers stay laid out so the arena never changes size when one swaps for the other.
struct GameView: View {
    let session: GameSession

    @State private var sheet: MenuSheet?

    private var engine: GameEngine { session.engine }
    private var inMenu: Bool { engine.phase == .menu }
    private var showsMenu: Bool { inMenu && !session.isLaunching }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HUDHeader(engine: engine)
                    .chromeLayer(visible: !inMenu)
                MenuHeader(cores: session.profile.profile.cores) { sheet = .settings }
                    .chromeLayer(visible: showsMenu)
            }
            .background(GamePalette.ink)
            ZStack(alignment: .top) {
                SpriteView(scene: session.scene, preferredFramesPerSecond: 120)
                    .accessibilityAction(named: "Ativar Ultimate") { engine.activatePulse() }
                if engine.lives == 1, engine.phase == .playing {
                    LastLifeVignette()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if engine.canPulse, engine.config.coachUltimate {
                    UltimateReadyHint(kind: engine.config.ultimate)
                        .padding(.bottom, 124)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                }
                VStack(spacing: 8) {
                    if let ratio = engine.bossHealthRatio {
                        BossBar(ratio: ratio, title: engine.bossVariant.title)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let banner = engine.banner {
                        BannerView(banner: banner)
                            .id(banner.id)
                            .transition(.scale(scale: 1.6).combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
                .allowsHitTesting(false)
                .animation(.spring(duration: 0.3, bounce: 0.4), value: engine.banner)
                .animation(.easeOut(duration: 0.3), value: engine.bossHealthRatio == nil)

                MenuStage(profile: session.profile, visible: showsMenu) {
                    session.launchRun()
                }
                .settlesHidden(!showsMenu)
            }
            .animation(.spring(duration: 0.35, bounce: 0.4), value: engine.canPulse)
            .animation(.easeInOut(duration: 0.3), value: engine.lives == 1)
            .clipped()
            ZStack {
                HUDFooter(engine: engine)
                    .chromeLayer(visible: !inMenu)
                MenuFooter(profile: session.profile) { sheet = $0 }
                    .chromeLayer(visible: showsMenu)
            }
            .background(GamePalette.ink)
        }
        .animation(.easeOut(duration: 0.26), value: showsMenu)
        .animation(.easeOut(duration: 0.3), value: inMenu)
        .overlay {
            if engine.canPulse {
                UltimateReadyEdges()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: engine.canPulse)
        .overlay {
            BossIntroLayer(engine: engine)
        }
        .overlay {
            switch engine.phase {
            case .choosingUpgrade:
                UpgradeView(engine: engine)
                    .transition(.opacity)
            case .paused:
                PauseView(session: session)
                    .transition(.opacity)
            case .gameOver:
                GameOverView(session: session)
                    .transition(.opacity)
            default:
                EmptyView()
            }
        }
        .animation(.spring(duration: 0.3), value: engine.phase)
        .onChange(of: session.profile.selectedCharacter) {
            session.previewHero()
        }
        .sheet(item: $sheet) { sheet in
            MenuSheetView(session: session, sheet: sheet) { self.sheet = nil }
        }
    }
}

extension View {
    /// Cross-fades the menu and HUD layers that share the header and footer slots.
    func chromeLayer(visible: Bool) -> some View {
        settlesHidden(!visible)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.97)
            .allowsHitTesting(visible)
    }

    /// Takes a faded-out layer out of rendering and the accessibility tree once its fade has
    /// finished, keeping its size so the header and footer slots never change height.
    func settlesHidden(_ hidden: Bool) -> some View {
        modifier(SettlesHidden(hidden: hidden))
    }
}

private struct SettlesHidden: ViewModifier {
    let hidden: Bool

    @State private var settled = false

    func body(content: Content) -> some View {
        Group {
            if hidden && settled {
                content.hidden()
            } else {
                content
            }
        }
        .accessibilityHidden(hidden)
        .task(id: hidden) {
            settled = false
            guard hidden else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { settled = true }
        }
    }
}

#Preview {
    ContentView()
}
