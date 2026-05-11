package com.philipp.playbox

import kotlin.random.Random

object MinimaxAI {

    // ── Classic TTT ────────────────────────────────────────────

    fun bestMove(board: List<Player?>, player: Player): Int {
        var best = Int.MIN_VALUE
        var bestIndex = -1
        for (i in 0..8) {
            if (board[i] != null) continue
            val newBoard = board.toMutableList()
            newBoard[i] = player
            val score = minimax(newBoard, 0, false, player, player.opposite)
            if (score > best) {
                best = score
                bestIndex = i
            }
        }
        return if (bestIndex == -1) board.indices.first { board[it] == null } else bestIndex
    }

    private fun minimax(
        board: List<Player?>, depth: Int, isMaximising: Boolean,
        maxPlayer: Player, minPlayer: Player
    ): Int {
        val winner = WinChecker.checkWinner(board)
        if (winner != null) return if (winner.first == maxPlayer) 10 - depth else depth - 10
        if (WinChecker.isFull(board)) return 0

        if (isMaximising) {
            var best = Int.MIN_VALUE
            for (i in 0..8) {
                if (board[i] != null) continue
                val newBoard = board.toMutableList().also { it[i] = maxPlayer }
                best = maxOf(best, minimax(newBoard, depth + 1, false, maxPlayer, minPlayer))
            }
            return best
        } else {
            var best = Int.MAX_VALUE
            for (i in 0..8) {
                if (board[i] != null) continue
                val newBoard = board.toMutableList().also { it[i] = minPlayer }
                best = minOf(best, minimax(newBoard, depth + 1, true, maxPlayer, minPlayer))
            }
            return best
        }
    }

    // ── Wild TTT ───────────────────────────────────────────────

    fun bestWildMove(board: List<Player?>, botPlayer: Player): Pair<Int, Player> {
        var best = Int.MIN_VALUE
        var bestIndex = 0
        var bestPiece = Player.X

        for (i in 0..8) {
            if (board[i] != null) continue
            for (piece in listOf(Player.X, Player.O)) {
                val newBoard = board.toMutableList().also { it[i] = piece }
                val score = wildMinimax(newBoard, 1, false, botPlayer)
                if (score > best) {
                    best = score
                    bestIndex = i
                    bestPiece = piece
                }
            }
        }
        return bestIndex to bestPiece
    }

    private fun wildMinimax(
        board: List<Player?>, depth: Int, isBotTurn: Boolean, botPlayer: Player
    ): Int {
        if (WinChecker.checkWinner(board) != null) return if (isBotTurn) depth - 10 else 10 - depth
        if (WinChecker.isFull(board)) return 0
        if (depth > 7) return 0

        if (isBotTurn) {
            var best = Int.MIN_VALUE
            for (i in 0..8) {
                if (board[i] != null) continue
                for (piece in listOf(Player.X, Player.O)) {
                    val newBoard = board.toMutableList().also { it[i] = piece }
                    best = maxOf(best, wildMinimax(newBoard, depth + 1, false, botPlayer))
                }
            }
            return best
        } else {
            var best = Int.MAX_VALUE
            for (i in 0..8) {
                if (board[i] != null) continue
                for (piece in listOf(Player.X, Player.O)) {
                    val newBoard = board.toMutableList().also { it[i] = piece }
                    best = minOf(best, wildMinimax(newBoard, depth + 1, true, botPlayer))
                }
            }
            return best
        }
    }

    // ── Connect 4 ──────────────────────────────────────────────

    fun bestConnect4Move(board: List<List<Player?>>, player: Player): Int {
        var bestScore = Int.MIN_VALUE
        var bestCol = 0
        for (col in 0..6) {
            val row = c4DropRow(board, col) ?: continue
            val newBoard = board.map { it.toMutableList() }.toMutableList()
            newBoard[row][col] = player
            val score = c4Minimax(newBoard, 0, false, player, Int.MIN_VALUE, Int.MAX_VALUE)
            if (score > bestScore) {
                bestScore = score
                bestCol = col
            }
        }
        return bestCol
    }

    fun c4DropRow(board: List<List<Player?>>, col: Int): Int? {
        for (row in 5 downTo 0) {
            if (board[row][col] == null) return row
        }
        return null
    }

    private fun c4Minimax(
        board: List<List<Player?>>, depth: Int, isMaximising: Boolean,
        maxPlayer: Player, alpha: Int, beta: Int
    ): Int {
        val winner = WinChecker.c4CheckWinner(board)
        if (winner != null) return if (winner == maxPlayer) 20 - depth else depth - 20
        if (WinChecker.c4IsFull(board) || depth >= 6) return 0

        var a = alpha
        var b = beta

        if (isMaximising) {
            var best = Int.MIN_VALUE
            for (col in 0..6) {
                val row = c4DropRow(board, col) ?: continue
                val newBoard = board.map { it.toMutableList() }.toMutableList()
                newBoard[row][col] = maxPlayer
                best = maxOf(best, c4Minimax(newBoard, depth + 1, false, maxPlayer, a, b))
                a = maxOf(a, best)
                if (b <= a) break
            }
            return best
        } else {
            var best = Int.MAX_VALUE
            val minPlayer = maxPlayer.opposite
            for (col in 0..6) {
                val row = c4DropRow(board, col) ?: continue
                val newBoard = board.map { it.toMutableList() }.toMutableList()
                newBoard[row][col] = minPlayer
                best = minOf(best, c4Minimax(newBoard, depth + 1, true, maxPlayer, a, b))
                b = minOf(b, best)
                if (b <= a) break
            }
            return best
        }
    }

    // ── Random helpers ────────────────────────────────────────

    fun randomMove(board: List<Player?>): Int? {
        return board.indices.filter { board[it] == null }.randomOrNull()
    }

    fun randomWildMove(board: List<Player?>): Pair<Int, Player>? {
        val idx = randomMove(board) ?: return null
        return idx to if (Random.nextBoolean()) Player.X else Player.O
    }
}