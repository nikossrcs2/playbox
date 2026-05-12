import SwiftUI
internal import Combine

class NotaktoState: ObservableObject {
    static let boardCount = 3

    @Published var boards: [[Player?]] = Array(repeating: Array(repeating: nil, count: 9), count: boardCount)
    @Published var deadBoards: [Bool] = Array(repeating: false, count: boardCount)
    @Published var currentPlayer: Player = .x
    @Published var loser: Player? = nil

    var isGameOver: Bool { loser != nil }
    var winner: Player? { loser.map { $0.opposite } }

    var aliveBoards: [Int] { (0..<Self.boardCount).filter { !deadBoards[$0] } }

    func place(board bIdx: Int, cell cIdx: Int) {
        guard !deadBoards[bIdx],
              boards[bIdx][cIdx] == nil,
              !isGameOver else { return }

        boards[bIdx][cIdx] = .x

        if let _ = WinChecker.checkWinner(board: boards[bIdx]) {
            deadBoards[bIdx] = true
            if aliveBoards.isEmpty {
                loser = currentPlayer
                return
            }
        }

        currentPlayer = currentPlayer.opposite
    }

    func reset() {
        boards = Array(repeating: Array(repeating: nil, count: 9), count: Self.boardCount)
        deadBoards = Array(repeating: false, count: Self.boardCount)
        currentPlayer = .x
        loser = nil
    }
}

struct NotaktoView: View {
    let mode: GameMode
    let difficulty: BotDifficulty

    @StateObject private var state = NotaktoState()
    @State private var isThinking = false
    @Environment(\.dismiss) private var dismiss

    private var isBot: Bool { mode == .vsBot }
    private var isAiVsAi: Bool { mode == .aiVsAi }
    private var botPlayer: Player { .o }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                statusBar
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                Spacer()

                boardsRow
                    .padding(.horizontal, 12)

                Spacer()

                legend
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notakto")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: state.currentPlayer) { _ in triggerBotIfNeeded() }
            .onAppear { triggerBotIfNeeded() }
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
        let isActive = !state.isGameOver && state.currentPlayer == player
        let isWinner = state.winner == player

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
            Text(isAiVsAi ? "AI" : (isBot && player == botPlayer ? "Bot" : "Player \(player.rawValue)"))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var statusCenter: some View {
        Group {
            if let winner = state.winner {
                Text("\(winner.rawValue) wins! 🎉")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(winner.color)
            } else if isThinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(state.currentPlayer.rawValue)'s turn")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(state.currentPlayer.color)
            }
        }
    }

    private var boardsRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let boardSize = (geo.size.width - spacing * 2) / 3

            HStack(spacing: spacing) {
                ForEach(0..<NotaktoState.boardCount, id: \.self) { bIdx in
                    notaktoBoardView(bIdx: bIdx, size: boardSize)
                }
            }
        }
        .frame(height: UIScreen.main.bounds.width / 3)
    }

    private func notaktoBoardView(bIdx: Int, size: CGFloat) -> some View {
        let isDead = state.deadBoards[bIdx]
        let isActive = !isDead && !state.isGameOver
        let cellSize = size / 3

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isDead
                    ? Color(.systemFill).opacity(0.8)
                    : Color(.secondarySystemGroupedBackground))

            notaktoGridLines(size: size)

            ForEach(0..<9, id: \.self) { cIdx in
                let row = cIdx / 3
                let col = cIdx % 3
                notaktoCell(bIdx: bIdx, cIdx: cIdx, size: cellSize, boardActive: isActive)
                    .position(
                        x: CGFloat(col) * cellSize + cellSize / 2,
                        y: CGFloat(row) * cellSize + cellSize / 2
                    )
            }

            if isDead {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.15))
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: size * 0.25))
                        .foregroundColor(.red.opacity(0.6))
                    Text("Dead")
                        .font(.system(size: size * 0.13, weight: .bold))
                        .foregroundColor(.red.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDead ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

    private func notaktoGridLines(size: CGFloat) -> some View {
        let cell = size / 3
        return ZStack {
            ForEach([1, 2], id: \.self) { i in
                Rectangle()
                    .fill(Color(.separator).opacity(0.4))
                    .frame(width: 1, height: size)
                    .position(x: cell * CGFloat(i), y: size / 2)
                Rectangle()
                    .fill(Color(.separator).opacity(0.4))
                    .frame(width: size, height: 1)
                    .position(x: size / 2, y: cell * CGFloat(i))
            }
        }
    }

    private func notaktoCell(bIdx: Int, cIdx: Int, size: CGFloat, boardActive: Bool) -> some View {
        let canTap = boardActive
            && state.boards[bIdx][cIdx] == nil
            && !isThinking
            && !isAiVsAi
            && !(isBot && state.currentPlayer == botPlayer)

        return Button {
            state.place(board: bIdx, cell: cIdx)
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: size, height: size)
                if state.boards[bIdx][cIdx] != nil {
                    Text("X")
                        .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(!canTap)
        .animation(.spring(response: 0.25), value: state.boards[bIdx][cIdx])
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("Both players place X — completing 3 in a row kills that board. Last player to cause a kill loses!")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    private var bottomBar: some View {
        Button {
            withAnimation { state.reset(); isThinking = false }
        } label: {
            Label("New Game", systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red)
                .cornerRadius(14)
        }
        .simultaneousGesture(TapGesture().onEnded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { triggerBotIfNeeded() }
        })
    }

    private func triggerBotIfNeeded() {
        guard !state.isGameOver, !isThinking else { return }
        let isAITurn = isAiVsAi || (isBot && state.currentPlayer == botPlayer)
        guard isAITurn else { return }
        isThinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if difficulty == .easy {
                let aliveBoards = state.aliveBoards
                if let bIdx = aliveBoards.randomElement(),
                   let cIdx = MinimaxAI.randomMove(board: state.boards[bIdx]) {
                    state.place(board: bIdx, cell: cIdx)
                }
            } else {
                let aliveBoards = state.aliveBoards
                var safeMoves: [(Int, Int)] = []
                var allMoves: [(Int, Int)] = []
                for bIdx in aliveBoards {
                    for cIdx in 0..<9 where state.boards[bIdx][cIdx] == nil {
                        allMoves.append((bIdx, cIdx))
                        var simBoard = state.boards[bIdx]
                        simBoard[cIdx] = .x
                        let wouldKill = WinChecker.checkWinner(board: simBoard) != nil
                        if !wouldKill {
                            safeMoves.append((bIdx, cIdx))
                        } else if aliveBoards.count > 1 {
                            safeMoves.append((bIdx, cIdx))
                        }
                    }
                }
                let candidates = safeMoves.isEmpty ? allMoves : safeMoves
                if let (bIdx, cIdx) = candidates.randomElement() {
                    state.place(board: bIdx, cell: cIdx)
                }
            }
            isThinking = false
        }
    }
}

#Preview {
    NotaktoView(mode: .vsHuman, difficulty: .hard)
}
