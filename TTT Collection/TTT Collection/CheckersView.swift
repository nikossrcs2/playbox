//
//  CheckerPiece.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI
internal import Combine

private enum CheckerPiece: Equatable {
    case red(isKing: Bool)
    case black(isKing: Bool)
    
    var color: Color {
        switch self {
        case .red: return .red
        case .black: return .black
        }
    }
    
    var isKing: Bool {
        switch self {
        case .red(let king): return king
        case .black(let king): return king
        }
    }
    
    func kinged() -> CheckerPiece {
        switch self {
        case .red: return .red(isKing: true)
        case .black: return .black(isKing: true)
        }
    }
}

private class CheckersGame: ObservableObject {
    @Published var board: [[CheckerPiece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    @Published var currentPlayer: CheckerPiece = .red(isKing: false)
    @Published var winner: CheckerPiece? = nil
    @Published var isThinking = false
    
    init() {
        setupBoard()
    }
    
    func setupBoard() {
        // Clear board
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        
        // Place black pieces (top)
        for row in 0..<3 {
            for col in 0..<8 {
                if (row + col) % 2 == 1 {
                    board[row][col] = .black(isKing: false)
                }
            }
        }
        
        // Place red pieces (bottom)
        for row in 5..<8 {
            for col in 0..<8 {
                if (row + col) % 2 == 1 {
                    board[row][col] = .red(isKing: false)
                }
            }
        }
        
        currentPlayer = .red(isKing: false)
        winner = nil
    }
    
    func isValidMove(from: (r: Int, c: Int), to: (r: Int, c: Int)) -> Bool {
        guard let piece = board[from.r][from.c] else { return false }
        guard piece.color == currentPlayer.color else { return false }
        guard board[to.r][to.c] == nil else { return false }
        
        let dr = to.r - from.r
        let dc = abs(to.c - from.c)
        
        // Normal move
        if abs(dr) == 1 && dc == 1 {
            if piece.isKing {
                return true
            } else {
                // Red moves up, black moves down
                if piece.color == .red && dr == -1 { return true }
                if piece.color == .black && dr == 1 { return true }
            }
        }
        
        // Jump move
        if abs(dr) == 2 && dc == 2 {
            let jumpedR = (from.r + to.r) / 2
            let jumpedC = (from.c + to.c) / 2
            if let jumped = board[jumpedR][jumpedC], jumped.color != piece.color {
                return true
            }
        }
        
        return false
    }
    
    func makeMove(from: (r: Int, c: Int), to: (r: Int, c: Int)) -> Bool {
        guard isValidMove(from: from, to: to) else { return false }
        
        let piece = board[from.r][from.c]!
        board[from.r][from.c] = nil
        board[to.r][to.c] = piece
        
        // Handle jumps
        if abs(to.r - from.r) == 2 {
            let jumpedR = (from.r + to.r) / 2
            let jumpedC = (from.c + to.c) / 2
            board[jumpedR][jumpedC] = nil
        }
        
        // King promotion
        if (piece.color == .red && to.r == 0) || (piece.color == .black && to.r == 7) {
            board[to.r][to.c] = piece.kinged()
        }
        
        // Check winner
        checkWinner()
        
        if winner == nil {
            currentPlayer = currentPlayer.color == .red ? .black(isKing: false) : .red(isKing: false)
        }
        
        return true
    }
    
    private func checkWinner() {
        var hasRed = false
        var hasBlack = false
        
        for row in 0..<8 {
            for col in 0..<8 {
                if let piece = board[row][col] {
                    if piece.color == .red { hasRed = true }
                    else { hasBlack = true }
                }
            }
        }
        
        if !hasRed { winner = .black(isKing: false) }
        else if !hasBlack { winner = .red(isKing: false) }
    }
    
    func getValidMoves(for piece: CheckerPiece, at pos: (r: Int, c: Int)) -> [(r: Int, c: Int)] {
        var moves: [(r: Int, c: Int)] = []
        let directions = piece.isKing ? [(-1,-1), (-1,1), (1,-1), (1,1)] :
            (piece.color == .red ? [(-1,-1), (-1,1)] : [(1,-1), (1,1)])
        
        for (dr, dc) in directions {
            let nr = pos.r + dr
            let nc = pos.c + dc
            if nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr][nc] == nil {
                moves.append((nr, nc))
            }
            
            // Jump
            let jr = pos.r + dr * 2
            let jc = pos.c + dc * 2
            if jr >= 0 && jr < 8 && jc >= 0 && jc < 8 && board[jr][jc] == nil {
                let mr = pos.r + dr
                let mc = pos.c + dc
                if let jumped = board[mr][mc], jumped.color != piece.color {
                    moves.append((jr, jc))
                }
            }
        }
        
        return moves
    }
    
    func getAIMove() -> ((r: Int, c: Int), (r: Int, c: Int))? {
        var allMoves: [((r: Int, c: Int), (r: Int, c: Int))] = []
        
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.color == currentPlayer.color {
                    let moves = getValidMoves(for: piece, at: (r, c))
                    for move in moves {
                        allMoves.append(((r, c), move))
                    }
                }
            }
        }
        
