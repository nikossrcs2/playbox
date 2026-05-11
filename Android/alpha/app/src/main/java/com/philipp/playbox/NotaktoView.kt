package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.Canvas
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.delay

class NotaktoViewModel : androidx.lifecycle.ViewModel() {
    var board by mutableStateOf(List(9) { null as Player? })
    var currentPlayer by mutableStateOf(Player.X)
    var result by mutableStateOf<GameResult>(GameResult.Ongoing)
    var isThinking by mutableStateOf(false)

    fun place(index: Int) {
        if (board[index] != null || result != GameResult.Ongoing) return
        val newBoard = board.toMutableList()
        newBoard[index] = Player.X // In Notakto, all pieces are the same (X)
        board = newBoard
        
        // In Notakto, the player who makes 3-in-a-row LOSES.
        val winnerPair = WinChecker.checkWinner(board)
        if (winnerPair != null) {
            // currentPlayer just lost. So the winner is the OTHER player.
            // But since Notakto is often played with neutral pieces, we just say "Opponent Wins"
            result = GameResult.Win(currentPlayer.opposite, winnerPair.second)
        } else if (WinChecker.isFull(board)) {
            result = GameResult.Draw
        } else {
            currentPlayer = currentPlayer.opposite
        }
    }

    fun reset() {
        board = List(9) { null }
        currentPlayer = Player.X
        result = GameResult.Ongoing
        isThinking = false
    }
}

@Composable
fun NotaktoView(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.HARD,
    onBack: () -> Unit = {}
) {
    val context = LocalContext.current
    val vm: NotaktoViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI
    val botPlayer = Player.O
    
    val neuralModel = remember { NeuralAIStore.getInstance(context).modelFor(GameType.NOTAKTO) }

    // Bot logic
    LaunchedEffect(vm.board, vm.currentPlayer, vm.result) {
        if (vm.result != GameResult.Ongoing || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && vm.currentPlayer == botPlayer)
        if (!aiTurn) return@LaunchedEffect

        vm.isThinking = true
        delay(600)

        val move = when (difficulty) {
            BotDifficulty.EASY -> MinimaxAI.randomMove(vm.board) ?: 0
            BotDifficulty.HARD -> MinimaxAI.bestMove(vm.board, vm.currentPlayer) // Minimax needs to be aware of Notakto rules
            BotDifficulty.NEURAL -> neuralModel.pickTTTMove(vm.board, vm.currentPlayer) // Simplified
        }

        vm.place(move)
        vm.isThinking = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Status Bar
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
            PlayerChip(Player.X, vm.currentPlayer, vm.result, isBot, isAiVsAi, botPlayer)
            NotaktoStatusLabel(vm.currentPlayer, vm.result, vm.isThinking)
            PlayerChip(Player.O, vm.currentPlayer, vm.result, isBot, isAiVsAi, botPlayer)
        }

        Spacer(modifier = Modifier.weight(1f))
        
        Text(
            "Avoid making 3-in-a-row!",
            modifier = Modifier.fillMaxWidth(),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            color = Color.Gray,
            fontSize = 12.sp
        )

        // Board
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(20.dp)
        ) {
            BoardView(
                board = vm.board,
                result = vm.result,
                canTap = vm.result == GameResult.Ongoing && !vm.isThinking &&
                        !isAiVsAi && !(isBot && vm.currentPlayer == botPlayer),
                onTap = { index -> vm.place(index) }
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        // New Game Button
        Button(
            onClick = { vm.reset() },
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
                .height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Red),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun NotaktoStatusLabel(currentPlayer: Player, result: GameResult, isThinking: Boolean) {
    when (result) {
        is GameResult.Ongoing -> {
            if (isThinking) {
                Text("Thinking...", fontSize = 13.sp, color = Color.Gray)
            } else {
                Text("${currentPlayer.name}'s turn", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = currentPlayer.color)
            }
        }
        is GameResult.Win -> {
            // result.player is the winner (the one who didn't make the 3-in-a-row)
            Text("${result.player.name} wins! 🎉", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = result.player.color)
        }
        is GameResult.Draw -> {
            Text("It's a draw!", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.Gray)
        }
    }
}
