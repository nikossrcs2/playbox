//
//  FlappyBirdGame.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


//
// FlappyBirdView.swift
// TTT Collection
//
// Created by Philipp on 09.05.26.
//

import SwiftUI
internal import Combine

// MARK: - Flappy Bird Model

private struct FlappyBirdGame {
    var birdY: CGFloat = 0
    var birdVelocity: CGFloat = 0
    var pipes: [Pipe] = []
    var score: Int = 0
    var isGameOver: Bool = false
    var isStarted: Bool = false
    
    struct Pipe: Identifiable {
        let id = UUID()
        var x: CGFloat
        let gapY: CGFloat
        var passed: Bool
    }
}

// MARK: - Flappy Bird ViewModel

private final class FlappyBirdViewModel: ObservableObject {
    @Published var game = FlappyBirdGame()
    @Published var highScore: Int = 0
    
    private var timer: Timer?
    private var gameLoop: Timer?
    private var frameCount = 0
    private let gravity: CGFloat = 0.4
    private let jumpStrength: CGFloat = -7.0
    private let pipeSpeed: CGFloat = 3.0
    private let pipeSpawnInterval = 90 // frames
    private let pipeWidth: CGFloat = 60
    private let pipeGap: CGFloat = 140
    private let birdSize: CGFloat = 40
    
    private var canvasHeight: CGFloat = 0
    private var canvasWidth: CGFloat = 0
    
    init() {
        loadHighScore()
    }
    
    func setCanvasSize(_ width: CGFloat, _ height: CGFloat) {
        let needsReset = canvasWidth == 0 || canvasHeight == 0
        canvasWidth = width
        canvasHeight = height
        // Only reset when we first receive a valid canvas size; never interrupt an active game
        if needsReset {
            resetGame()
        }
    }
    
    func resetGame() {
        gameLoop?.invalidate()
        timer?.invalidate()
        
        game = FlappyBirdGame()
        game.birdY = canvasHeight / 2
        game.birdVelocity = 0
        game.pipes = []
        game.score = 0
        game.isGameOver = false
        game.isStarted = false
        frameCount = 0
    }
    
    func startGame() {
        guard !game.isStarted && !game.isGameOver else { return }
        game.isStarted = true
        startGameLoop()
    }
    
    func jump() {
        if !game.isStarted {
            startGame()
            return
        }
        
        if game.isGameOver {
            resetGame()
            startGame()
            return
        }
        
        game.birdVelocity = jumpStrength
        // Add a little haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func startGameLoop() {
        let t = Timer(timeInterval: 1/60, repeats: true) { [weak self] _ in
            self?.updateGame()
        }
        // Use .common mode for better touch responsiveness
        RunLoop.main.add(t, forMode: .common)
        gameLoop = t
    }
    
