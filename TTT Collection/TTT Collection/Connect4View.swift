//
//  Connect4View.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI

struct Connect4View: View {
    let mode: GameMode
    let difficulty: BotDifficulty
    
    private let rows = 6
    private let cols = 7
    
    @State private var board: [[Player?]] = Array(repeating: Array(repeating: nil, count: 7), count: 6)
    @State private var currentPlayer: Player = .x
    @State private var winner: Player? = nil
    @State private var isDraw = false
    @State private var isThinking = false
    @State private var aiTurnScheduled = false
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
                
                boardView
                    .padding(.horizontal, 20)
                
                Spacer()
                
                if !isAiVsAi {
                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                } else {
                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Connect 4")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isAiVsAi && !aiTurnScheduled {
                    scheduleAITurn()
                }
            }
            .onChange(of: currentPlayer) { _ in
                scheduleAITurn()
            }
        }
        .navigationViewStyle(.stack)
    }
    
    // MARK: - Status Bar
    
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
        let isActive = winner == nil && !isDraw && currentPlayer == player
        let isWinner = winner == player
        
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(player.color.opacity(isActive || isWinner ? 0.15 : 0.05))
                    .frame(width: 48, height: 48)
                Circle()
                    .fill(player.color.opacity(isActive || isWinner ? 1 : 0.3))
                    .frame(width: 36, height: 36)
                Text(player.rawValue)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .overlay(Circle().stroke(player.color, lineWidth: isActive ? 2 : 0))
            Text(isBot && player == botPlayer ? "Bot" : (isAiVsAi ? "AI \(player.rawValue)" : "Player \(player.rawValue)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var statusCenter: some View {
        Group {
            if let w = winner {
                Text("\(w.rawValue) wins! 🎉")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(w.color)
            } else if isDraw {
                Text("It's a draw!")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
            } else if isThinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(currentPlayer.rawValue)'s turn")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(currentPlayer.color)
            }
        }
    }
    
    // MARK: - Board View
    
    private var boardView: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cellSize = size / CGFloat(cols)
            
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            cellView(row: row, col: col, size: cellSize)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .frame(width: size, height: size * CGFloat(rows) / CGFloat(cols))
        }
        .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
    }
    
    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let canDrop = winner == nil && !isDraw && currentPlayer != nil && !isThinking
            && !(isBot && currentPlayer == botPlayer)
            && !isAiVsAi
            && board[0][col] == nil
        
        return Button {
            dropDisc(col: col)
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: size, height: size)
                
                Circle()
                    .stroke(Color(.separator), lineWidth: 1.5)
                    .frame(width: size - 8, height: size - 8)
                
                if let player = board[row][col] {
                    Circle()
                        .fill(player.color)
                        .frame(width: size - 12, height: size - 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .disabled(!canDrop)
        .animation(.spring(response: 0.3), value: board[row][col])
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                resetGame()
            } label: {
                Label("New Game", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow)
                    .cornerRadius(14)
            }
        }
    }
    
    // MARK: - Game Logic
    
    private func dropDisc(col: Int) {
        guard winner == nil && !isDraw else { return }
        
        // Find the target row
        var targetRow = -1
        for row in (0..<rows).reversed() {
            if board[row][col] == nil {
                targetRow = row
                break
            }
        }
        
        guard targetRow != -1 else { return }
        
        // Animate dropping
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            board[targetRow][col] = currentPlayer
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Check win/draw after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let w = WinChecker.c4CheckWinner(board: self.board) {
                self.winner = w
            } else if WinChecker.c4IsFull(board: self.board) {
                self.isDraw = true
            } else {
                self.currentPlayer = self.currentPlayer.opposite
            }
        }
    }
    
    private func scheduleAITurn() {
        guard !isThinking && winner == nil && !isDraw else { return }
        let shouldTakeTurn = (isBot && currentPlayer == botPlayer) || isAiVsAi
        guard shouldTakeTurn && !aiTurnScheduled else { return }

        aiTurnScheduled = true
        isThinking = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isAiVsAi {
                let col = getAIMove(for: currentPlayer)
                dropDisc(col: col)
            } else {
                let col = getAIMove(for: botPlayer)
                dropDisc(col: col)
            }
            isThinking = false
            aiTurnScheduled = false

            // Re-trigger for AI vs AI after each move
            if isAiVsAi && winner == nil && !isDraw {
                scheduleAITurn()
            }
        }
    }
    
    private func getAIMove(for player: Player) -> Int {
        if difficulty == .easy {
            var availableCols: [Int] = []
            for col in 0..<cols {
                if board[0][col] == nil {
                    availableCols.append(col)
                }
            }
            return availableCols.randomElement() ?? 0
        } else {
            return MinimaxAI.bestConnect4Move(board: board, player: player)
        }
    }
    
    private func resetGame() {
        withAnimation {
            board = Array(repeating: Array(repeating: nil, count: cols), count: rows)
            currentPlayer = .x
            winner = nil
            isDraw = false
            isThinking = false
            aiTurnScheduled = false
        }
        
        if isAiVsAi {
            scheduleAITurn()
        }
    }
}

#Preview {
    Connect4View(mode: .vsHuman, difficulty: .hard)
}
