//
//  MinimaxAI.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import Foundation

// MARK: - MinimaxAI
// All methods are pure / thread-safe — call from any queue.

struct MinimaxAI {

    // ─────────────────────────────────────────────
    // MARK: Classic TTT
    // ─────────────────────────────────────────────

    static func bestMove(board: [Player?], player: Player) -> Int {
        var best = -1000
        var bestIndex = -1
        for i in 0..<9 where board[i] == nil {
            var b = board
            b[i] = player
            let score = minimax(board: b, depth: 0, isMaximising: false,
                                maxPlayer: player, minPlayer: player.opposite)
            if score > best {
                best = score
                bestIndex = i
            }
        }
        return bestIndex == -1 ? (board.indices.first(where: { board[$0] == nil }) ?? 0) : bestIndex
    }

    private static func minimax(board: [Player?], depth: Int, isMaximising: Bool,
                                maxPlayer: Player, minPlayer: Player) -> Int {
        if let (winner, _) = WinChecker.checkWinner(board: board) {
            return winner == maxPlayer ? (10 - depth) : (depth - 10)
        }
        if WinChecker.isFull(board: board) { return 0 }

        if isMaximising {
            var best = -1000
            for i in 0..<9 where board[i] == nil {
                var b = board; b[i] = maxPlayer
                best = max(best, minimax(board: b, depth: depth + 1, isMaximising: false,
                                        maxPlayer: maxPlayer, minPlayer: minPlayer))
            }
            return best
        } else {
            var best = 1000
            for i in 0..<9 where board[i] == nil {
                var b = board; b[i] = minPlayer
                best = min(best, minimax(board: b, depth: depth + 1, isMaximising: true,
                                        maxPlayer: maxPlayer, minPlayer: minPlayer))
            }
            return best
        }
    }

    // ─────────────────────────────────────────────
    // MARK: Wild TTT
    // ─────────────────────────────────────────────

    static func bestWildMove(board: [Player?], botPlayer: Player) -> (Int, Player) {
        var best = -1000
        var bestIndex = 0
        var bestPiece = Player.x

        for i in 0..<9 where board[i] == nil {
            for piece in [Player.x, Player.o] {
                var b = board; b[i] = piece
                let score = wildMinimax(board: b, depth: 1, isBotTurn: false, botPlayer: botPlayer)
                if score > best {
                    best = score; bestIndex = i; bestPiece = piece
                }
            }
        }
        return (bestIndex, bestPiece)
    }

    private static func wildMinimax(board: [Player?], depth: Int, isBotTurn: Bool,
                                    botPlayer: Player) -> Int {
        if WinChecker.checkWinner(board: board) != nil {
            return isBotTurn ? (depth - 10) : (10 - depth)   // last mover won
        }
        if WinChecker.isFull(board: board) { return 0 }
        if depth > 7 { return 0 }

        if isBotTurn {
            var best = -1000
            for i in 0..<9 where board[i] == nil {
                for piece in [Player.x, Player.o] {
                    var b = board; b[i] = piece
                    best = max(best, wildMinimax(board: b, depth: depth + 1, isBotTurn: false, botPlayer: botPlayer))
                }
            }
            return best
        } else {
            var best = 1000
            for i in 0..<9 where board[i] == nil {
                for piece in [Player.x, Player.o] {
                    var b = board; b[i] = piece
                    best = min(best, wildMinimax(board: b, depth: depth + 1, isBotTurn: true, botPlayer: botPlayer))
                }
            }
            return best
        }
    }

    // ─────────────────────────────────────────────
    // MARK: Connect 4
    // ─────────────────────────────────────────────

    static let c4Rows = 6
    static let c4Cols = 7

    static func bestConnect4Move(board: [[Player?]], player: Player) -> Int {
        var bestScore = Int.min
        var bestCol = 0
        for col in 0..<c4Cols {
            guard let row = c4DropRow(board: board, col: col) else { continue }
            var b = board; b[row][col] = player
            let score = c4Minimax(board: b, depth: 0, isMaximising: false,
                                  maxPlayer: player, alpha: Int.min, beta: Int.max)
            if score > bestScore { bestScore = score; bestCol = col }
        }
        return bestCol
    }

    static func c4DropRow(board: [[Player?]], col: Int) -> Int? {
        for row in stride(from: c4Rows - 1, through: 0, by: -1) {
            if board[row][col] == nil { return row }
        }
        return nil
    }

    private static func c4Minimax(board: [[Player?]], depth: Int, isMaximising: Bool,
                                   maxPlayer: Player, alpha: Int, beta: Int) -> Int {
        if let winner = WinChecker.c4CheckWinner(board: board) {
            return winner == maxPlayer ? (20 - depth) : (depth - 20)
        }
        if WinChecker.c4IsFull(board: board) || depth >= 6 { return 0 }

        var alpha = alpha, beta = beta
        if isMaximising {
            var best = Int.min
            for col in 0..<c4Cols {
                guard let row = c4DropRow(board: board, col: col) else { continue }
                var b = board; b[row][col] = maxPlayer
                best = max(best, c4Minimax(board: b, depth: depth + 1, isMaximising: false,
                                           maxPlayer: maxPlayer, alpha: alpha, beta: beta))
                alpha = max(alpha, best)
                if beta <= alpha { break }
            }
            return best
        } else {
            var best = Int.max
            let minPlayer = maxPlayer.opposite
            for col in 0..<c4Cols {
                guard let row = c4DropRow(board: board, col: col) else { continue }
                var b = board; b[row][col] = minPlayer
                best = min(best, c4Minimax(board: b, depth: depth + 1, isMaximising: true,
                                           maxPlayer: maxPlayer, alpha: alpha, beta: beta))
                beta = min(beta, best)
                if beta <= alpha { break }
            }
            return best
        }
    }

