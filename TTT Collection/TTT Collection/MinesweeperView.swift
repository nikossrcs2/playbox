//
//  MinesweeperGame.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI
internal import Combine

private class MinesweeperGame: ObservableObject {
    let rows = 9
    let cols = 9
    let mineCount = 10
    
    @Published var board: [[Cell]] = []
    @Published var gameOver = false
    @Published var win = false
    @Published var flagsRemaining: Int
    
    struct Cell: Equatable {
        var isMine = false
        var isRevealed = false
        var isFlagged = false
        var adjacentMines = 0
    }
    
    init() {
        flagsRemaining = mineCount
        reset()
    }
    
    func reset() {
        gameOver = false
        win = false
        flagsRemaining = mineCount
        initializeBoard()
        placeMines()
        calculateAdjacent()
    }
    
    private func initializeBoard() {
        board = Array(repeating: Array(repeating: Cell(), count: cols), count: rows)
    }
    
    private func placeMines() {
        var minesPlaced = 0
        while minesPlaced < mineCount {
            let row = Int.random(in: 0..<rows)
            let col = Int.random(in: 0..<cols)
            if !board[row][col].isMine {
                board[row][col].isMine = true
                minesPlaced += 1
            }
        }
    }
    
    private func calculateAdjacent() {
        for r in 0..<rows {
            for c in 0..<cols {
                if !board[r][c].isMine {
                    var count = 0
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let nr = r + dr
                            let nc = c + dc
                            if nr >= 0 && nr < rows && nc >= 0 && nc < cols && board[nr][nc].isMine {
                                count += 1
                            }
                        }
                    }
                    board[r][c].adjacentMines = count
                }
            }
        }
    }
    
    func revealCell(row: Int, col: Int) {
        guard !gameOver && !win else { return }
        guard !board[row][col].isFlagged else { return }
        guard !board[row][col].isRevealed else { return }
        
        if board[row][col].isMine {
            board[row][col].isRevealed = true
            gameOver = true
            revealAllMines()
            return
        }
        
        revealRecursive(row: row, col: col)
        checkWin()
    }
    
    private func revealRecursive(row: Int, col: Int) {
        guard row >= 0 && row < rows && col >= 0 && col < cols else { return }
        guard !board[row][col].isRevealed && !board[row][col].isFlagged else { return }
        guard !board[row][col].isMine else { return }
        
        board[row][col].isRevealed = true
        
        if board[row][col].adjacentMines == 0 {
            for dr in -1...1 {
                for dc in -1...1 {
                    if dr != 0 || dc != 0 {
                        revealRecursive(row: row + dr, col: col + dc)
                    }
                }
            }
        }
    }
    
    func toggleFlag(row: Int, col: Int) {
        guard !gameOver && !win else { return }
        guard !board[row][col].isRevealed else { return }
        
        if !board[row][col].isFlagged && flagsRemaining > 0 {
            board[row][col].isFlagged = true
            flagsRemaining -= 1
            
            // After flagging, check if we can auto-clear surrounding cells
            autoClearAdjacentIfNeeded(row: row, col: col)
        } else if board[row][col].isFlagged {
            board[row][col].isFlagged = false
            flagsRemaining += 1
        }
        
        checkWin()
    }
    
    // MARK: - Auto Clear (Chord)
    
    /// When a revealed cell has the same number of adjacent flags as its mine count,
    /// auto-reveal all adjacent non-flagged cells.
    func autoClearChord(row: Int, col: Int) {
        guard !gameOver && !win else { return }
        guard board[row][col].isRevealed else { return }
        
        let cell = board[row][col]
        let adjacentCells = getAdjacentCells(row: row, col: col)
        let flagCount = adjacentCells.filter { $0.isFlagged }.count
        
        // Only auto-clear if flags match the mine count
        if flagCount == cell.adjacentMines && cell.adjacentMines > 0 {
            var hasIncorrectFlag = false
            var cellsToReveal: [(Int, Int)] = []
            
            // Check for incorrect flags
            for (nr, nc, isFlagged, isRevealed, isMine) in adjacentCells.map({ ($0.row, $0.col, $0.isFlagged, $0.isRevealed, $0.isMine) }) {
                if isFlagged && !isMine {
                    hasIncorrectFlag = true
                    break
                }
                if !isFlagged && !isRevealed {
                    cellsToReveal.append((nr, nc))
                }
            }
            
            // Only auto-clear if no incorrect flags
            if !hasIncorrectFlag {
                for (nr, nc) in cellsToReveal {
                    revealCell(row: nr, col: nc)
                }
            }
        }
    }
    
    /// Called after flagging to check if any revealed cells can be auto-cleared
    private func autoClearAdjacentIfNeeded(row: Int, col: Int) {
        // Check all adjacent revealed cells
        for dr in -1...1 {
            for dc in -1...1 {
                let nr = row + dr
                let nc = col + dc
                if nr >= 0 && nr < rows && nc >= 0 && nc < cols {
                    if board[nr][nc].isRevealed {
                        autoClearChord(row: nr, col: nc)
                    }
                }
            }
        }
    }
    
    private func getAdjacentCells(row: Int, col: Int) -> [(row: Int, col: Int, isFlagged: Bool, isRevealed: Bool, isMine: Bool)] {
        var adjacent: [(row: Int, col: Int, isFlagged: Bool, isRevealed: Bool, isMine: Bool)] = []
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let nr = row + dr
                let nc = col + dc
                if nr >= 0 && nr < rows && nc >= 0 && nc < cols {
                    adjacent.append((row: nr, col: nc, isFlagged: board[nr][nc].isFlagged, isRevealed: board[nr][nc].isRevealed, isMine: board[nr][nc].isMine))
                }
            }
        }
        return adjacent
    }
    
    private func checkWin() {
        var revealedSafe = 0
        let totalSafe = rows * cols - mineCount
        
        for r in 0..<rows {
            for c in 0..<cols {
                if !board[r][c].isMine && board[r][c].isRevealed {
                    revealedSafe += 1
                }
            }
        }
        
        if revealedSafe == totalSafe {
            win = true
            gameOver = true
        }
    }
    
    private func revealAllMines() {
        for r in 0..<rows {
            for c in 0..<cols {
                if board[r][c].isMine {
                    board[r][c].isRevealed = true
                }
            }
        }
    }
    
    // Helper for UI to know if auto-clear is possible on a cell
    func canAutoClear(row: Int, col: Int) -> Bool {
        guard board[row][col].isRevealed else { return false }
        let cell = board[row][col]
        if cell.adjacentMines == 0 { return false }
        
        let adjacentCells = getAdjacentCells(row: row, col: col)
        let flagCount = adjacentCells.filter { $0.isFlagged }.count
        let unrevealedCount = adjacentCells.filter { !$0.isRevealed && !$0.isFlagged }.count
        
        return flagCount == cell.adjacentMines && unrevealedCount > 0
    }
}

