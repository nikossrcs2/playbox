package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
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

import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.delay

class Connect4ViewModel : ViewModel() {
    companion object {
        const val ROWS = 6
        const val COLS = 7
    }

    var board by mutableStateOf(List(ROWS) { List(COLS) { null as Player? } })
    var currentPlayer by mutableStateOf(Player.X)
    var winner by mutableStateOf<Player?>(null)
    var isDraw by mutableStateOf(false)
    var isThinking by mutableStateOf(false)

    init { reset() }

    fun reset() {
        board = List(ROWS) { List(COLS) { null } }
        currentPlayer = Player.X
        winner = null
        isDraw = false
        isThinking = false
    }

    fun dropDisc(col: Int): Boolean {
        if (winner != null || isDraw || isThinking) return false
        for (row in (ROWS - 1) downTo 0) {
            if (board[row][col] == null) {
                board = board.toMutableList().also {
                    it[row] = it[row].toMutableList().also { rowList -> rowList[col] = currentPlayer }
                }
                winner = WinChecker.c4CheckWinner(board)
                if (winner == null && WinChecker.c4IsFull(board)) isDraw = true
                if (winner == null && !isDraw) currentPlayer = currentPlayer.opposite
                return true
            }
        }
        return false
    }
}

@Composable
fun Connect4View(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.HARD,
    onBack: () -> Unit = {}
) {
    val context = LocalContext.current
    val vm: Connect4ViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI
    val botPlayer = Player.O
    val neuralModel = remember { NeuralAIStore.getInstance(context).modelFor(GameType.CONNECT4) }

    // Bot logic
    LaunchedEffect(vm.currentPlayer, vm.winner, vm.isDraw) {
        if (vm.winner != null || vm.isDraw || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && vm.currentPlayer == botPlayer)
        if (!aiTurn) return@LaunchedEffect

        vm.isThinking = true
        delay(800)

        val move = when (difficulty) {
            BotDifficulty.EASY -> (0 until Connect4ViewModel.COLS).filter { vm.board[0][it] == null }.randomOrNull() ?: 0
            BotDifficulty.HARD -> MinimaxAI.bestConnect4Move(vm.board, vm.currentPlayer)
            BotDifficulty.NEURAL -> neuralModel.pickC4Move(vm.board, vm.currentPlayer)
        }

        vm.dropDisc(move)
        vm.isThinking = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Text("←", fontSize = 20.sp, color = MaterialTheme.colorScheme.onBackground)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                if (vm.winner != null) {
                    Text("${vm.winner!!.name} wins! 🎉", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = vm.winner!!.color)
                } else if (vm.isDraw) {
                    Text("Draw!", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.Gray)
                } else if (vm.isThinking) {
                    Text("Thinking...", fontSize = 14.sp, color = Color.Gray)
                } else {
                    Text("${vm.currentPlayer.name}'s turn", fontSize = 16.sp, color = vm.currentPlayer.color)
                }
            }
            Button(onClick = { vm.reset() }) { Text("↻ New") }
        }

        // Board
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF1565C0))
                .padding(8.dp)
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                for (r in 0 until Connect4ViewModel.ROWS) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        for (c in 0 until Connect4ViewModel.COLS) {
                            val canDrop = vm.winner == null && !vm.isDraw && !vm.isThinking &&
                                    !(isBot && vm.currentPlayer == botPlayer) && !isAiVsAi &&
                                    vm.board[0][c] == null

                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .aspectRatio(1f)
                                    .clip(CircleShape)
                                    .background(Color.White)
                                    .clickable(enabled = canDrop) { vm.dropDisc(c) },
                                contentAlignment = Alignment.Center
                            ) {
                                vm.board[r][c]?.let { player ->
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize(0.85f)
                                            .clip(CircleShape)
                                            .background(player.color)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Controls hint
        Text(
            "Tap column to drop disc",
            fontSize = 12.sp,
            color = Color.Gray,
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}