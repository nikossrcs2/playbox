import SwiftUI

// MARK: - Player

enum Player: String, Equatable {
    case x = "X"
    case o = "O"

    var opposite: Player {
        self == .x ? .o : .x
    }

    var color: Color {
        self == .x ? .blue : .orange
    }
}

// MARK: - Game Mode

enum GameMode: String, CaseIterable, Identifiable {
    case vsHuman = "vs Friend"
    case vsBot = "vs Bot"
    case aiVsAi = "AI vs AI"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .vsHuman: return "person.2.fill"
        case .vsBot:   return "cpu.fill"
        case .aiVsAi:  return "brain.head.profile"
        }
    }

    var displayName: String {
        switch self {
        case .vsHuman: return String(localized: "Two Players")
        case .vsBot:   return String(localized: "vs Bot")
        case .aiVsAi:  return String(localized: "AI Battle")
        }
    }
}

// MARK: - Bot Difficulty

enum BotDifficulty: String, CaseIterable, Identifiable {
    case easy   = "Easy"
    case hard   = "Hard"
    case neural = "Neural AI"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .easy:   return "tortoise.fill"
        case .hard:   return "brain.filled.head.profile"
        case .neural: return "cpu.fill"
        }
    }
    var description: String {
        switch self {
        case .easy:   return String(localized: "Random moves")
        case .hard:   return String(localized: "Minimax AI")
        case .neural: return String(localized: "Trained neural net")
        }
    }
}

// MARK: - Game Category

enum GameCategory: String, CaseIterable, Identifiable, Hashable {
    case tictactoe = "Tic Tac Toe"
    case arcade    = "Arcade"
    case puzzles   = "Puzzles"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tictactoe: return "grid"
        case .arcade:    return "gamecontroller.fill"
        case .puzzles:   return "brain.head.profile"
        }
    }

    var games: [GameType] {
        switch self {
        case .tictactoe: return [.classic, .superTTT, .notakto, .wild, .connect4]
        case .arcade:    return [.snake, .solitaire, .brickBreaker, .minesweeper, .twenty48, .memoryMatch, .stack, .aimTrainer, .flappyBird, .tetris, .blackjack]
        case .puzzles:   return [.wordle, .checkers, .chess]
        }
    }
}

// MARK: - Game Type

