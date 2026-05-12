import SwiftUI
internal import Combine

class SuperTTTState: ObservableObject {
    @Published var boards: [[Player?]] = Array(repeating: Array(repeating: nil, count: 9), count: 9)
    @Published var boardResults: [GameResult] = Array(repeating: .ongoing, count: 9)
    @Published var activeBoard: Int? = nil
    @Published var currentPlayer: Player = .x
    @Published var globalResult: GameResult = .ongoing

    func place(board bIdx: Int, cell cIdx: Int) {
        guard boards[bIdx][cIdx] == nil,
              boardResults[bIdx] == .ongoing,
              globalResult == .ongoing else { return }

        boards[bIdx][cIdx] = currentPlayer

        let miniResult = WinChecker.result(board: boards[bIdx])
        if miniResult != .ongoing { boardResults[bIdx] = miniResult }

        let globalBoards: [Player?] = boardResults.map {
            if case .win(let w, _) = $0 { return w }
            return nil
        }
        globalResult = WinChecker.result(board: globalBoards)

        activeBoard = (boardResults[cIdx] == .ongoing) ? cIdx : nil
        currentPlayer = currentPlayer.opposite
    }

    func reset() {
        boards = Array(repeating: Array(repeating: nil, count: 9), count: 9)
        boardResults = Array(repeating: .ongoing, count: 9)
        activeBoard = nil
        currentPlayer = .x
        globalResult = .ongoing
    }

    func validBoards() -> [Int] {
        if let forced = activeBoard { return [forced] }
        return (0..<9).filter { boardResults[$0] == .ongoing }
    }

    /// Snapshot suitable for MinimaxAI
    func minimaxState() -> MinimaxAI.SuperState {
        MinimaxAI.SuperState(
            boards: boards,
            boardResults: boardResults,
            activeBoard: activeBoard,
            currentPlayer: currentPlayer
        )
    }
}


struct SuperTTTView: View {
    let mode: GameMode
    let difficulty: BotDifficulty

    @StateObject private var state = SuperTTTState()
    @State private var isThinking = false
    @State private var thinkingDots = 0
    @State private var dotTimer: Timer? = nil
    @Environment(\.dismiss) private var dismiss

    private var isBot: Bool { mode == .vsBot }
    private var botPlayer: Player { .o }
    private var isAiVsAi: Bool { mode == .aiVsAi }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                statusBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                globalBoardView
                    .padding(.horizontal, 12)

