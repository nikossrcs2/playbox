//
//  Twenty48Game.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//

import SwiftUI
internal import Combine

private class Twenty48Game: ObservableObject {
    @Published var board: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    @Published var score: Int = 0
    @Published var gameOver: Bool = false
    @Published var win: Bool = false
    @Published var chaosMode: Bool = false
    @Published var movesSinceChaos: Int = 0
    
    init() {
        reset()
    }
    
    func reset() {
        board = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        score = 0
        gameOver = false
        win = false
        movesSinceChaos = 0
        addRandomTile()
        addRandomTile()
    }
    
    func toggleChaosMode() {
        chaosMode.toggle()
        if chaosMode {
            movesSinceChaos = 0
        }
    }
    
    func addRandomTile() {
        var emptyCells: [(Int, Int)] = []
        for r in 0..<4 {
            for c in 0..<4 {
                if board[r][c] == 0 {
                    emptyCells.append((r, c))
                }
            }
        }
        
        if let (r, c) = emptyCells.randomElement() {
            board[r][c] = Bool.random() ? 2 : 4
        }
    }
    
    func move(_ direction: (dx: Int, dy: Int)) {
        guard !gameOver && !win else { return }
        
        var moved = false
        let reversed = direction.dx > 0 || direction.dy > 0
        
        if direction.dx != 0 {
            for r in 0..<4 {
                var row = (0..<4).map { board[r][$0] }
                if reversed { row.reverse() }
                let newRow = slideAndMerge(row)
                var result = newRow
                if reversed { result.reverse() }
                if result != (0..<4).map({ board[r][$0] }) {
                    moved = true
                    for c in 0..<4 { board[r][c] = result[c] }
                }
            }
        } else {
            for c in 0..<4 {
                var col = (0..<4).map { board[$0][c] }
                if reversed { col.reverse() }
                let newCol = slideAndMerge(col)
                var result = newCol
                if reversed { result.reverse() }
                if result != (0..<4).map({ board[$0][c] }) {
                    moved = true
                    for r in 0..<4 { board[r][c] = result[r] }
                }
            }
        }
        
        if moved {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                addRandomTile()
            }
            movesSinceChaos += 1
            
            if chaosMode && movesSinceChaos >= 10 {
                withAnimation(.easeInOut(duration: 0.4)) {
                    rotateBoard()
                }
                movesSinceChaos = 0
            }
            
            checkGameState()
        }
    }
    
    private func slideAndMerge(_ line: [Int]) -> [Int] {
        let filtered = line.filter { $0 != 0 }
        var merged = [Int]()
        var i = 0
        
        while i < filtered.count {
            if i + 1 < filtered.count && filtered[i] == filtered[i + 1] {
                let value = filtered[i] * 2
                merged.append(value)
                score += value
                i += 2
            } else {
                merged.append(filtered[i])
                i += 1
            }
        }
        
        while merged.count < 4 {
            merged.append(0)
        }
        
        return merged
    }
    
    private func rotateBoard() {
        var rotated = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        for r in 0..<4 {
            for c in 0..<4 {
                rotated[c][3 - r] = board[r][c]
            }
        }
        board = rotated
    }
    
    private func checkGameState() {
        // Check win
        for r in 0..<4 {
            for c in 0..<4 {
                if board[r][c] == 2048 {
                    win = true
                    return
                }
            }
        }
        
        // Check game over
        var hasMove = false
        for r in 0..<4 {
            for c in 0..<4 {
                if board[r][c] == 0 {
                    hasMove = true
                    break
                }
                if c + 1 < 4 && board[r][c] == board[r][c + 1] {
                    hasMove = true
                    break
                }
                if r + 1 < 4 && board[r][c] == board[r + 1][c] {
                    hasMove = true
                    break
                }
            }
        }
        gameOver = !hasMove
    }
}

struct Twenty48View: View {
    @StateObject private var game = Twenty48Game()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Score header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SCORE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(game.score)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.brown)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text("BEST")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(UserDefaults.standard.integer(forKey: "2048_highscore"))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Chaos mode toggle
                Toggle(isOn: $game.chaosMode) {
                    HStack {
                        Image(systemName: "hurricane")
                            .foregroundColor(.orange)
                        Text("Chaos Mode")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .padding(.horizontal, 20)
                
                if game.chaosMode {
                    Text("Board rotates every 10 moves! 🔄")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 20)
                }
                
                // Game board
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let cellSize = size / 4
                    
                    VStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { col in
                                    tileView(value: game.board[row][col], size: cellSize)
                                }
                            }
                        }
                    }
                    .frame(width: size, height: size)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 20)
                
                // Swipe gestures
                HStack(spacing: 20) {
                    ForEach([(dx: 0, dy: -1, icon: "arrow.up", "Up"),
                             (dx: 0, dy: 1, icon: "arrow.down", "Down"),
                             (dx: -1, dy: 0, icon: "arrow.left", "Left"),
                             (dx: 1, dy: 0, icon: "arrow.right", "Right")], id: \.3) { dir in
                        Button {
                            withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                                game.move((dx: dir.dx, dy: dir.dy))
                            }
                        } label: {
                            Image(systemName: dir.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.brown)
                                .cornerRadius(14)
                        }
                    }
                }
                .padding(.bottom, 16)
                
                // New game button
                Button {
                    game.reset()
                } label: {
                    Label("New Game", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brown)
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("2048")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(
                Group {
                    if game.gameOver && !game.win {
                        gameOverlay(title: "Game Over", message: "Score: \(game.score)")
                    } else if game.win {
                        gameOverlay(title: "You Win! 🎉", message: "Reached 2048!")
                    }
                }
            )
            .onChange(of: game.score) { newScore in
                let highscore = UserDefaults.standard.integer(forKey: "2048_highscore")
                if newScore > highscore {
                    UserDefaults.standard.set(newScore, forKey: "2048_highscore")
                }
            }
        }
        .navigationViewStyle(.stack)
    }
    
    @ViewBuilder
    private func tileView(value: Int, size: CGFloat) -> some View {
        let color = tileColor(value)
        
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(width: size - 8, height: size - 8)
            
            if value > 0 {
                Text("\(value)")
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .foregroundColor(value > 4 ? .white : .black)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .scaleEffect(value > 0 ? 1.0 : 0.85)
        .animation(.spring(response: 0.18, dampingFraction: 0.65), value: value)
    }
    
    private func tileColor(_ value: Int) -> Color {
        switch value {
        case 0: return Color(.systemGray5)
        case 2: return Color(.systemGray4)
        case 4: return Color(.systemGray3)
        case 8: return .orange.opacity(0.7)
        case 16: return .orange.opacity(0.8)
        case 32: return .orange
        case 64: return .orange.opacity(1.2)
        case 128, 256: return .yellow
        case 512, 1024: return .yellow.opacity(0.8)
        default: return .green
        }
    }
    
    @ViewBuilder
    private func gameOverlay(title: String, message: String) -> some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text(title.contains("Win") ? "🏆" : "💀")
                    .font(.system(size: 56))
                Text(title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
                Button {
                    game.reset()
                } label: {
                    Label("Play Again", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.brown)
                        .cornerRadius(14)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        }
    }
}

#Preview {
    Twenty48View()
}
