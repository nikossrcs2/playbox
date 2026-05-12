package com.philipp.playbox

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

enum class Player {
    X, O;

    val opposite: Player get() = if (this == X) O else X

    val color: Color get() = if (this == X) Color.Blue else Color(0xFFFF9800)
}

enum class GameMode(val displayName: String, val icon: ImageVector) {
    VS_HUMAN("Two Players", Icons.Default.Group),
    VS_BOT("vs Bot", Icons.Default.SmartToy),
    AI_VS_AI("AI Battle", Icons.Default.Psychology)
}

enum class BotDifficulty(val displayName: String, val icon: ImageVector, val description: String) {
    EASY("Easy", Icons.Default.ChildCare, "Random moves"),
    HARD("Hard", Icons.Default.PsychologyAlt, "Minimax AI"),
    NEURAL("Neural AI", Icons.Default.Memory, "Trained neural net")
}

enum class GameCategory(val displayName: String, val icon: ImageVector) {
    TICTACTOE("Tic Tac Toe", Icons.Default.GridView),
    ARCADE("Arcade", Icons.Default.SportsEsports),
    PUZZLES("Puzzles", Icons.Default.Extension)
}

enum class GameType(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
    val accentColor: Color,
    val needsSetup: Boolean,
    val category: GameCategory
) {
    CLASSIC("Classic", "The original 3×3 game", Icons.Default.Grid3x3, Color.Blue, true, GameCategory.TICTACTOE),
    SUPER_TTT("Super TTT", "9 boards inside a board", Icons.Default.Apps, Color(0xFF9C27B0), true, GameCategory.TICTACTOE),
    NOTAKTO("Notakto", "Misère – avoid 3-in-a-row!", Icons.Default.GridOff, Color.Red, true, GameCategory.TICTACTOE),
    WILD("Wild TTT", "Choose X or O each turn", Icons.Default.Shuffle, Color.Green, true, GameCategory.TICTACTOE),
    CONNECT4("Connect 4", "Connect 4 in a row to win", Icons.Default.TableChart, Color(0xFFFFEB3B), true, GameCategory.TICTACTOE),
    SNAKE("Snake", "Eat, grow, don't crash", Icons.Default.KeyboardDoubleArrowRight, Color(0xFF00BCD4), false, GameCategory.ARCADE),
    SOLITAIRE("Solitaire", "Classic Klondike patience", Icons.Default.Style, Color(0xFF3F51B5), false, GameCategory.ARCADE),
    BRICK_BREAKER("Brick Breaker", "Break bricks with a paddle", Icons.Default.Layers, Color(0xFFFF9800), false, GameCategory.ARCADE),
    MINESWEEPER("Minesweeper", "Flag mines, clear the field", Icons.Default.Flag, Color.Gray, false, GameCategory.ARCADE),
    TWENTY48("2048", "Merge tiles to reach 2048", Icons.Default.Filter4, Color(0xFF795548), false, GameCategory.ARCADE),
    WORDLE("Wordle", "Guess the 5-letter word", Icons.Default.Title, Color.Green, false, GameCategory.PUZZLES),
    CHECKERS("Checkers", "Capture all opponent pieces", Icons.Default.Lens, Color.Red, true, GameCategory.PUZZLES),
    CHESS("Chess", "Strategic board game", Icons.Default.EmojiEvents, Color.Blue, true, GameCategory.PUZZLES),
    MEMORY_MATCH("Memory Match", "Find all matching pairs", Icons.Default.ContentCopy, Color(0xFFE91E63), false, GameCategory.ARCADE),
    STACK("Stack", "Stack the blocks perfectly", Icons.Default.ViewStream, Color(0xFF00BCD4), false, GameCategory.ARCADE),
    AIM_TRAINER("Aim Trainer", "Test your reaction speed", Icons.Default.AdsClick, Color(0xFFFF9800), false, GameCategory.ARCADE),
    FLAPPY_BIRD("Flappy Bird", "Tap to keep flying", Icons.Default.Flight, Color(0xFFFFEB3B), false, GameCategory.ARCADE),
    TETRIS("Tetris", "Stack blocks, clear lines", Icons.Default.DashboardCustomize, Color(0xFF00BCD4), false, GameCategory.ARCADE),
    BLACKJACK("Blackjack", "Get as close to 21 as you can", Icons.Default.CreditCard, Color.Red, false, GameCategory.ARCADE);

    val supportsNeuralAI: Boolean get() = when (this) {
        CLASSIC, WILD, CONNECT4, NOTAKTO, SUPER_TTT -> true
        else -> false
    }
}

sealed class GameResult {
    object Ongoing : GameResult()
    data class Win(val player: Player, val indices: List<Int>) : GameResult()
    object Draw : GameResult()
}

object WinChecker {
    val lines = listOf(
        listOf(0,1,2), listOf(3,4,5), listOf(6,7,8),
        listOf(0,3,6), listOf(1,4,7), listOf(2,5,8),
        listOf(0,4,8), listOf(2,4,6)
    )

    fun checkWinner(board: List<Player?>): Pair<Player, List<Int>>? {
        for (line in lines) {
            val first = board[line[0]] ?: continue
            if (line.all { board[it] == first }) return first to line
        }
        return null
    }

    fun isFull(board: List<Player?>): Boolean = board.all { it != null }

    fun result(board: List<Player?>): GameResult {
        val winner = checkWinner(board)
        if (winner != null) return GameResult.Win(winner.first, winner.second)
        if (isFull(board)) return GameResult.Draw
        return GameResult.Ongoing
    }

    fun c4CheckWinner(board: List<List<Player?>>): Player? {
        val rows = 6
        val cols = 7
        val dirs = listOf(0 to 1, 1 to 0, 1 to 1, 1 to -1)
        for (r in 0 until rows) {
            for (c in 0 until cols) {
                val p = board[r][c] ?: continue
                for ((dr, dc) in dirs) {
                    var count = 0
                    for (k in 0..3) {
                        val nr = r + k * dr
                        val nc = c + k * dc
                        if (nr in 0 until rows && nc in 0 until cols && board[nr][nc] == p) count++
                        else break
                    }
                    if (count == 4) return p
                }
            }
        }
        return null
    }

    fun c4IsFull(board: List<List<Player?>>): Boolean = board[0].all { it != null }
}