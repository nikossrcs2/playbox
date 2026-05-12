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

data class CheckerPiece(val isRed: Boolean, val isKing: Boolean)

class CheckersViewModel : ViewModel() {
    var board by mutableStateOf(List(8) { MutableList<CheckerPiece?>(8) { null } })
    var currentPlayer by mutableStateOf(true) // true = red
    var winner by mutableStateOf<Boolean?>(null)
    var isThinking by mutableStateOf(false)
    var selectedPos by mutableStateOf<Pair<Int, Int>?>(null)

    init { setupBoard() }

    fun setupBoard() {
        board = List(8) { r ->
            MutableList(8) { c ->
                when {
                    r < 3 && (r + c) % 2 == 1 -> CheckerPiece(false, false) // black
                    r > 4 && (r + c) % 2 == 1 -> CheckerPiece(true, false) // red
                    else -> null
                }
            }
        }
        currentPlayer = true; winner = null; selectedPos = null
    }

    fun getValidMoves(from: Pair<Int, Int>): List<Pair<Int, Int>> {
        val (r, c) = from
        val piece = board[r][c] ?: return emptyList()
        val moves = mutableListOf<Pair<Int, Int>>()
        val dirs = if (piece.isKing) listOf(-1 to -1, -1 to 1, 1 to -1, 1 to 1)
        else if (piece.isRed) listOf(-1 to -1, -1 to 1)
        else listOf(1 to -1, 1 to 1)

        for ((dr, dc) in dirs) {
            val nr = r + dr; val nc = c + dc
            if (nr in 0..7 && nc in 0..7 && board[nr][nc] == null) moves.add(nr to nc)
            val jr = r + dr * 2; val jc = c + dc * 2
            if (jr in 0..7 && jc in 0..7 && board[jr][jc] == null) {
                val jumped = board[r + dr][c + dc]
                if (jumped != null && jumped.isRed != piece.isRed) moves.add(jr to jc)
            }
        }
        return moves
    }

    fun makeMove(to: Pair<Int, Int>): Boolean {
        val from = selectedPos ?: return false
        val piece = board[from.first][from.second] ?: return false
        if (!getValidMoves(from).contains(to)) return false

        board = board.map { it.toMutableList() }.toMutableList().also {
            it[from.first][from.second] = null
            val isKing = piece.isKing || (piece.isRed && to.first == 0) || (!piece.isRed && to.first == 7)
            it[to.first][to.second] = CheckerPiece(piece.isRed, isKing)

            // Jump capture
            if (kotlin.math.abs(to.first - from.first) == 2) {
                val mr = (from.first + to.first) / 2; val mc = (from.second + to.second) / 2
                it[mr][mc] = null
            }
        }

        // Check winner
        val hasRed = board.any { row -> row.any { it?.isRed == true } }
        val hasBlack = board.any { row -> row.any { it?.isRed == false } }
        if (!hasRed) winner = false
        else if (!hasBlack) winner = true
        else currentPlayer = !currentPlayer

        selectedPos = null
        return true
    }

    fun getAIMove(): Pair<Pair<Int, Int>, Pair<Int, Int>>? {
        val moves = mutableListOf<Pair<Pair<Int, Int>, Pair<Int, Int>>>()
        for (r in 0..7) for (c in 0..7) {
            if (board[r][c]?.isRed == !currentPlayer) {
                getValidMoves(r to c).forEach { moves.add((r to c) to it) }
            }
        }
        return moves.randomOrNull()
    }

    fun selectPiece(pos: Pair<Int, Int>) {
        val piece = board[pos.first][pos.second]
        if (piece != null && piece.isRed == currentPlayer) selectedPos = pos
    }
}

@Composable
fun CheckersView(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.EASY,
    onBack: () -> Unit = {}
) {
    val vm: CheckersViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI

    // Bot AI
    LaunchedEffect(vm.currentPlayer, vm.winner) {
        if (vm.winner != null || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && !vm.currentPlayer) // bot is black (false)
        if (!aiTurn) return@LaunchedEffect

        vm.isThinking = true
        delay(500)
        vm.getAIMove()?.let { (from, to) ->
            vm.selectedPos = from
            vm.makeMove(to)
        }
        vm.isThinking = false

        if (isAiVsAi && vm.winner == null) {
            // Chain next AI move via recomposition
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
            }
            if (vm.winner != null) {
                Text("${if (vm.winner!!) "Red" else "Black"} wins! 🎉", fontSize = 16.sp, fontWeight = FontWeight.Bold,
                    color = if (vm.winner!!) Color.Red else Color.Black)
            } else if (vm.isThinking) {
                Text("Thinking...", color = Color.Gray)
            } else {
                Text("${if (vm.currentPlayer) "Red" else "Black"}'s turn", fontSize = 16.sp,
                    color = if (vm.currentPlayer) Color.Red else MaterialTheme.colorScheme.onBackground)
            }
            IconButton(onClick = { vm.setupBoard() }) {
                Icon(Icons.Default.Refresh, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
            }
        }

        // Board
        Box(modifier = Modifier.fillMaxWidth().aspectRatio(1f).padding(16.dp)) {
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val cellSize = maxWidth / 8
                Column {
                    for (r in 0..7) {
                        Row {
                            for (c in 0..7) {
                                val isDark = (r + c) % 2 == 1
                                val piece = vm.board[r][c]
                                val isSelected = vm.selectedPos == (r to c)

                                Box(
                                    modifier = Modifier
                                        .size(cellSize)
                                        .background(if (isDark) Color(0xFF8B4513) else Color(0xFFF5DEB3))
                                        .clickable {
                                            if (vm.selectedPos != null) vm.makeMove(r to c)
                                            else vm.selectPiece(r to c)
                                        },
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (isSelected) {
                                        Box(modifier = Modifier.fillMaxSize().border(3.dp, Color.Blue))
                                    }
                                    piece?.let {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxSize(0.7f)
                                                .clip(CircleShape)
                                                .background(if (it.isRed) Color.Red else Color.Black)
                                                .then(if (it.isKing) Modifier.border(2.dp, Color.Yellow, CircleShape) else Modifier),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            if (it.isKing) Text("👑", fontSize = (cellSize.value * 0.3f).sp)
                                        }
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
            colors = ButtonDefaults.buttonColors(containerColor = Color.Red),
            shape = RoundedCornerShape(14.dp)
        ) { Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold) }

        Spacer(modifier = Modifier.height(24.dp))
    }
}