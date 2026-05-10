//
//  Brick.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI
internal import Combine

private struct Brick: Identifiable {
    let id = UUID()
    var x: Int
    var y: Int
    var isAlive: Bool = true
    var hitsToBreak: Int = 1
    var color: Color
    
    init(x: Int, y: Int, hits: Int = 1) {
        self.x = x
        self.y = y
        self.hitsToBreak = hits
        self.color = hits == 1 ? .red : (hits == 2 ? .orange : .yellow)
    }
}

private class BrickBreakerGame: ObservableObject {
    @Published var paddleX: CGFloat = 0.5
    @Published var ballX: CGFloat = 0.5
    @Published var ballY: CGFloat = 0.85
    @Published var ballDX: CGFloat = 0.008
    @Published var ballDY: CGFloat = -0.012
    @Published var score: Int = 0
    @Published var lives: Int = 3
    @Published var isGameOver: Bool = false
    @Published var isWin: Bool = false
    @Published var bricks: [Brick] = []
    
    private var timer: Timer?
    private let brickRows = 5
    private let brickCols = 8
    private let paddleWidth: CGFloat = 0.2
    private let ballSize: CGFloat = 0.02
    
    init() {
        setupBricks()
    }
    
    func setupBricks() {
        bricks = []
        for row in 0..<brickRows {
            for col in 0..<brickCols {
                let hits = row < 2 ? 1 : (row < 4 ? 2 : 3)
                bricks.append(Brick(x: col, y: row, hits: hits))
            }
        }
    }
    
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.update()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        stop()
        paddleX = 0.5
        ballX = 0.5
        ballY = 0.85
        ballDX = 0.008
        ballDY = -0.012
        score = 0
        lives = 3
        isGameOver = false
        isWin = false
        setupBricks()
        start()
    }
    
    func movePaddle(to x: CGFloat) {
        // Centre the paddle on the finger, clamped so it never goes off-screen
        let half = paddleWidth / 2
        paddleX = min(max(x - half, 0.0), 1.0 - paddleWidth)
    }
    
    private func update() {
        guard !isGameOver && !isWin else { return }
        
        // Move ball
        ballX += ballDX
        ballY += ballDY
        
        // Wall collisions
        if ballX <= 0 || ballX >= 1 {
            ballDX = -ballDX
            ballX = min(max(ballX, 0), 1)
        }
        
        if ballY <= 0 {
            ballDY = -ballDY
        }
        
        // Paddle collision
        if ballY + ballSize >= 0.98 && ballY - ballSize <= 1.0 &&
           ballX + ballSize >= paddleX && ballX - ballSize <= paddleX + paddleWidth {
            let hitPos = (ballX - paddleX) / paddleWidth
            ballDX = (hitPos - 0.5) * 0.02
            ballDY = -abs(ballDY)
            ballY = 0.98 - ballSize
            
            // Add some randomness
            ballDX += CGFloat.random(in: -0.002...0.002)
            ballDX = min(max(ballDX, -0.02), 0.02)
        }
        
        // Bottom collision (loss)
        if ballY + ballSize >= 1.0 {
            lives -= 1
            if lives <= 0 {
                isGameOver = true
                stop()
            } else {
                // Reset ball position
                ballX = paddleX + paddleWidth / 2
                ballY = 0.85
                ballDX = 0.008
                ballDY = -0.012
            }
        }
        
        // Brick collisions
        for i in bricks.indices {
            var brick = bricks[i]
            guard brick.isAlive else { continue }
            
            let brickH = 0.05
            let brickX = CGFloat(brick.x) / CGFloat(brickCols)
            let brickY = CGFloat(brick.y) * brickH + 0.02
            let brickW = 1.0 / CGFloat(brickCols)
            
            if ballX + ballSize > brickX && ballX - ballSize < brickX + brickW &&
               ballY + ballSize > brickY && ballY - ballSize < brickY + brickH {
                
                brick.hitsToBreak -= 1
                if brick.hitsToBreak <= 0 {
                    bricks[i].isAlive = false
                    score += 10
                } else {
                    bricks[i] = brick
                    score += 5
                }
                
                // Bounce
                let overlapLeft = abs((ballX + ballSize) - brickX)
                let overlapRight = abs((ballX - ballSize) - (brickX + brickW))
                let overlapTop = abs((ballY + ballSize) - brickY)
                let overlapBottom = abs((ballY - ballSize) - (brickY + brickH))
                
                let minX = min(overlapLeft, overlapRight)
                let minY = min(overlapTop, overlapBottom)
                
                if minX < minY {
                    ballDX = -ballDX
                } else {
                    ballDY = -ballDY
                }
                break
            }
        }
        
        // Check win
        let allDead = bricks.allSatisfy { !$0.isAlive }
        if allDead {
            isWin = true
            stop()
        }
    }
    
    deinit {
        stop()
    }
}

struct BrickBreakerView: View {
    @StateObject private var game = BrickBreakerGame()
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Score bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCORE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(game.score)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<game.lives, id: \.self) { _ in
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Game board
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemGroupedBackground))
                        
                        // Bricks — use same normalized math as collision model
                        ForEach(game.bricks) { brick in
                            if brick.isAlive {
                                let brickCols = 8
                                let brickW = width / CGFloat(brickCols)
                                let brickH = height * 0.05
                                // Mirror exactly: CGFloat(y) * brickH + 0.02
                                let normX = CGFloat(brick.x) / CGFloat(brickCols)
                                let normY = CGFloat(brick.y) * 0.05 + 0.02
                                let brickX = normX * width
                                let brickY = normY * height
                                
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(brick.color)
                                    if brick.hitsToBreak > 1 {
                                        Text("\(brick.hitsToBreak)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: brickW - 2, height: brickH - 2)
                                .position(x: brickX + brickW / 2, y: brickY + brickH / 2)
                            }
                        }
                        
                        // Paddle
                        let paddleWidth = width * 0.2
                        let paddleX = game.paddleX * width
                        let paddleY = height * 0.98
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange)
                            .frame(width: paddleWidth, height: 10)
                            .position(x: paddleX + paddleWidth / 2, y: paddleY)
                        
                        // Ball
                        let ballSize = width * 0.02
                        let ballX = game.ballX * width
                        let ballY = game.ballY * height
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: ballSize, height: ballSize)
                            .position(x: ballX, y: ballY)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let x = value.location.x / width
                                game.movePaddle(to: x)
                            }
                    )
                }
                .aspectRatio(0.8, contentMode: .fit)
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Controls hint
                Text("Drag left/right to move paddle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
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
                        .background(Color.orange)
                        .cornerRadius(14)
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Brick Breaker")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                game.start()
            }
            .onDisappear {
                game.stop()
            }
            .overlay(
                Group {
                    if game.isGameOver {
                        gameOverlay(title: "Game Over", message: "Score: \(game.score)")
                    } else if game.isWin {
                        gameOverlay(title: "You Win! 🎉", message: "Perfect score: \(game.score)")
                    }
                }
            )
        }
        .navigationViewStyle(.stack)
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
                        .background(Color.orange)
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
    BrickBreakerView()
}
