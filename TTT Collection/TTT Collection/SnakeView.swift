import SwiftUI
internal import Combine

private struct Point: Equatable {
    var x: Int
    var y: Int
}

private enum Direction {
    case up, down, left, right

    var opposite: Direction {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}

private enum SnakeGameState {
    case waiting
    case playing
    case dead
}

private class SnakeGame: ObservableObject {
    static let columns = 20
    static let rows = 20

    @Published var snake: [Point] = []
    @Published var food: Point = Point(x: 0, y: 0)
    @Published var score: Int = 0
    @Published var highScore: Int = 0
    @Published var gameState: SnakeGameState = .waiting

    private var direction: Direction = .right
    private var nextDirection: Direction = .right
    private var timer: Timer?

    init() {
        loadHighScore()
        setupGame()
    }

    func setupGame() {
        let midX = Self.columns / 2
        let midY = Self.rows / 2
        snake = [
            Point(x: midX, y: midY),
            Point(x: midX - 1, y: midY),
            Point(x: midX - 2, y: midY)
        ]
        direction = .right
        nextDirection = .right
        score = 0
        spawnFood()
    }

    func start() {
        gameState = .playing
        scheduleTimer()
    }

    func restart() {
        timer?.invalidate()
        setupGame()
        gameState = .playing
        scheduleTimer()
    }

    func steer(_ dir: Direction) {
        guard dir != direction.opposite else { return }
        nextDirection = dir
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard gameState == .playing else { return }

        direction = nextDirection

        let head = snake[0]
        var newHead: Point
        switch direction {
        case .up:    newHead = Point(x: head.x, y: head.y - 1)
        case .down:  newHead = Point(x: head.x, y: head.y + 1)
        case .left:  newHead = Point(x: head.x - 1, y: head.y)
        case .right: newHead = Point(x: head.x + 1, y: head.y)
        }

        if newHead.x < 0 || newHead.x >= Self.columns || newHead.y < 0 || newHead.y >= Self.rows {
            die(); return
        }
        if snake.dropLast().contains(newHead) {
            die(); return
        }

        let atFood = newHead == food
        var newSnake = [newHead] + snake
        if !atFood { newSnake.removeLast() }

        snake = newSnake

        if atFood {
            score += 10
            if score > highScore {
                highScore = score
                saveHighScore()
            }
            spawnFood()
        }
    }

    private func die() {
        timer?.invalidate()
        gameState = .dead
    }

    private func spawnFood() {
        var candidate: Point
        repeat {
            candidate = Point(
                x: Int.random(in: 0..<Self.columns),
                y: Int.random(in: 0..<Self.rows)
            )
        } while snake.contains(candidate)
        food = candidate
    }

    private func loadHighScore() {
        highScore = UserDefaults.standard.integer(forKey: "snake_highscore")
    }

    private func saveHighScore() {
        UserDefaults.standard.set(highScore, forKey: "snake_highscore")
    }

    deinit {
        timer?.invalidate()
    }
}

struct SnakeView: View {
    @StateObject private var game = SnakeGame()
    @Environment(\.dismiss) private var dismiss

    private let accentColor = Color.mint

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                scoreBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                boardView
                    .padding(.horizontal, 16)

                Spacer()

                dpad
                    .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Snake")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(
                Group {
                    if game.gameState != .playing {
                        overlayView
                    }
                }
            )
        }
        .navigationViewStyle(.stack)
    }

    private var scoreBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(1)
                Text("\(game.score)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(1)
                Text("\(game.highScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var boardView: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cellSize = size / CGFloat(SnakeGame.columns)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))

                Canvas { context, canvasSize in
                    let cs = canvasSize.width / CGFloat(SnakeGame.columns)
                    for row in 0..<SnakeGame.rows {
                        for col in 0..<SnakeGame.columns {
                            let cx = CGFloat(col) * cs + cs / 2
                            let cy = CGFloat(row) * cs + cs / 2
                            let dot = CGRect(x: cx - 0.5, y: cy - 0.5, width: 1, height: 1)
                            context.fill(Path(ellipseIn: dot), with: .color(.gray.opacity(0.15)))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                foodCell(cellSize: cellSize)

                ForEach(Array(game.snake.enumerated()), id: \.offset) { idx, point in
                    snakeCell(point: point, index: idx, total: game.snake.count, cellSize: cellSize)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func snakeCell(point: Point, index: Int, total: Int, cellSize: CGFloat) -> some View {
        let isHead = index == 0
        let progress = Double(index) / Double(max(total - 1, 1))
        let color = isHead ? accentColor : accentColor.opacity(0.9 - progress * 0.5)
        let padding: CGFloat = isHead ? 1 : 2

        return RoundedRectangle(cornerRadius: isHead ? 6 : 4)
            .fill(color)
            .frame(width: cellSize - padding, height: cellSize - padding)
            .offset(
                x: CGFloat(point.x) * cellSize + padding / 2,
                y: CGFloat(point.y) * cellSize + padding / 2
            )
    }

    private func foodCell(cellSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.85))
                .frame(width: cellSize - 4, height: cellSize - 4)
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: cellSize * 0.25, height: cellSize * 0.25)
                .offset(x: -(cellSize * 0.1), y: -(cellSize * 0.1))
        }
        .offset(
            x: CGFloat(game.food.x) * cellSize + 2,
            y: CGFloat(game.food.y) * cellSize + 2
        )
    }

    private var dpad: some View {
        VStack(spacing: 4) {
            dpadButton(icon: "chevron.up", direction: .up)
            HStack(spacing: 4) {
                dpadButton(icon: "chevron.left", direction: .left)
                Color.clear.frame(width: 60, height: 60)
                dpadButton(icon: "chevron.right", direction: .right)
            }
            dpadButton(icon: "chevron.down", direction: .down)
        }
    }

    private func dpadButton(icon: String, direction: Direction) -> some View {
        Button {
            if game.gameState == .waiting { game.start() }
            game.steer(direction)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(accentColor)
                .frame(width: 60, height: 60)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
        }
        .buttonStyle(CardButtonStyle())
    }

    private var overlayView: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                if game.gameState == .waiting {
                    Text("🐍")
                        .font(.system(size: 56))
                    Text("Snake")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Tap a direction\nto start")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                } else {
                    Text("💀")
                        .font(.system(size: 56))
                    Text("Game Over")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Score: \(game.score)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(accentColor)
                    if game.score >= game.highScore && game.score > 0 {
                        Text("🎉 New High Score!")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.yellow)
                    }
                    Button {
                        game.restart()
                    } label: {
                        Label("Play Again", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(accentColor)
                            .cornerRadius(14)
                    }
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        }
    }
}

#Preview {
    SnakeView()
}