        return allMoves.randomElement()
    }
}

struct CheckersView: View {
    let mode: GameMode
    let difficulty: BotDifficulty
    
    @StateObject private var game = CheckersGame()
    @State private var selectedPos: (r: Int, c: Int)? = nil
    @State private var aiTurnScheduled = false
    @Environment(\.dismiss) private var dismiss
    
    private var isBot: Bool { mode == .vsBot }
    private var isAiVsAi: Bool { mode == .aiVsAi }
    private var botPlayer: CheckerPiece { .black(isKing: false) }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    playerChip(.red(isKing: false), isRed: true)
                    Spacer()
                    statusLabel
                    Spacer()
                    playerChip(.black(isKing: false), isRed: false)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Board
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let cellSize = size / 8
                    
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<8, id: \.self) { col in
                                    cellView(row: row, col: col, size: cellSize)
                                }
                            }
                        }
                    }
                    .frame(width: size, height: size)
                    .background(Color(.systemGray4))
                    .cornerRadius(12)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // New game button
                Button {
                    game.setupBoard()
                    selectedPos = nil
                    aiTurnScheduled = false
                    if isAiVsAi {
                        scheduleAITurn()
                    }
                } label: {
                    Label("New Game", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Checkers")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isAiVsAi && !aiTurnScheduled && game.winner == nil {
                    scheduleAITurn()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func playerChip(_ player: CheckerPiece, isRed: Bool) -> some View {
        let isActive = game.winner == nil && game.currentPlayer.color == player.color
        let isWinner = game.winner?.color == player.color
        
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill((isRed ? Color.red : Color.black).opacity(isActive || isWinner ? 0.15 : 0.05))
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(isRed ? Color.red : Color.black)
                    .frame(width: 32, height: 32)
            }
            .overlay(Circle().stroke((isRed ? Color.red : Color.black), lineWidth: isActive ? 2 : 0))
            Text(isBot && !isRed ? "Bot" : (isAiVsAi ? "AI" : "Player"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var statusLabel: some View {
        Group {
            if let w = game.winner {
                Text("\(w.color == .red ? "Red" : "Black") wins! 🎉")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(w.color == .red ? .red : .black)
            } else if game.isThinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(game.currentPlayer.color == .red ? "Red" : "Black")'s turn")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(game.currentPlayer.color == .red ? .red : .black)
            }
        }
    }
    
    @ViewBuilder
    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let isDark = (row + col) % 2 == 1
        let piece = game.board[row][col]
        let isSelected = selectedPos?.r == row && selectedPos?.c == col
        
        ZStack {
            Rectangle()
                .fill(isDark ? Color.brown.opacity(0.6) : Color(.systemGray5))
                .frame(width: size, height: size)
            
            if let p = piece {
                Circle()
                    .fill(p.color)
                    .frame(width: size * 0.7, height: size * 0.7)
                    .overlay(
                        Group {
                            if p.isKing {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: size * 0.25))
                                    .foregroundColor(.yellow)
                            }
                        }
                    )
            }
            
            if isSelected {
                Rectangle()
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: size, height: size)
            }
        }
        .onTapGesture {
            handleTap(row: row, col: col)
        }
    }
    
    private func handleTap(row: Int, col: Int) {
        guard game.winner == nil else { return }
        
        let isHumanTurn = !isAiVsAi && (!isBot || (isBot && game.currentPlayer.color != botPlayer.color))
        
        if let selected = selectedPos {
            // Try to move
            if game.makeMove(from: selected, to: (row, col)) {
                selectedPos = nil
                if isAiVsAi {
                    scheduleAITurn()
                } else if isBot && game.currentPlayer.color == botPlayer.color && game.winner == nil {
                    scheduleAITurn()
                }
            } else {
                // Invalid move, reselect if tapping on own piece
                if let piece = game.board[row][col], piece.color == game.currentPlayer.color && isHumanTurn {
                    selectedPos = (row, col)
                } else {
                    selectedPos = nil
                }
            }
        } else {
            // Select piece
            if let piece = game.board[row][col], piece.color == game.currentPlayer.color && isHumanTurn {
                selectedPos = (row, col)
            }
        }
    }
    
    private func scheduleAITurn() {
        guard !game.isThinking && game.winner == nil else { return }
        let shouldTakeTurn = (isBot && game.currentPlayer.color == botPlayer.color) || isAiVsAi
        guard shouldTakeTurn && !aiTurnScheduled else { return }

        aiTurnScheduled = true
        game.isThinking = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let move = game.getAIMove() {
                _ = game.makeMove(from: move.0, to: move.1)
            }
            game.isThinking = false
            aiTurnScheduled = false

            let stillAI = (self.isBot && self.game.currentPlayer.color == self.botPlayer.color) || self.isAiVsAi
            if self.game.winner == nil && stillAI {
                self.scheduleAITurn()
            }
        }
    }
}

#Preview {
    CheckersView(mode: .vsHuman, difficulty: .hard)
}