enum GameType: String, CaseIterable, Identifiable, Hashable {
    case classic      = "Classic"
    case superTTT     = "Super"
    case notakto      = "Notakto"
    case wild         = "Wild"
    case connect4     = "Connect 4"
    case snake        = "Snake"
    case solitaire    = "Solitaire"
    case brickBreaker = "Brick Breaker"
    case minesweeper  = "Minesweeper"
    case twenty48     = "2048"
    case wordle       = "Wordle"
    case checkers     = "Checkers"
    case chess        = "Chess"
    // New games
    case memoryMatch  = "Memory Match"
    case stack        = "Stack"
    case aimTrainer   = "Aim Trainer"
    case flappyBird   = "Flappy Bird"
    case tetris       = "Tetris"
    case blackjack    = "Blackjack"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:      return String(localized: "Classic")
        case .superTTT:     return String(localized: "Super TTT")
        case .notakto:      return String(localized: "Notakto")
        case .wild:         return String(localized: "Wild TTT")
        case .connect4:     return String(localized: "Connect 4")
        case .snake:        return String(localized: "Snake")
        case .solitaire:    return String(localized: "Solitaire")
        case .brickBreaker: return String(localized: "Brick Breaker")
        case .minesweeper:  return String(localized: "Minesweeper")
        case .twenty48:     return String(localized: "2048")
        case .wordle:       return String(localized: "Wordle")
        case .checkers:     return String(localized: "Checkers")
        case .chess:        return String(localized: "Chess")
        case .memoryMatch:  return String(localized: "Memory Match")
        case .stack:        return String(localized: "Stack")
        case .aimTrainer:   return String(localized: "Aim Trainer")
        case .flappyBird:   return String(localized: "Flappy Bird")
        case .tetris:       return String(localized: "Tetris")
        case .blackjack:    return String(localized: "Blackjack")
        }
    }

    var subtitle: String {
        switch self {
        case .classic:      return String(localized: "The original 3×3 game")
        case .superTTT:     return String(localized: "9 boards inside a board")
        case .notakto:      return String(localized: "Misère – avoid 3-in-a-row!")
        case .wild:         return String(localized: "Choose X or O each turn")
        case .connect4:     return String(localized: "Connect 4 in a row to win")
        case .snake:        return String(localized: "Eat, grow, don't crash")
        case .solitaire:    return String(localized: "Classic Klondike patience")
        case .brickBreaker: return String(localized: "Break bricks with a paddle")
        case .minesweeper:  return String(localized: "Flag mines, clear the field")
        case .twenty48:     return String(localized: "Merge tiles to reach 2048")
        case .wordle:       return String(localized: "Guess the 5-letter word")
        case .checkers:     return String(localized: "Capture all opponent pieces")
        case .chess:        return String(localized: "Strategic board game")
        case .memoryMatch:  return String(localized: "Find all matching pairs")
        case .stack:        return String(localized: "Stack the blocks perfectly")
        case .aimTrainer:   return String(localized: "Test your reaction speed")
        case .flappyBird:   return String(localized: "Tap to keep flying")
        case .tetris:       return String(localized: "Stack blocks, clear lines")
        case .blackjack:    return String(localized: "Guess cards to reach 21")
        }
    }

    var icon: String {
        switch self {
        case .classic:      return "grid"
        case .superTTT:     return "square.grid.3x3.fill"
        case .notakto:      return "xmark.square"
        case .wild:         return "shuffle"
        case .connect4:     return "circle.grid.3x3.fill"
        case .snake:        return "arrow.triangle.swap"
        case .solitaire:    return "suit.spade.fill"
        case .brickBreaker: return "square.stack.fill"
        case .minesweeper:  return "flag.fill"
        case .twenty48:     return "number.square.fill"
        case .wordle:       return "textformat.abc"
        case .checkers:     return "circle.dotted.circle"
        case .chess:        return "crown.fill"
        case .memoryMatch:  return "rectangle.on.rectangle"
        case .stack:        return "square.3.layers.3d"
        case .aimTrainer:   return "target"
        case .flappyBird:   return "bird.fill"
        case .tetris:       return "square.3.layers.3d.down.left"
        case .blackjack:    return "suit.spade.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .classic:      return .blue
        case .superTTT:     return .purple
        case .notakto:      return .red
        case .wild:         return .green
        case .connect4:     return .yellow
        case .snake:        return .mint
        case .solitaire:    return .indigo
        case .brickBreaker: return .orange
        case .minesweeper:  return .gray
        case .twenty48:     return .brown
        case .wordle:       return .green
        case .checkers:     return .red
        case .chess:        return .blue
        case .memoryMatch:  return .pink
        case .stack:        return .cyan
        case .aimTrainer:   return .orange
        case .flappyBird:   return .yellow
        case .tetris:       return .cyan
        case .blackjack:    return .red
        }
    }

    /// Whether this game uses the multiplayer setup screen
    var needsSetup: Bool {
        switch self {
        case .classic, .superTTT, .notakto, .wild, .connect4, .checkers, .chess:
            return true
        default:
            return false
        }
    }

    /// Whether this game has a Neural AI trained model available
    var supportsNeuralAI: Bool {
        switch self {
        case .classic, .wild, .connect4, .notakto, .superTTT:
            return true
        default:
            return false
        }
    }
}

// MARK: - Game Result

enum GameResult: Equatable {
    case ongoing
    case win(Player, [Int])   // winner + winning indices
    case draw
}

// MARK: - Win Check Helpers

struct WinChecker {
    static let lines: [[Int]] = [
        [0,1,2],[3,4,5],[6,7,8],
        [0,3,6],[1,4,7],[2,5,8],
        [0,4,8],[2,4,6]
    ]

    static func checkWinner(board: [Player?]) -> (Player, [Int])? {
        for line in lines {
            let vals = line.map { board[$0] }
            if let first = vals[0], vals.allSatisfy({ $0 == first }) {
                return (first, line)
            }
        }
        return nil
    }

    static func isFull(board: [Player?]) -> Bool { board.allSatisfy { $0 != nil } }

    static func result(board: [Player?]) -> GameResult {
        if let (winner, indices) = checkWinner(board: board) { return .win(winner, indices) }
        if isFull(board: board) { return .draw }
        return .ongoing
    }

    // Connect 4
    static func c4CheckWinner(board: [[Player?]]) -> Player? {
        let rows = 6, cols = 7
        let dirs = [(0,1),(1,0),(1,1),(1,-1)]
        for r in 0..<rows {
            for c in 0..<cols {
                guard let p = board[r][c] else { continue }
                for (dr, dc) in dirs {
                    var count = 0
                    for k in 0..<4 {
                        let nr = r + k * dr, nc = c + k * dc
                        guard nr >= 0, nr < rows, nc >= 0, nc < cols else { break }
                        if board[nr][nc] == p { count += 1 } else { break }
                    }
                    if count == 4 { return p }
                }
            }
        }
        return nil
    }

    static func c4IsFull(board: [[Player?]]) -> Bool {
        board[0].allSatisfy { $0 != nil }
    }
}
