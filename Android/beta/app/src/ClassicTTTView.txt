import SwiftUI

struct ClassicTTTView: View {
    let mode: GameMode
    let difficulty: BotDifficulty

    @State private var board: [Player?] = Array(repeating: nil, count: 9)
    @State private var currentPlayer: Player = .x
    @State private var result: GameResult = .ongoing
    @State private var isThinking = false
    @State private var thinkingDots = 0
    @State private var dotTimer: Timer? = nil
    @Environment(\.dismiss) private var dismiss

    private var isBot: Bool { mode == .vsBot }
    private var isAiVsAi: Bool { mode == .aiVsAi }
    private var botPlayer: Player { .o }
    private var neuralModel: NeuralAIModel { NeuralAIStore.shared.model(for: .classic) }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                statusBar.padding(.top, 16).padding(.horizontal, 20)
                Spacer()
                boardView.padding(.horizontal, 20)
                Spacer()
                bottomBar.padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Classic TTT")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: board) { _ in triggerBotIfNeeded() }
            .onAppear { triggerBotIfNeeded() }
            .onDisappear { stopDotTimer() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            playerIndicator(.x)
            Spacer()
            statusLabel
            Spacer()
            playerIndicator(.o)
        }
    }

    private func playerIndicator(_ player: Player) -> some View {
        let isActive = result == .ongoing && currentPlayer == player
        let isWinner: Bool = {
            if case .win(let w, _) = result { return w == player }
            return false
        }()
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(player.color.opacity(isActive || isWinner ? 0.15 : 0.05))
                    .frame(width: 48, height: 48)
                Text(player.rawValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(player.color.opacity(isActive || isWinner ? 1 : 0.3))
            }
            .overlay(Circle().stroke(player.color, lineWidth: isActive ? 2 : 0))
            Text(playerLabel(player))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private func playerLabel(_ player: Player) -> String {
        if isAiVsAi { return "AI \(player.rawValue)" }
        if isBot && player == botPlayer {
            return difficulty == .neural ? "Neural" : "Bot"
        }
        return player == .x ? "Player X" : "Player O"
    }

    private var statusLabel: some View {
        Group {
            switch result {
            case .ongoing:
                if isThinking {
                    Text("Thinking" + String(repeating: ".", count: thinkingDots + 1))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .animation(.none, value: thinkingDots)
                } else {
                    Text("\(currentPlayer.rawValue)'s turn")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(currentPlayer.color)
                }
            case .win(let winner, _):
                Text("\(winner.rawValue) wins! 🎉")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(winner.color)
            case .draw:
                Text("It's a draw!")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Board

    private var boardView: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cellSize = size / 3
            ZStack {
                gridLines(size: size)
                ForEach(0..<9, id: \.self) { index in
                    let row = index / 3; let col = index % 3
                    cellView(index: index, size: cellSize)
                        .position(x: CGFloat(col) * cellSize + cellSize / 2,
                                  y: CGFloat(row) * cellSize + cellSize / 2)
                }
                if case .win(_, let indices) = result {
                    WinLineView(indices: indices, size: size)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func gridLines(size: CGFloat) -> some View {
        let cell = size / 3
        return ZStack {
            ForEach([1, 2], id: \.self) { i in
                Rectangle().fill(Color(.separator)).frame(width: 1.5, height: size)
                    .position(x: cell * CGFloat(i), y: size / 2)
                Rectangle().fill(Color(.separator)).frame(width: size, height: 1.5)
                    .position(x: size / 2, y: cell * CGFloat(i))
            }
        }
    }

    private func cellView(index: Int, size: CGFloat) -> some View {
        let canTap = board[index] == nil && result == .ongoing && !isThinking
            && !isAiVsAi && !(isBot && currentPlayer == botPlayer)
        return Button { tap(index) } label: {
            ZStack {
                Rectangle().fill(Color.clear).frame(width: size, height: size)
                if let player = board[index] {
                    Text(player.rawValue)
                        .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                        .foregroundColor(player.color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(!canTap)
        .animation(.spring(response: 0.3), value: board[index])
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Button {
            resetGame()
        } label: {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(14)
        }
    }

    // MARK: - Logic

    private func tap(_ index: Int) {
        guard board[index] == nil, result == .ongoing else { return }
        place(index, player: currentPlayer)
    }

    private func place(_ index: Int, player: Player) {
        withAnimation(.spring(response: 0.25)) { board[index] = player }
        let newResult = WinChecker.result(board: board)
        withAnimation(.easeInOut(duration: 0.3)) { result = newResult }
        if newResult == .ongoing { currentPlayer = player.opposite }
    }

    private func triggerBotIfNeeded() {
        guard result == .ongoing, !isThinking else { return }
        let isAITurn = isAiVsAi || (isBot && currentPlayer == botPlayer)
        guard isAITurn else { return }

        isThinking = true
        startDotTimer()
        let player = currentPlayer
        let boardSnapshot = board

        DispatchQueue.global(qos: .userInitiated).async {
            let move: Int?
            switch difficulty {
            case .easy:
                move = MinimaxAI.randomMove(board: boardSnapshot)
            case .hard:
                move = MinimaxAI.bestMove(board: boardSnapshot, player: player)
            case .neural:
                let nm = NeuralAIStore.shared.model(for: .classic)
                move = nm.trainedEpisodes > 0
                    ? nm.pickTTTMove(board: boardSnapshot, player: player)
                    : MinimaxAI.randomMove(board: boardSnapshot)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.isThinking = false
                self.stopDotTimer()
                if let m = move { self.place(m, player: player) }
            }
        }
    }

    private func resetGame() {
        stopDotTimer()
        withAnimation {
            board = Array(repeating: nil, count: 9)
            currentPlayer = .x
            result = .ongoing
            isThinking = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { triggerBotIfNeeded() }
    }

    private func startDotTimer() {
        thinkingDots = 0
        dotTimer?.invalidate()
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            thinkingDots = (thinkingDots + 1) % 3
        }
    }

    private func stopDotTimer() {
        dotTimer?.invalidate()
        dotTimer = nil
    }
}

struct WinLineView: View {
    let indices: [Int]; let size: CGFloat
    var body: some View {
        let cell = size / 3
        let start = center(of: indices[0], cell: cell)
        let end = center(of: indices[2], cell: cell)
        return Path { p in p.move(to: start); p.addLine(to: end) }
            .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .transition(.opacity)
    }
    private func center(of index: Int, cell: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(index % 3) * cell + cell / 2,
                y: CGFloat(index / 3) * cell + cell / 2)
    }
}

#Preview {
    ClassicTTTView(mode: .vsBot, difficulty: .hard)
}
