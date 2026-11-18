import SwiftUI

struct PauseView: View {
    let session: GameSession

    private var engine: GameEngine { session.engine }

    var body: some View {
        VStack(spacing: 18) {
            Text("PAUSADO")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(GamePalette.primary)

            BuildSummary(engine: engine)

            QuickSettingsGrid(session: session)

            VStack(spacing: 10) {
                Button("CONTINUAR") { engine.resume() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Abandonar run") { engine.abandonRun() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .modalCard()
    }
}

struct BuildSummary: View {
    let engine: GameEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUA BUILD")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                BallChip(type: .basic, level: nil, count: engine.basicBallCount)
                ForEach(engine.ownedSpecialBalls, id: \.type) { entry in
                    BallChip(type: entry.type, level: entry.type.isFusion ? nil : entry.level, count: nil)
                }
            }
            let passives = Passive.allCases.filter { (engine.passiveLevels[$0] ?? 0) > 0 }
            if !passives.isEmpty {
                FlowRow(items: passives) { passive in
                    Label("\(passive.title) \(engine.passiveLevels[passive] ?? 0)", systemImage: passive.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(passive.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(passive.color.opacity(0.12), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Minimal wrapping row for chips.
struct FlowRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct GameOverView: View {
    let session: GameSession

    @State private var shownCores = 0

    var body: some View {
        let stats = session.engine.finalStats ?? RunStats()
        let reward = session.lastReward
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("RUN ENCERRADA")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(GamePalette.coral)
                if reward?.newBestScore == true {
                    Text("NOVO RECORDE!")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(GamePalette.gold, in: Capsule())
                        .shadow(color: GamePalette.gold, radius: 10)
                }
            }

            Text(stats.score, format: .number)
                .font(.system(size: 46, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)

            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    StatCell(title: "Onda", value: "\(stats.wave)", color: GamePalette.primary)
                    StatCell(title: "Nível", value: "\(stats.level)", color: GamePalette.accent)
                    StatCell(title: "Abates", value: "\(stats.kills)", color: GamePalette.coral)
                }
                GridRow {
                    StatCell(title: "Combo", value: "\(stats.bestCombo)", color: GamePalette.gold)
                    StatCell(title: "Chefes", value: "\(stats.bossesDefeated)", color: .orange)
                    StatCell(title: "Fusões", value: "\(stats.fusions)", color: GamePalette.magenta)
                }
            }

            HStack {
                Text("Núcleos ganhos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                CoreBadge(amount: shownCores)
            }

            VStack(spacing: 10) {
                Button("JOGAR DE NOVO") { session.restart() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Menu") { session.engine.returnToMenu() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .modalCard()
        .task {
            shownCores = 0
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.9)) {
                shownCores = stats.coresEarned
            }
        }
    }
}

struct StatCell: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.black).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