    private func updateGame() {
        guard game.isStarted && !game.isGameOver else { return }
        
        // Update bird physics
        game.birdVelocity += gravity
        game.birdY += game.birdVelocity
        
        // Spawn pipes
        frameCount += 1
        if frameCount >= pipeSpawnInterval && canvasWidth > 0 {
            spawnPipe()
            frameCount = 0
        }
        
        // Update pipes positions
        for i in game.pipes.indices {
            game.pipes[i].x -= pipeSpeed
        }
        
        // Remove off-screen pipes
        game.pipes.removeAll { $0.x + pipeWidth < 0 }
        
        // Check for score (bird passing pipes)
        for i in game.pipes.indices {
            let pipe = game.pipes[i]
            let birdX = canvasWidth / 3 // Bird is at left 1/3 of screen
            
            if !pipe.passed && pipe.x + pipeWidth < birdX {
                game.pipes[i].passed = true
                game.score += 1
                
                // Haptic on score
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
        
        // Check collisions
        checkCollisions()
    }
    
    private func spawnPipe() {
        let minGapY: CGFloat = 100
        let maxGapY: CGFloat = canvasHeight - pipeGap - 100
        let gapY = CGFloat.random(in: minGapY...maxGapY)
        
        let pipe = FlappyBirdGame.Pipe(
            x: canvasWidth,
            gapY: gapY,
            passed: false
        )
        game.pipes.append(pipe)
    }
    
    private func checkCollisions() {
        let birdRect = CGRect(
            x: canvasWidth / 3 - birdSize / 2,
            y: game.birdY - birdSize / 2,
            width: birdSize,
            height: birdSize
        )
        
        // Ground and ceiling collision
        if game.birdY - birdSize / 2 <= 0 ||
           game.birdY + birdSize / 2 >= canvasHeight {
            gameOver()
            return
        }
        
        // Pipe collisions
        for pipe in game.pipes {
            let topPipeRect = CGRect(
                x: pipe.x,
                y: 0,
                width: pipeWidth,
                height: pipe.gapY
            )
            
            let bottomPipeRect = CGRect(
                x: pipe.x,
                y: pipe.gapY + pipeGap,
                width: pipeWidth,
                height: canvasHeight - (pipe.gapY + pipeGap)
            )
            
            if birdRect.intersects(topPipeRect) || birdRect.intersects(bottomPipeRect) {
                gameOver()
                return
            }
        }
    }
    
    private func gameOver() {
        game.isGameOver = true
        game.isStarted = false
        
        // Update high score
        if game.score > highScore {
            highScore = game.score
            saveHighScore()
            
            // Haptic for new high score
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        }
        
        gameLoop?.invalidate()
        gameLoop = nil
    }
    
    private func saveHighScore() {
        UserDefaults.standard.set(highScore, forKey: "flappyBirdHighScore")
    }
    
    private func loadHighScore() {
        highScore = UserDefaults.standard.integer(forKey: "flappyBirdHighScore")
    }
    
    deinit {
        gameLoop?.invalidate()
        timer?.invalidate()
    }
    
    // MARK: - Drawing helpers
    
    func getBirdRotation() -> Double {
        let rotation = min(max(Double(game.birdVelocity) * 3, -30), 90)
        return rotation
    }
    
    func getPipePosition(for pipe: FlappyBirdGame.Pipe, isTop: Bool) -> CGPoint {
        if isTop {
            return CGPoint(x: pipe.x, y: pipe.gapY)
        } else {
            return CGPoint(x: pipe.x, y: pipe.gapY + pipeGap)
        }
    }
    
    func getPipeHeight(isTop: Bool, gapY: CGFloat) -> CGFloat {
        if isTop {
            return gapY
        } else {
            return canvasHeight - (gapY + pipeGap)
        }
    }
}

// MARK: - Flappy Bird View

struct FlappyBirdView: View {
    @StateObject private var vm = FlappyBirdViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Sky gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.cyan.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Clouds decoration
            CloudView()
            
            VStack(spacing: 0) {
                // Header with back button
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                        Text("\(vm.highScore)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer()
                
                // Game Canvas
                GeometryReader { geo in
                    ZStack {
                        // Game area background
                        Color.clear
                            .onAppear {
                                vm.setCanvasSize(geo.size.width, geo.size.height)
                            }
                            .onChange(of: geo.size.width) { _ in
                                vm.setCanvasSize(geo.size.width, geo.size.height)
                            }
                            .onChange(of: geo.size.height) { _ in
                                vm.setCanvasSize(geo.size.width, geo.size.height)
                            }
                        
                        // Pipes
                        ForEach(vm.game.pipes) { pipe in
                            PipeView(
                                pipe: pipe,
                                width: 60,
                                gap: 140,
                                canvasHeight: geo.size.height
                            )
                        }
                        
                        // Bird
                        BirdView(
                            y: vm.game.birdY,
                            size: 40,
                            rotation: vm.getBirdRotation(),
                            canvasWidth: geo.size.width
                        )
                        
                        // Start overlay
                        if !vm.game.isStarted && !vm.game.isGameOver {
                            StartOverlay()
                        }
                        
                        // Game Over overlay
                        if vm.game.isGameOver {
                            GameOverOverlay(
                                score: vm.game.score,
                                highScore: vm.highScore
                            ) {
                                vm.resetGame()
                                vm.startGame()
                            }
                        }
                        
                        // Score display during game
                        if vm.game.isStarted && !vm.game.isGameOver {
                            Text("\(vm.game.score)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                                .position(x: geo.size.width / 2, y: 50)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.jump()
                    }
                }
                
                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Bird View

private struct BirdView: View {
    let y: CGFloat
    let size: CGFloat
    let rotation: Double
    let canvasWidth: CGFloat   // fix: was using UIScreen.main.bounds.width, wrong in split-screen

    var body: some View {
        Image(systemName: "bird.fill")
            .font(.system(size: size))
            .foregroundColor(.yellow)
            .shadow(color: .orange, radius: 4, x: 0, y: 2)
            .rotationEffect(.degrees(rotation))
            .position(x: canvasWidth / 3, y: y)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: y)
    }
}

// MARK: - Pipe View

private struct PipeView: View {
    let pipe: FlappyBirdGame.Pipe
    let width: CGFloat
    let gap: CGFloat
    let canvasHeight: CGFloat
    
    var body: some View {
        ZStack {
            // Top pipe
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: pipe.gapY)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.5), lineWidth: 2)
                )
                .position(x: pipe.x + width / 2, y: pipe.gapY / 2)
            
            // Pipe cap (top)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green)
                .frame(width: width + 10, height: 30)
                .position(x: pipe.x + width / 2, y: pipe.gapY - 15)
            
            // Bottom pipe
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: canvasHeight - (pipe.gapY + gap))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.5), lineWidth: 2)
                )
                .position(x: pipe.x + width / 2, y: pipe.gapY + gap + (canvasHeight - (pipe.gapY + gap)) / 2)
            
