//
//  ChessPieceType.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//

import SwiftUI
internal import Combine

private enum ChessPieceType: String {
    case pawn, rook, knight, bishop, queen, king
}

private struct ChessPiece: Equatable {
    let type: ChessPieceType
    let color: Color
    
    var symbol: String {
        let base: String
        switch type {
        case .pawn: base = "p"
        case .rook: base = "r"
        case .knight: base = "n"
        case .bishop: base = "b"
        case .queen: base = "q"
        case .king: base = "k"
        }
        return color == .white ? base.uppercased() : base
    }
    
    /// Name of the sprite sheet asset: "white" or "black"
    var spriteSheetName: String {
        color == .white ? "white" : "black"
    }

    /// Index of this piece in the sprite sheet (left = 0).
    /// Order in both "white" and "black" assets: bishop(0), king(1), knight(2), pawn(3), queen(4), rook(5)
    var spriteIndex: Int {
        switch type {
        case .bishop: return 0
        case .king:   return 1
        case .knight: return 2
        case .pawn:   return 3
        case .queen:  return 4
        case .rook:   return 5
        }
    }

    /// Crops the correct piece out of the 6-piece horizontal sprite sheet.
    func spriteImage(cellSize: CGFloat) -> Image? {
        guard let sheet = UIImage(named: spriteSheetName) else { return nil }
        let totalCols = 6
        let tileW = sheet.size.width / CGFloat(totalCols)
        let tileH = sheet.size.height
        let cropRect = CGRect(x: CGFloat(spriteIndex) * tileW, y: 0, width: tileW, height: tileH)
        guard let cgImage = sheet.cgImage?.cropping(to: cropRect) else { return nil }
        return Image(uiImage: UIImage(cgImage: cgImage, scale: sheet.scale, orientation: sheet.imageOrientation))
    }
}

