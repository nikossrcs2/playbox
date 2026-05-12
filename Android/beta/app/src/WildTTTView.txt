import SwiftUI

struct WildTTTView: View {
    let mode: GameMode
    let difficulty: BotDifficulty

    @State private var board: [Player?] = Array(repeating: nil, count: 9)
    @State private var currentPlayer: Player = .x
    @State private var chosenPiece: Player = .x
    @State private var result: GameResult = .ongoing
    @State private var isThinking = false
    @State private var thinkingDots = 0
    @State private var dotTimer: Timer? = nil
    @Environment(\.dismiss) private var dismiss

    private var isBot: Bool { mode == .vsBot }
    private var isAiVsAi: Bool { mode == .aiVsAi }
    private var botPlayer: Player { .o }
    private var neuralModel: NeuralAIModel { NeuralAIStore.shared.model(for: .wild) }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                statusBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                boardView
                    .padding(.horizontal, 20)

                Spacer()

                if result == .ongoing && !isAiVsAi && !(isBot && currentPlayer == botPlayer) && !isThinking {
                    piecePicker
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Wild TTT")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.2), value: result)
            .onAppear { triggerBotIfNeeded() }
            .onDisappear { stopDotTimer() }
        }
        .navigationViewStyle(.stack)
    }

    private var statusBar: some View {
        HStack {
            playerChip(.x)
            Spacer()
            statusCenter
            Spacer()
            playerChip(.o)
        }
    }

    private func playerChip(_ player: Player) -> some View {
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

    private var statusCenter: some View {
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

    private var piecePicker: some View {
        VStack(spacing: 8) {
            Text("Choose your piece this turn")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                ForEach([Player.x, Player.o], id: \.self) { piece in
                    Button {
                        chosenPiece = piece
                    } label: {
                        HStack(spacing: 6) {
                            Text(piece.rawValue)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(chosenPiece == piece ? .white : piece.color)
                            Text(piece.rawValue == "X" ? "X" : "O")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(chosenPiece == piece ? .white.opacity(0.8) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(chosenPiece == piece ? piece.color : piece.color.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cellSize = size / 3

            ZStack {
                gridLines(size: size)

                ForEach(0..<9, id: \.self) { index in
                    let row = index / 3
                    let col = index % 3
                    cellView(index: index, size: cellSize)
                        .position(
                            x: CGFloat(col) * cellSize + cellSize / 2,
                            y: CGFloat(row) * cellSize + cellSize / 2
                        )
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
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1.5, height: size)
                    .position(x: cell * CGFloat(i), y: size / 2)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: size, height: 1.5)
                    .position(x: size / 2, y: cell * CGFloat(i))
            }
        }
    }

    private func cellView(index: Int, size: CGFloat) -> some View {
        let isHumanTurn = !isAiVsAi && !(isBot && currentPlayer == botPlayer) && !isThinking
        let canTap = board[index] == nil && result == .ongoing && isHumanTurn

        return Button {
            tap(index)
        } label: {
            ZStack {
                Rectangle()
                    .fill(canTap ? chosenPiece.color.opacity(0.05) : Color.clear)
                    .frame(width: size, height: size)

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

    private var bottomBar: some View {
        Button {
            resetGame()
        } label: {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.green)
                .cornerRadius(14)
        }
    }

    private func tap(_ index: Int) {
        guard board[index] == nil, result == .ongoing else { return }
        place(index, piece: chosenPiece, for: currentPlayer)
    }

    private func place(_ index: Int, piece: Player, for player: Player) {
        withAnimation(.spring(response: 0.25)) {
            board[index] = piece
        }
        let newResult = WinChecker.result(board: board)
        withAnimation(.easeInOut(duration: 0.3)) {
            result = newResult
        }
        if newResult == .ongoing {
            currentPlayer = player.opposite
            chosenPiece = .x
            triggerBotIfNeeded()
        }
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
            let move: (Int, Player)?
            
            switch difficulty {
            case .easy:
                move = MinimaxAI.randomWildMove(board: boardSnapshot)
                
            case .hard:
                move = (
                    MinimaxAI.bestWildMove(board: boardSnapshot, botPlayer: player).0,
                    MinimaxAI.bestWildMove(board: boardSnapshot, botPlayer: player).1
                )
                
            case .neural:
                // Use Neural AI if trained, fallback to Minimax otherwise
                let neural = NeuralAIStore.shared.model(for: .wild)
                if neural.trainedEpisodes > 0 {
                    move = neural.pickWildMove(board: boardSnapshot, player: player)
                } else {
                    // Fallback to Minimax if untrained
                    move = (
                        MinimaxAI.bestWildMove(board: boardSnapshot, botPlayer: player).0,
                        MinimaxAI.bestWildMove(board: boardSnapshot, botPlayer: player).1
                    )
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isThinking = false
                self.stopDotTimer()
                if let (idx, piece) = move {
                    self.place(idx, piece: piece, for: player)
                }
            }
        }
    }

    private func resetGame() {
        stopDotTimer()
        withAnimation {
            board = Array(repeating: nil, count: 9)
            currentPlayer = .x
            chosenPiece = .x
            result = .ongoing
            isThinking = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            triggerBotIfNeeded()
        }
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

#Preview {
    WildTTTView(mode: .vsBot, difficulty: .hard)
}
