import SwiftUI

struct GameSetupView: View {
    let gameType: GameType
    @State private var mode: GameMode = .vsHuman
    @State private var difficulty: BotDifficulty = .hard
    @State private var startGame = false
    @State private var showTraining = false
    @Environment(\.dismiss) private var dismiss

    private var neuralModel: NeuralAIModel { NeuralAIStore.shared.model(for: gameType) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    gameHeader
                    modeSection
                    if mode == .vsBot || mode == .aiVsAi {
                        difficultySection
                    }
                    if gameType.supportsNeuralAI {
                        neuralAICard
                    }
                    startButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(gameType.title)
            .navigationBarTitleDisplayMode(.inline)
            .background(
                NavigationLink(destination: gameView, isActive: $startGame) { EmptyView() }
            )
            .sheet(isPresented: $showTraining) {
                NeuralAITrainingView(gameType: gameType, model: neuralModel)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Game Header

    private var gameHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(gameType.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: gameType.icon)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(gameType.accentColor)
            }
            Text(gameType.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(gameType.subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            rulesBadge
        }
        .padding(.top, 8)
    }

    private var rulesBadge: some View {
        Text(gameType.rulesDescription)
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(12)
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(String(localized: "Game Mode"))
            HStack(spacing: 12) {
                ForEach(GameMode.allCases) { m in
                    ModeButton(title: m.displayName, icon: m.icon,
                               isSelected: mode == m, color: gameType.accentColor) { mode = m }
                }
            }
        }
    }

