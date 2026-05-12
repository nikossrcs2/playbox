package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay

data class ChessPieces(val type: String, val isWhite: Boolean) {
    val symbol: String get() = when (type) {
        "king" -> if (isWhite) "♔" else "♚"
        "queen" -> if (isWhite) "♕" else "♛"
        "rook" -> if (isWhite) "♖" else "♜"
        "bishop" -> if (isWhite) "♗" else "♝"
        "knight" -> if (isWhite) "♘" else "♞"
        "pawn" -> if (isWhite) "♙" else "♟"
        else -> "?"
    }
}

class ChessViewModel : ViewModel() {
    var board by mutableStateOf(List(8) { MutableList<ChessPieces?>(8) { null } })
    var currentPlayer by mutableStateOf(true) // true = white
    var winner by mutableStateOf<Boolean?>(null)
    var isThinking by mutableStateOf(false)
    var selectedPos by mutableStateOf<Pair<Int, Int>?>(null)
    var checkWarning by mutableStateOf(false)

    init { setupBoard() }

    fun setupBoard() {
        val backRow = listOf("rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook")
        board = List(8) { r ->
            MutableList(8) { c ->
                when (r) {
                    0 -> ChessPieces(backRow[c], false)
                    1 -> ChessPieces("pawn", false)
                    6 -> ChessPieces("pawn", true)
                    7 -> ChessPieces(backRow[c], true)
                    else -> null
                }
            }
        }
        currentPlayer = true; winner = null; selectedPos = null; checkWarning = false
    }

    fun getValidMoves(from: Pair<Int, Int>): List<Pair<Int, Int>> {
        val (r, c) = from
        val piece = board[r][c] ?: return emptyList()
        if (piece.isWhite != currentPlayer) return emptyList()
        val moves = mutableListOf<Pair<Int, Int>>()

        when (piece.type) {
            "pawn" -> {
                val dir = if (piece.isWhite) -1 else 1
                val startRow = if (piece.isWhite) 6 else 1
                if (r + dir in 0..7 && board[r + dir][c] == null) {
                    moves.add(r + dir to c)
                    if (r == startRow && board[r + dir * 2][c] == null) moves.add(r + dir * 2 to c)
                }
                listOf(-1, 1).forEach { dc ->
                    val nr = r + dir; val nc = c + dc
                    if (nr in 0..7 && nc in 0..7 && board[nr][nc]?.isWhite != piece.isWhite && board[nr][nc] != null) {
                        moves.add(nr to nc)
                    }
                }
            }
            "knight" -> {
                listOf(-2 to -1, -2 to 1, -1 to -2, -1 to 2, 1 to -2, 1 to 2, 2 to -1, 2 to 1).forEach { (dr, dc) ->
                    val nr = r + dr; val nc = c + dc
                    if (nr in 0..7 && nc in 0..7 && board[nr][nc]?.isWhite != piece.isWhite) moves.add(nr to nc)
                }
            }
            "king" -> {
                for (dr in -1..1) for (dc in -1..1) {
                    if (dr == 0 && dc == 0) continue
                    val nr = r + dr; val nc = c + dc
                    if (nr in 0..7 && nc in 0..7 && board[nr][nc]?.isWhite != piece.isWhite) moves.add(nr to nc)
                }
            }
            "rook", "bishop", "queen" -> {
                val dirs = when (piece.type) {
                    "rook" -> listOf(-1 to 0, 1 to 0, 0 to -1, 0 to 1)
                    "bishop" -> listOf(-1 to -1, -1 to 1, 1 to -1, 1 to 1)
                    else -> listOf(-1 to -1, -1 to 0, -1 to 1, 0 to -1, 0 to 1, 1 to -1, 1 to 0, 1 to 1)
                }
                dirs.forEach { (dr, dc) ->
                    var nr = r + dr; var nc = c + dc
                    while (nr in 0..7 && nc in 0..7) {
                        if (board[nr][nc] == null) moves.add(nr to nc)
                        else {
                            if (board[nr][nc]!!.isWhite != piece.isWhite) moves.add(nr to nc)
                            break
                        }
                        nr += dr; nc += dc
                    }
                }
            }
        }
        return moves
    }

    fun makeMove(to: Pair<Int, Int>): Boolean {
        val from = selectedPos ?: return false
        val validMoves = getValidMoves(from)
        if (!validMoves.contains(to)) return false

        val newBoard = board.map { it.toMutableList() }.toMutableList()
        newBoard[to.first][to.second] = newBoard[from.first][from.second]
        newBoard[from.first][from.second] = null

        // Pawn promotion
        if (newBoard[to.first][to.second]?.type == "pawn" && (to.first == 0 || to.first == 7)) {
            newBoard[to.first][to.second] = ChessPieces("queen", newBoard[to.first][to.second]!!.isWhite)
        }
        
        board = newBoard

        currentPlayer = !currentPlayer
        selectedPos = null
        return true
    }

    fun getAIMove(): Pair<Pair<Int, Int>, Pair<Int, Int>>? {
        val moves = mutableListOf<Pair<Pair<Int, Int>, Pair<Int, Int>>>()
        for (r in 0..7) for (c in 0..7) {
            if (board[r][c]?.isWhite == currentPlayer) {
                getValidMoves(r to c).forEach { moves.add((r to c) to it) }
            }
        }
        return moves.randomOrNull()
    }
}

@Composable
fun ChessView(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.EASY,
    onBack: () -> Unit = {}
) {
    val vm: ChessViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI

    LaunchedEffect(vm.currentPlayer) {
        if (vm.winner != null || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && !vm.currentPlayer)
        if (!aiTurn) return@LaunchedEffect
        vm.isThinking = true; delay(500)
        vm.getAIMove()?.let { (from, to) -> vm.selectedPos = from; vm.makeMove(to) }
        vm.isThinking = false
    }

    Column(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
            }
            Text(
                if (vm.winner != null) "${if (vm.winner!!) "White" else "Black"} wins!"
                else if (vm.isThinking) "Thinking..."
                else "${if (vm.currentPlayer) "White" else "Black"}'s turn",
                fontSize = 16.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground
            )
            IconButton(onClick = { vm.setupBoard() }) {
                Icon(Icons.Default.Refresh, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
            }
        }

        Box(modifier = Modifier.fillMaxWidth().aspectRatio(1f).padding(16.dp)) {
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val cellSize = maxWidth / 8
                Column {
                    for (r in 0..7) {
                        Row {
                            for (c in 0..7) {
                                val isLight = (r + c) % 2 == 0
                                val piece = vm.board[r][c]
                                val isSelected = vm.selectedPos == (r to c)

                                Box(
                                    modifier = Modifier
                                        .size(cellSize)
                                        .background(if (isLight) Color(0xFFF0D9B5) else Color(0xFFB58863))
                                        .clickable {
                                            if (vm.selectedPos != null) vm.makeMove(r to c)
                                            else { vm.selectedPos = r to c }
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (isSelected) Box(modifier = Modifier.fillMaxSize().border(3.dp, Color(0xFF2196F3)))
                                    piece?.let {
                                        Text(it.symbol, fontSize = (cellSize.value * 0.6f).sp, color = if (it.isWhite) Color.White else Color.Black)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Button(
            onClick = { vm.setupBoard() },
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2196F3)),
            shape = RoundedCornerShape(14.dp)
        ) { Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold) }
        Spacer(modifier = Modifier.height(24.dp))
    }
}