private class ChessGame: ObservableObject {
    @Published var board: [[ChessPiece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
    @Published var currentPlayer: Color = .white
    @Published var winner: Color? = nil
    @Published var isThinking = false
    @Published var checkWarning: Bool = false
    
    init() {
        setupBoard()
    }
    
    func setupBoard() {
        // Clear
        board = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        
        // Pawns
        for col in 0..<8 {
            board[1][col] = ChessPiece(type: .pawn, color: .black)
            board[6][col] = ChessPiece(type: .pawn, color: .white)
        }
        
        // Major pieces
        let backRow: [ChessPieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for col in 0..<8 {
            board[0][col] = ChessPiece(type: backRow[col], color: .black)
            board[7][col] = ChessPiece(type: backRow[col], color: .white)
        }
        
        currentPlayer = .white
        winner = nil
        checkWarning = false
    }
    
    // MARK: - Move validation (piece movement rules only, no self-check filter)

    /// Returns true if the piece at `from` can reach `to` by its movement rules,
    /// ignoring whether the move leaves the moving side's king in check.
    /// Used internally by isSquareAttacked and as the base for isValidMove.
    private func pieceCanMove(from: (r: Int, c: Int), to: (r: Int, c: Int), as color: Color) -> Bool {
        guard from.r != to.r || from.c != to.c else { return false }
        guard to.r >= 0, to.r < 8, to.c >= 0, to.c < 8 else { return false }
        guard let piece = board[from.r][from.c], piece.color == color else { return false }
        if let target = board[to.r][to.c], target.color == color { return false }

        let dr = to.r - from.r
        let dc = to.c - from.c
        let absDr = abs(dr)
        let absDc = abs(dc)

        switch piece.type {
        case .pawn:
            let dir = color == .white ? -1 : 1
            let startRow = color == .white ? 6 : 1
            if dc == 0 && dr == dir && board[to.r][to.c] == nil { return true }
            if dc == 0 && dr == dir * 2 && from.r == startRow
                && board[from.r + dir][from.c] == nil && board[to.r][to.c] == nil { return true }
            if absDc == 1 && dr == dir,
               let target = board[to.r][to.c], target.color != color { return true }
            return false
        case .rook:
            guard dr == 0 || dc == 0 else { return false }
            return isPathClear(from: from, to: to)
        case .knight:
            return (absDr == 2 && absDc == 1) || (absDr == 1 && absDc == 2)
        case .bishop:
            guard absDr == absDc else { return false }
            return isPathClear(from: from, to: to)
        case .queen:
            guard dr == 0 || dc == 0 || absDr == absDc else { return false }
            return isPathClear(from: from, to: to)
        case .king:
            return absDr <= 1 && absDc <= 1
        }
    }

    private func isPathClear(from: (r: Int, c: Int), to: (r: Int, c: Int)) -> Bool {
        let dr = to.r - from.r
        let dc = to.c - from.c
        let stepR = dr == 0 ? 0 : dr / abs(dr)
        let stepC = dc == 0 ? 0 : dc / abs(dc)
        var r = from.r + stepR
        var c = from.c + stepC
        while r != to.r || c != to.c {
            if board[r][c] != nil { return false }
            r += stepR
            c += stepC
        }
        return true
    }

    /// Returns true if `pos` is attacked by any piece of `color` on the given board.
    private func isSquareAttacked(at pos: (r: Int, c: Int), by color: Color, on b: [[ChessPiece?]]? = nil) -> Bool {
        let brd = b ?? board
        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = brd[r][c], piece.color == color else { continue }
                // Temporarily use the supplied board for path-clear checks by
                // swapping self.board — safest to do inline attack check here.
                let dr = pos.r - r
                let dc = pos.c - c
                let absDr = abs(dr)
                let absDc = abs(dc)
                let attacks: Bool
                switch piece.type {
                case .pawn:
                    let dir = color == .white ? -1 : 1
                    attacks = dr == dir && absDc == 1
                case .knight:
                    attacks = (absDr == 2 && absDc == 1) || (absDr == 1 && absDc == 2)
                case .king:
                    attacks = absDr <= 1 && absDc <= 1
                case .rook:
                    attacks = (dr == 0 || dc == 0) && isPathClearOn(brd, from: (r, c), to: pos)
                case .bishop:
                    attacks = absDr == absDc && isPathClearOn(brd, from: (r, c), to: pos)
                case .queen:
                    attacks = (dr == 0 || dc == 0 || absDr == absDc) && isPathClearOn(brd, from: (r, c), to: pos)
                }
                if attacks { return true }
            }
        }
        return false
    }

    private func isPathClearOn(_ brd: [[ChessPiece?]], from: (r: Int, c: Int), to: (r: Int, c: Int)) -> Bool {
        let dr = to.r - from.r
        let dc = to.c - from.c
        let stepR = dr == 0 ? 0 : dr / abs(dr)
        let stepC = dc == 0 ? 0 : dc / abs(dc)
        var r = from.r + stepR
        var c = from.c + stepC
        while r != to.r || c != to.c {
            if brd[r][c] != nil { return false }
            r += stepR
            c += stepC
        }
        return true
    }

    /// Simulates a move on a copy of the board and returns true if the moving
    /// side's king is NOT in check afterwards (i.e. the move is legal).
    private func moveLeavesKingSafe(from: (r: Int, c: Int), to: (r: Int, c: Int), color: Color) -> Bool {
        var copy = board
        let piece = copy[from.r][from.c]!
        copy[to.r][to.c] = piece
        copy[from.r][from.c] = nil
        // Pawn promotion on copy (to queen) so king-safety check is accurate
        if piece.type == .pawn && ((color == .white && to.r == 0) || (color == .black && to.r == 7)) {
            copy[to.r][to.c] = ChessPiece(type: .queen, color: color)
        }
        // Find king on the copied board
        var kingPos: (r: Int, c: Int)? = nil
        for r in 0..<8 {
            for c in 0..<8 {
                if let p = copy[r][c], p.type == .king, p.color == color { kingPos = (r, c) }
            }
        }
        guard let kp = kingPos else { return false }
        return !isSquareAttacked(at: kp, by: color == .white ? .black : .white, on: copy)
    }

    /// Full legal-move check: piece movement rules + does not leave own king in check.
    func isValidMove(from: (r: Int, c: Int), to: (r: Int, c: Int)) -> Bool {
        guard let piece = board[from.r][from.c], piece.color == currentPlayer else { return false }
        guard pieceCanMove(from: from, to: to, as: currentPlayer) else { return false }
        return moveLeavesKingSafe(from: from, to: to, color: currentPlayer)
    }

    func makeMove(from: (r: Int, c: Int), to: (r: Int, c: Int)) -> Bool {
        guard isValidMove(from: from, to: to) else { return false }

        let piece = board[from.r][from.c]!
        board[to.r][to.c] = piece
        board[from.r][from.c] = nil

        // Pawn promotion to queen
        if piece.type == .pawn && ((piece.color == .white && to.r == 0) || (piece.color == .black && to.r == 7)) {
            board[to.r][to.c] = ChessPiece(type: .queen, color: piece.color)
        }

        // Flip turn
        currentPlayer = currentPlayer == .white ? .black : .white

        // Check if the new current player (just became their turn) is in check
        let opponent = currentPlayer == .white ? Color.black : Color.white
        if let kingPos = findKing(for: currentPlayer),
           isSquareAttacked(at: kingPos, by: opponent) {
            checkWarning = true
        } else {
            checkWarning = false
        }

        // Checkmate vs stalemate: does the new current player have any legal moves?
        if !hasAnyLegalMoves(for: currentPlayer) {
            if checkWarning {
                // In check with no moves → checkmate; the player who just moved wins
                winner = opponent
            } else {
                // Not in check with no moves → stalemate; it's a draw
                // Signal draw by setting winner to nil but ending the game via a
                // dedicated flag would be cleaner; for now set both to signal draw.
                winner = currentPlayer  // will show "draw" in statusLabel below
            }
        }

        return true
    }

    private func findKing(for color: Color) -> (r: Int, c: Int)? {
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board[r][c], piece.type == .king, piece.color == color {
                    return (r, c)
                }
            }
        }
        return nil
    }

    /// Returns true if `color` has at least one fully-legal move available.
    /// Temporarily overrides currentPlayer so isValidMove works for either side.
    private func hasAnyLegalMoves(for color: Color) -> Bool {
        let saved = currentPlayer
        currentPlayer = color
        defer { currentPlayer = saved }
        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = board[r][c], piece.color == color else { continue }
                for tr in 0..<8 {
                    for tc in 0..<8 {
                        if isValidMove(from: (r, c), to: (tr, tc)) { return true }
                    }
                }
            }
        }
        return false
    }

    func getAIMove() -> ((r: Int, c: Int), (r: Int, c: Int))? {
        var allMoves: [((r: Int, c: Int), (r: Int, c: Int), value: Int)] = []
        
        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = board[r][c], piece.color == currentPlayer else { continue }
                for tr in 0..<8 {
                    for tc in 0..<8 {
                        if isValidMove(from: (r, c), to: (tr, tc)) {
                            // Evaluate move value
                            var value = 0
                            // Capture piece value
                            if let target = board[tr][tc] {
                                let pieceValues: [ChessPieceType: Int] = [
                                    .pawn: 10, .knight: 30, .bishop: 30,
                                    .rook: 50, .queen: 90, .king: 900
                                ]
                                value += pieceValues[target.type] ?? 0
                            }
                            // Prefer center control
                            let centerDist = abs(Double(tr) - 3.5) + abs(Double(tc) - 3.5)
                            value += Int((7 - centerDist) * 2)
                            // Prefer moving pieces that haven't moved
                            value += 1
                            
                            allMoves.append(((r, c), (tr, tc), value))
                        }
                    }
                }
            }
        }
        
        // Sort by value and pick best (with some randomness)
        allMoves.sort { $0.value > $1.value }
        let topMoves = Array(allMoves.prefix(max(3, allMoves.count / 3)))
        return topMoves.randomElement().map { ($0.0, $0.1) }
    }
}