    // MARK: - Difficulty Section

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(mode == .aiVsAi ? String(localized: "AI Difficulty") : String(localized: "Bot Difficulty"))
            let available = gameType.supportsNeuralAI ? BotDifficulty.allCases : BotDifficulty.allCases.filter { $0 != .neural }
            HStack(spacing: 12) {
                ForEach(available) { d in
                    DifficultyButton(difficulty: d, isSelected: difficulty == d,
                                     color: gameType.accentColor) { difficulty = d }
                }
            }
        }
    }

    // MARK: - Neural AI Card

    private var neuralAICard: some View {
        let eps = neuralModel.trainedEpisodes
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(gameType.accentColor)
                Text("Neural AI")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if eps > 0 {
                    Text(String(localized: "\(eps) eps trained"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.systemGray5)).cornerRadius(8)
                }
            }

            Text(eps == 0
                 ? String(localized: "Train your own AI to challenge it in-game. Tap the button below to start training!")
                 : String(localized: "Your AI has been through \(eps) self-play episodes. Keep training to make it smarter, then select **Neural AI** difficulty to fight it."))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showTraining = true
            } label: {
                Label(eps == 0 ? String(localized: "Train Neural AI") : String(localized: "Continue Training"),
                      systemImage: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(gameType.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(gameType.accentColor.opacity(0.1))
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Start

    private var startButton: some View {
        Button {
            startGame = true
        } label: {
            Label(String(localized: "Start Game"), systemImage: "play.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(gameType.accentColor)
                .cornerRadius(16)
        }
        .padding(.top, 8)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Game View Router

    @ViewBuilder
    private var gameView: some View {
        switch gameType {
        case .classic:      ClassicTTTView(mode: mode, difficulty: difficulty)
        case .superTTT:     SuperTTTView(mode: mode, difficulty: difficulty)
        case .notakto:      NotaktoView(mode: mode, difficulty: difficulty)
        case .wild:         WildTTTView(mode: mode, difficulty: difficulty)
        case .connect4:     Connect4View(mode: mode, difficulty: difficulty)
        case .snake:        SnakeView()
        case .solitaire:    SolitaireView()
        case .brickBreaker: BrickBreakerView()
        case .minesweeper:  MinesweeperView()
        case .twenty48:     Twenty48View()
        case .wordle:       WordleView()
        case .checkers:     CheckersView(mode: mode, difficulty: difficulty)
        case .chess:        ChessView(mode: mode, difficulty: difficulty)
            // New games (no setup needed, but kept for completeness)
        case .memoryMatch:  MemoryMatchView()
        case .stack:        StackView()
        case .aimTrainer:   AimTrainerView()
            
        case .flappyBird:   FlappyBirdView()
        case .tetris:       TetrisView()
        case .blackjack:    BlackjackView()
        }
    }
}

extension GameType {
    var rulesDescription: String {
        switch self {
        case .classic:
            return String(localized: "Get three in a row to win. Take turns placing X and O on a 3×3 grid.")
        case .superTTT:
            return String(localized: "Win small boards to claim them on the big board. Your move determines which board your opponent plays in next!")
        case .notakto:
            return String(localized: "Both players use X. The player who completes three in a row LOSES. Play on up to three boards.")
        case .wild:
            return String(localized: "On each turn, choose to place either X or O anywhere. First to get three in a row wins.")
        case .connect4:
            return String(localized: "Drop colored discs into a 7x6 grid. Get 4 in a row horizontally, vertically, or diagonally to win.")
        case .snake:
            return String(localized: "Eat food to grow your snake. Don't hit the walls or yourself!")
        case .solitaire:
            return String(localized: "Build four foundation piles from Ace to King by suit. Move cards between tableau columns to uncover hidden cards.")
        case .brickBreaker:
            return String(localized: "Break all bricks using a paddle and ball. Catch the ball to keep playing!")
        case .minesweeper:
            return String(localized: "Reveal all safe cells without triggering mines. Numbers indicate adjacent mines.")
        case .twenty48:
            return String(localized: "Swipe to merge matching numbers. Reach 2048 to win!")
        case .wordle:
            return String(localized: "Guess the 5-letter word in 6 tries. Green = correct position, Yellow = wrong position, Gray = not in word.")
        case .checkers:
            return String(localized: "Move diagonally forward. Capture opponent pieces by jumping over them. Get to the back row to become a king.")
        case .chess:
            return String(localized: "Strategic board game. Checkmate the opponent's king to win.")
        case .memoryMatch:
            return String(localized: "Flip cards to find matching pairs. Remember where you've seen each symbol. Clear the board to win!")
        case .stack:
            return String(localized: "Tap to drop each moving block onto the stack. The overhanging part gets cut off. Stack as high as you can!")
        case .aimTrainer:
            return String(localized: "Tap targets as fast as possible. Your reaction time is measured. How quick are your reflexes?")
        case .flappyBird:
            return String(localized: "Tap to flap your wings and fly between pipes. Don't touch the pipes or ground!")
        case .tetris:
            return String(localized: "Stack falling tetrominoes to fill complete lines. Clear lines to score — 4 at once is a Tetris! Tap to rotate, swipe to move, swipe down to drop.")
        case .blackjack:
            return String(localized: "Draw cards and try to get as close to 21 as you can without busting!")
        }
    }
}

// MARK: - Supporting Buttons

struct ModeButton: View {
    let title: String; let icon: String; let isSelected: Bool; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22)).foregroundColor(isSelected ? color : .secondary)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundColor(isSelected ? color : .secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(isSelected ? color.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? color : Color.clear, lineWidth: 2))
            .cornerRadius(14)
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct DifficultyButton: View {
    let difficulty: BotDifficulty; let isSelected: Bool; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: difficulty.icon).font(.system(size: 22)).foregroundColor(isSelected ? color : .secondary)
                Text(difficulty.rawValue).font(.system(size: 13, weight: .semibold)).foregroundColor(isSelected ? color : .secondary)
                Text(difficulty.description).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(isSelected ? color.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? color : Color.clear, lineWidth: 2))
            .cornerRadius(14)
        }
        .buttonStyle(CardButtonStyle())
    }
}

#Preview {
    GameSetupView(gameType: .classic)
}