struct MinesweeperView: View {
    @StateObject private var game = MinesweeperGame()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.red)
                    Text("\(game.flagsRemaining)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if game.gameOver {
                        Text(game.win ? "You Win! 🎉" : "Game Over 💀")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(game.win ? .green : .red)
                    }
                    
                    Spacer()
                    
                    Button {
                        game.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Game board
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let cellSize = size / CGFloat(game.cols)
                    
                    VStack(spacing: 0) {
                        ForEach(0..<game.rows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<game.cols, id: \.self) { col in
                                    cellView(row: row, col: col, size: cellSize)
                                }
                            }
                        }
                    }
                    .frame(width: size, height: size)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Instructions
                Text("Tap to reveal • Long press to flag")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Minesweeper")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
    
    @ViewBuilder
    private func cellView(row: Int, col: Int, size: CGFloat) -> some View {
        let cell = game.board[row][col]
        let canAuto = game.canAutoClear(row: row, col: col)
        
        ZStack {
            Rectangle()
                .fill(cell.isRevealed ? Color(.systemGray5) : Color(.systemGray3))
                .frame(width: size, height: size)
                .overlay(
                    Rectangle()
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            
            if cell.isRevealed {
                if cell.isMine {
                    Image(systemName: "burst.fill")
                        .foregroundColor(.black)
                        .font(.system(size: size * 0.5))
                } else if cell.adjacentMines > 0 {
                    Text("\(cell.adjacentMines)")
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundColor(numberColor(cell.adjacentMines))
                }
            } else if cell.isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundColor(.red)
                    .font(.system(size: size * 0.5))
            }
            
            // Visual hint for auto-clear
            if canAuto && !cell.isRevealed && !cell.isFlagged {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1.5)
                    .frame(width: size - 4, height: size - 4)
            }
        }
        .frame(width: size, height: size)
        .onTapGesture(count: 2) {
            if !game.gameOver {
                game.autoClearChord(row: row, col: col)
            }
        }
        .onTapGesture(count: 1) {
            if !game.gameOver {
                game.revealCell(row: row, col: col)
            }
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            if !game.gameOver {
                game.toggleFlag(row: row, col: col)
            }
        }
    }
    
    private func numberColor(_ num: Int) -> Color {
        switch num {
        case 1: return .blue
        case 2: return .green
        case 3: return .red
        case 4: return .purple
        case 5: return .orange
        default: return .black
        }
    }
}

#Preview {
    MinesweeperView()
}