    // ─────────────────────────────────────────────
    // MARK: Super TTT — proper global minimax
    // ─────────────────────────────────────────────
    // State passed around as value types so it's thread-safe.

    struct SuperState {
        var boards: [[Player?]]        // 9 mini-boards × 9 cells
        var boardResults: [GameResult] // result of each mini-board
        var activeBoard: Int?          // nil = free choice
        var currentPlayer: Player
    }

    /// Returns (boardIndex, cellIndex) for the best move.
    static func bestSuperMove(state: SuperState, depth: Int = 0) -> (Int, Int) {
        let validBds = superValidBoards(state: state)
        var bestScore = Int.min
        var bestMove = (validBds[0], 0)

        for bIdx in validBds {
            for cIdx in 0..<9 where state.boards[bIdx][cIdx] == nil {
                let next = superApply(state: state, board: bIdx, cell: cIdx)
                let score = superMinimax(state: next, depth: depth + 1,
                                         isMaximising: false, maxPlayer: state.currentPlayer,
                                         alpha: Int.min, beta: Int.max)
                if score > bestScore { bestScore = score; bestMove = (bIdx, cIdx) }
            }
        }
        return bestMove
    }

    private static func superMinimax(state: SuperState, depth: Int, isMaximising: Bool,
                                     maxPlayer: Player, alpha: Int, beta: Int) -> Int {
        // Terminal: global win/draw
        let globalBoards: [Player?] = state.boardResults.map {
            if case .win(let w, _) = $0 { return w }
            return nil
        }
        let globalRes = WinChecker.result(board: globalBoards)
        if case .win(let w, _) = globalRes {
            return w == maxPlayer ? (50 - depth) : (depth - 50)
        }
        if globalRes == .draw { return 0 }

        // Depth limit — evaluate heuristically
        if depth >= 6 { return superHeuristic(state: state, maxPlayer: maxPlayer) }

        let validBds = superValidBoards(state: state)
        if validBds.isEmpty { return 0 }

        var alpha = alpha, beta = beta

        if isMaximising {
            var best = Int.min
            outer: for bIdx in validBds {
                for cIdx in 0..<9 where state.boards[bIdx][cIdx] == nil {
                    let next = superApply(state: state, board: bIdx, cell: cIdx)
                    let score = superMinimax(state: next, depth: depth + 1, isMaximising: false,
                                             maxPlayer: maxPlayer, alpha: alpha, beta: beta)
                    best = max(best, score)
                    alpha = max(alpha, best)
                    if beta <= alpha { break outer }
                }
            }
            return best
        } else {
            var best = Int.max
            outer: for bIdx in validBds {
                for cIdx in 0..<9 where state.boards[bIdx][cIdx] == nil {
                    let next = superApply(state: state, board: bIdx, cell: cIdx)
                    let score = superMinimax(state: next, depth: depth + 1, isMaximising: true,
                                             maxPlayer: maxPlayer, alpha: alpha, beta: beta)
                    best = min(best, score)
                    beta = min(beta, best)
                    if beta <= alpha { break outer }
                }
            }
            return best
        }
    }

    private static func superApply(state: SuperState, board bIdx: Int, cell cIdx: Int) -> SuperState {
        var s = state
        s.boards[bIdx][cIdx] = s.currentPlayer
        let miniRes = WinChecker.result(board: s.boards[bIdx])
        if miniRes != .ongoing { s.boardResults[bIdx] = miniRes }
        s.activeBoard = (s.boardResults[cIdx] == .ongoing) ? cIdx : nil
        s.currentPlayer = s.currentPlayer.opposite
        return s
    }

    private static func superValidBoards(state: SuperState) -> [Int] {
        if let forced = state.activeBoard { return [forced] }
        return (0..<9).filter { state.boardResults[$0] == .ongoing }
    }

    // Heuristic: count mini-board wins and near-wins on the global board.
    private static func superHeuristic(state: SuperState, maxPlayer: Player) -> Int {
        var score = 0
        // Mini-board ownership
        for bIdx in 0..<9 {
            if case .win(let w, _) = state.boardResults[bIdx] {
                score += (w == maxPlayer) ? 10 : -10
            }
        }
        // Potential on global board
        let globalCells: [Player?] = state.boardResults.map {
            if case .win(let w, _) = $0 { return w }
            return nil
        }
        for line in WinChecker.lines {
            let vals = line.map { globalCells[$0] }
            let maxCount = vals.filter { $0 == maxPlayer }.count
            let minCount = vals.filter { $0 == maxPlayer.opposite }.count
            if minCount == 0 { score += maxCount * maxCount }
            if maxCount == 0 { score -= minCount * minCount }
        }
        return score
    }

    // ─────────────────────────────────────────────
    // MARK: Random helpers
    // ─────────────────────────────────────────────

    static func randomMove(board: [Player?]) -> Int? {
        board.indices.filter { board[$0] == nil }.randomElement()
    }

    static func randomWildMove(board: [Player?]) -> (Int, Player)? {
        guard let idx = randomMove(board: board) else { return nil }
        return (idx, Bool.random() ? Player.x : Player.o)
    }
}