                Spacer()

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Super TTT")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { triggerBotIfNeeded() }
            .onDisappear { stopDotTimer() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            playerChip(.x)
            Spacer()
            statusLabel
            Spacer()
            playerChip(.o)
        }
    }

    private func playerChip(_ player: Player) -> some View {
        let isActive = state.globalResult == .ongoing && state.currentPlayer == player
        let isWinner: Bool = {
            if case .win(let w, _) = state.globalResult { return w == player }
            return false
        }()

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(player.color.opacity(isActive || isWinner ? 0.15 : 0.05))
                    .frame(width: 44, height: 44)
                Text(player.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(player.color.opacity(isActive || isWinner ? 1 : 0.3))
            }
            .overlay(Circle().stroke(player.color, lineWidth: isActive ? 2 : 0))
            Text(playerLabel(player))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    private func playerLabel(_ player: Player) -> String {
        if isAiVsAi { return "AI" }
        if isBot && player == botPlayer {
            return difficulty == .neural ? "Neural" : "Bot"
        }
        return "Player"
    }

    private var statusLabel: some View {
        Group {
            switch state.globalResult {
            case .ongoing:
                if isThinking {
                    Text("Thinking" + String(repeating: ".", count: thinkingDots + 1))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .animation(.none, value: thinkingDots)
                } else {
                    VStack(spacing: 2) {
                        Text("\(state.currentPlayer.rawValue)'s turn")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(state.currentPlayer.color)
                        Text(state.activeBoard == nil ? "Play anywhere" : "Board \(state.activeBoard! + 1)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            case .win(let winner, _):
                Text("\(winner.rawValue) wins! 🎉")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(winner.color)
            case .draw:
                Text("It's a draw!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Board

    private var globalBoardView: some View {
        GeometryReader { geo in
            let totalSize = min(geo.size.width, geo.size.height)
            let gap: CGFloat = 6
            let boardSize = (totalSize - gap * 4) / 3

            ZStack {
                globalGridLines(size: totalSize, gap: gap)
                ForEach(0..<9, id: \.self) { bIdx in
                    let row = bIdx / 3
                    let col = bIdx % 3
                    let x = CGFloat(col) * (boardSize + gap) + boardSize / 2 + gap
                    let y = CGFloat(row) * (boardSize + gap) + boardSize / 2 + gap
                    miniBoardView(bIdx: bIdx, size: boardSize).position(x: x, y: y)
                }
            }
            .frame(width: totalSize, height: totalSize)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func globalGridLines(size: CGFloat, gap: CGFloat) -> some View {
        let boardSize = (size - gap * 4) / 3
        let step = boardSize + gap
        return ZStack {
            ForEach([1, 2], id: \.self) { i in
                Rectangle()
                    .fill(Color(.separator).opacity(0.8))
                    .frame(width: gap, height: size)
                    .position(x: CGFloat(i) * step + gap / 2 + gap, y: size / 2)
                Rectangle()
                    .fill(Color(.separator).opacity(0.8))
                    .frame(width: size, height: gap)
                    .position(x: size / 2, y: CGFloat(i) * step + gap / 2 + gap)
            }
        }
    }

    @ViewBuilder
    private func miniBoardView(bIdx: Int, size: CGFloat) -> some View {
        let isActive = state.validBoards().contains(bIdx) && state.globalResult == .ongoing
        let boardResult = state.boardResults[bIdx]
        let cellSize = size / 3

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive
                    ? state.currentPlayer.color.opacity(0.08)
                    : Color(.systemBackground).opacity(0.3))

            miniGridLines(size: size)

            ForEach(0..<9, id: \.self) { cIdx in
                let row = cIdx / 3
                let col = cIdx % 3
                miniCell(bIdx: bIdx, cIdx: cIdx, size: cellSize, boardActive: isActive)
                    .position(x: CGFloat(col) * cellSize + cellSize / 2,
                              y: CGFloat(row) * cellSize + cellSize / 2)
            }

            if case .win(let winner, _) = boardResult {
                WinOverlayView(winner: winner, size: size)
            } else if boardResult == .draw {
                RoundedRectangle(cornerRadius: 8).fill(Color(.systemFill).opacity(0.6))
                Text("Draw").font(.system(size: size * 0.18, weight: .bold)).foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? state.currentPlayer.color : Color.clear, lineWidth: 2))
    }

    private func miniGridLines(size: CGFloat) -> some View {
        let cell = size / 3
        return ZStack {
            ForEach([1, 2], id: \.self) { i in
                Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 1, height: size)
                    .position(x: cell * CGFloat(i), y: size / 2)
                Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: size, height: 1)
                    .position(x: size / 2, y: cell * CGFloat(i))
            }
        }
    }

    private func miniCell(bIdx: Int, cIdx: Int, size: CGFloat, boardActive: Bool) -> some View {
        let canTap = boardActive
            && state.boards[bIdx][cIdx] == nil
            && state.globalResult == .ongoing
            && !isThinking && !isAiVsAi
            && !(isBot && state.currentPlayer == botPlayer)

        return Button {
            state.place(board: bIdx, cell: cIdx)
            triggerBotIfNeeded()
        } label: {
            ZStack {
                Rectangle().fill(Color.clear).frame(width: size, height: size)
                if let player = state.boards[bIdx][cIdx] {
                    Text(player.rawValue)
                        .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                        .foregroundColor(player.color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(!canTap)
        .animation(.spring(response: 0.25), value: state.boards[bIdx][cIdx])
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Button {
            withAnimation { state.reset(); isThinking = false }
            stopDotTimer()
        } label: {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple)
                .cornerRadius(14)
        }
    }

    // MARK: - AI Logic

    private func triggerBotIfNeeded() {
        guard state.globalResult == .ongoing, !isThinking else { return }
        let isAITurn = isAiVsAi || (isBot && state.currentPlayer == botPlayer)
        guard isAITurn else { return }

        isThinking = true
        startDotTimer()

        let snapshot = state.minimaxState()
        let capturedState = state
        let capturedDifficulty = difficulty
        let capturedIsAiVsAi = isAiVsAi

        DispatchQueue.global(qos: .userInitiated).async {
            let (bIdx, cIdx): (Int, Int)

            switch capturedDifficulty {
            case .easy:
                let validBds = snapshot.activeBoard.map { [$0] }
                    ?? (0..<9).filter { snapshot.boardResults[$0] == .ongoing }
                let b = validBds.randomElement() ?? 0
                let c = snapshot.boards[b].indices.filter { snapshot.boards[b][$0] == nil }.randomElement() ?? 0
                (bIdx, cIdx) = (b, c)

            case .hard:
                (bIdx, cIdx) = MinimaxAI.bestSuperMove(state: snapshot)

            case .neural:
                let neural = NeuralAIStore.shared.model(for: .superTTT)
                if neural.trainedEpisodes > 0,
                   let move = neural.pickSuperTTTMove(
                       boards: snapshot.boards,
                       boardResults: snapshot.boardResults,
                       activeBoard: snapshot.activeBoard,
                       player: snapshot.currentPlayer
                   ) {
                    (bIdx, cIdx) = move
                } else {
                    (bIdx, cIdx) = MinimaxAI.bestSuperMove(state: snapshot)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                capturedState.place(board: bIdx, cell: cIdx)
                isThinking = false
                stopDotTimer()

                if capturedIsAiVsAi && capturedState.globalResult == .ongoing {
                    triggerBotIfNeeded()
                }
            }
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

struct WinOverlayView: View {
    let winner: Player
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(winner.color.opacity(0.25))
            Text(winner.rawValue)
                .font(.system(size: size * 0.55, weight: .black, design: .rounded))
                .foregroundColor(winner.color.opacity(0.8))
        }
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    SuperTTTView(mode: .vsBot, difficulty: .hard)
}