struct ChessView: View {
    let mode: GameMode
    let difficulty: BotDifficulty
    
    @StateObject private var game = ChessGame()
    @State private var selectedPos: (r: Int, c: Int)? = nil
    @State private var aiTurnScheduled = false
    @Environment(\.dismiss) private var dismiss
    
    private var isBot: Bool { mode == .vsBot }
    private var isAiVsAi: Bool { mode == .aiVsAi }
    private var botPlayer: Color { .black }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    playerChip(.white)
                    Spacer()
                    statusLabel
                    Spacer()
                    playerChip(.black)
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
                        .background(Color.blue)
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chess")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if isAiVsAi && !aiTurnScheduled && game.winner == nil {
                    scheduleAITurn()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func playerChip(_ color: Color) -> some View {
        let isActive = game.winner == nil && game.currentPlayer == color
        let isWinner = game.winner == color
        
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(isActive || isWinner ? 0.15 : 0.05))
                    .frame(width: 44, height: 44)
                Image(systemName: color == .white ? "circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundColor(color)
            }
            .overlay(Circle().stroke(color, lineWidth: isActive ? 2 : 0))
            Text(isBot && color == .black ? "Bot" : (isAiVsAi ? "AI" : "Player"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
    
    private var statusLabel: some View {
        Group {
            if let w = game.winner {
                // Stalemate: winner == currentPlayer (the side that has no moves but is NOT in check)
                if w == game.currentPlayer && !game.checkWarning {
                    Text("Stalemate — Draw!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                } else {
                    Text("\(w == .white ? "White" : "Black") wins! 🎉")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(w)
                }
            } else if game.checkWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Check!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }
            } else if game.isThinking {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("\(game.currentPlayer == .white ? "White" : "Black")'s turn")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(game.currentPlayer)
            }
        }
    }
    
    @ViewBuilder
    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let isDark = (row + col) % 2 == 0
        let piece = game.board[row][col]
        let isSelected = selectedPos?.r == row && selectedPos?.c == col
        
        ZStack {
            Rectangle()
                .fill(isDark ? Color.brown.opacity(0.6) : Color(.systemGray5))
                .frame(width: size, height: size)
            
            if let p = piece {
                if let image = p.spriteImage(cellSize: size) {
                    image
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size * 0.7, height: size * 0.7)
                } else {
                    // Fallback to letter symbols if assets are missing
                    Text(p.symbol)
                        .font(.system(size: size * 0.35))
                        .foregroundColor(p.color)
                }
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
        
        let isHumanTurn = !isAiVsAi && (!isBot || (isBot && game.currentPlayer != botPlayer))
        
        if let selected = selectedPos {
            if game.makeMove(from: selected, to: (row, col)) {
                selectedPos = nil
                if isAiVsAi {
                    scheduleAITurn()
                } else if isBot && game.currentPlayer == botPlayer && game.winner == nil {
                    scheduleAITurn()
                }
            } else {
                if let piece = game.board[row][col], piece.color == game.currentPlayer && isHumanTurn {
                    selectedPos = (row, col)
                } else {
                    selectedPos = nil
                }
            }
        } else {
            if let piece = game.board[row][col], piece.color == game.currentPlayer && isHumanTurn {
                selectedPos = (row, col)
            }
        }
    }
    
    private func scheduleAITurn() {
        guard !game.isThinking && game.winner == nil else { return }
        let shouldTakeTurn = (isBot && game.currentPlayer == botPlayer) || isAiVsAi
        guard shouldTakeTurn && !aiTurnScheduled else { return }

        aiTurnScheduled = true
        game.isThinking = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let move = game.getAIMove() {
                _ = game.makeMove(from: move.0, to: move.1)
            }
            game.isThinking = false
            aiTurnScheduled = false

            let stillAI = (self.isBot && self.game.currentPlayer == self.botPlayer) || self.isAiVsAi
            if self.game.winner == nil && stillAI {
                self.scheduleAITurn()
            }
        }
    }
}

#Preview {
    ChessView(mode: .vsHuman, difficulty: .hard)
}
