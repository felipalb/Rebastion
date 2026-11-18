import GameKit
import UIKit

/// Game Center integration. Requires the Game Center capability on the target and the
/// leaderboard / achievement IDs (see `GameAchievement`) to exist in App Store Connect;
/// otherwise every call fails silently and the game keeps tracking progress locally.
@MainActor
@Observable
final class GameCenterService {
    enum Leaderboard {
        static let score = "rebastion.score"
        static let wave = "rebastion.wave"
    }

    private(set) var isAuthenticated = false
    private(set) var playerName: String?

    /// Last percentage sent per achievement, so a sync only reports what moved.
    @ObservationIgnored private var reported: [GameAchievement: Double] = [:]
    @ObservationIgnored private var pendingProfile: PlayerProfile?

    func authenticate(syncing profile: PlayerProfile) {
        pendingProfile = profile
        GKAccessPoint.shared.isActive = false
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                }
                let player = GKLocalPlayer.local
                self.isAuthenticated = player.isAuthenticated
                self.playerName = player.isAuthenticated ? player.displayName : nil
                if self.isAuthenticated, let profile = self.pendingProfile {
                    Task {
                        await self.loadReported()
                        self.sync(self.pendingProfile ?? profile)
                    }
                }
            }
        }
    }

    func submitScores(_ run: RunStats) {
        guard isAuthenticated else { return }
        let scores = [Leaderboard.score: run.score, Leaderboard.wave: run.wave]
        for (board, score) in scores {
            GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board]) { _ in }
        }
    }

    /// Reports every achievement whose progress went up since the last report.
    func sync(_ profile: PlayerProfile) {
        pendingProfile = profile
        guard isAuthenticated else { return }
        var achievements: [GKAchievement] = []
        for entry in GameAchievement.allCases {
            let percent = (entry.progress(in: profile) * 100).rounded(.down)
            guard percent > (reported[entry] ?? 0) else { continue }
            reported[entry] = percent
            let achievement = GKAchievement(identifier: entry.rawValue)
            achievement.percentComplete = percent
            achievement.showsCompletionBanner = percent >= 100
            achievements.append(achievement)
        }
        if !achievements.isEmpty {
            GKAchievement.report(achievements) { _ in }
        }
    }

    func showAchievements() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .achievements) {}
    }

    func showLeaderboards() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }

    private func loadReported() async {
        let achievements = (try? await GKAchievement.loadAchievements()) ?? []
        for achievement in achievements {
            if let entry = GameAchievement(rawValue: achievement.identifier) {
                reported[entry] = achievement.percentComplete
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