            // Pipe cap (bottom)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green)
                .frame(width: width + 10, height: 30)
                .position(x: pipe.x + width / 2, y: pipe.gapY + gap + 15)
        }
    }
}

// MARK: - Cloud Decoration

private struct CloudView: View {
    @State private var offset1: CGFloat = 0
    @State private var offset2: CGFloat = 0
    @State private var offset3: CGFloat = 0
    
    var body: some View {
        ZStack {
            CloudShape()
                .fill(Color.white.opacity(0.3))
                .frame(width: 120, height: 70)
                .position(x: offset1, y: 100)
            
            CloudShape()
                .fill(Color.white.opacity(0.25))
                .frame(width: 150, height: 80)
                .position(x: offset2, y: 200)
            
            CloudShape()
                .fill(Color.white.opacity(0.2))
                .frame(width: 100, height: 60)
                .position(x: offset3, y: 300)
        }
        .onAppear {
            let screenWidth = UIScreen.main.bounds.width
            offset1 = -50
            offset2 = screenWidth + 50
            offset3 = screenWidth / 2
            
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                offset1 = screenWidth + 50
            }
            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                offset2 = -50
            }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                offset3 = screenWidth + 50
            }
        }
    }
}

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: width * 0.2, y: height))
        path.addQuadCurve(to: CGPoint(x: width * 0.4, y: height * 0.6),
                         control: CGPoint(x: width * 0.1, y: height * 0.8))
        path.addQuadCurve(to: CGPoint(x: width * 0.6, y: height * 0.4),
                         control: CGPoint(x: width * 0.5, y: height * 0.5))
        path.addQuadCurve(to: CGPoint(x: width * 0.85, y: height * 0.55),
                         control: CGPoint(x: width * 0.75, y: height * 0.35))
        path.addQuadCurve(to: CGPoint(x: width * 0.9, y: height),
                         control: CGPoint(x: width, y: height * 0.7))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Overlay Views

private struct StartOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bird.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
                .shadow(radius: 4)
            
            Text("Flappy Bird")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(radius: 2)
            
            Text("Tap to Start")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            
            Text("Tap screen to fly\nAvoid the pipes")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .cornerRadius(30)
        .shadow(radius: 20)
    }
}

private struct GameOverOverlay: View {
    let score: Int
    let highScore: Int
    let onRestart: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Game Over")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Score:")
                        .font(.system(size: 18, weight: .medium))
                    Text("\(score)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.yellow)
                }
                
                if score == highScore && score > 0 {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("NEW HIGH SCORE!")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                } else if highScore > 0 {
                    HStack {
                        Text("Best:")
                            .font(.system(size: 16, weight: .medium))
                        Text("\(highScore)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.yellow)
                    }
                }
            }
            
            Button(action: onRestart) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Play Again")
                }
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(25)
            }
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .cornerRadius(30)
        .shadow(radius: 20)
    }
}

// MARK: - Preview

#Preview {
    FlappyBirdView()
}
