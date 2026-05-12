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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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

class WildTTTViewModel : androidx.lifecycle.ViewModel() {
    var board by mutableStateOf(List(9) { null as Player? })
    var currentPlayer by mutableStateOf(Player.X)
    var result by mutableStateOf<GameResult>(GameResult.Ongoing)
    var isThinking by mutableStateOf(false)

    fun place(index: Int, player: Player) {
        if (board[index] != null || result != GameResult.Ongoing) return
        val newBoard = board.toMutableList()
        newBoard[index] = player
        board = newBoard
        result = WinChecker.result(board)
        if (result == GameResult.Ongoing) currentPlayer = currentPlayer.opposite
    }

    fun reset() {
        board = List(9) { null }
        currentPlayer = Player.X
        result = GameResult.Ongoing
        isThinking = false
    }
}

@Composable
fun WildTTTView(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.HARD,
    onBack: () -> Unit = {}
) {
    val context = LocalContext.current
    val vm: WildTTTViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI
    val botPlayer = Player.O
    
    val neuralModel = remember { NeuralAIStore.getInstance(context).modelFor(GameType.WILD) }
    var selectedPlayer by remember { mutableStateOf(Player.X) }

    // Bot logic
    LaunchedEffect(vm.board, vm.currentPlayer, vm.result) {
        if (vm.result != GameResult.Ongoing || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && vm.currentPlayer == botPlayer)
        if (!aiTurn) return@LaunchedEffect

        vm.isThinking = true
        delay(600)

        val (move, piece) = when (difficulty) {
            BotDifficulty.EASY -> MinimaxAI.randomWildMove(vm.board) ?: (0 to Player.X)
            BotDifficulty.HARD -> MinimaxAI.bestWildMove(vm.board, vm.currentPlayer)
            BotDifficulty.NEURAL -> neuralModel.pickWildMove(vm.board, vm.currentPlayer)
        }

        vm.place(move, piece)
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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
            }
            PlayerChip(Player.X, vm.currentPlayer, vm.result, isBot, isAiVsAi, botPlayer)
            StatusLabel(vm.currentPlayer, vm.result, vm.isThinking)
            PlayerChip(Player.O, vm.currentPlayer, vm.result, isBot, isAiVsAi, botPlayer)
        }

        Spacer(modifier = Modifier.weight(1f))

        // Piece Selection (Only if it's human turn)
        val isHumanTurn = !vm.isThinking && !isAiVsAi && !(isBot && vm.currentPlayer == botPlayer)
        if (isHumanTurn && vm.result == GameResult.Ongoing) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 20.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Pick piece: ", color = MaterialTheme.colorScheme.onBackground)
                Spacer(modifier = Modifier.width(12.dp))
                PieceButton(Player.X, selectedPlayer == Player.X) { selectedPlayer = Player.X }
                Spacer(modifier = Modifier.width(12.dp))
                PieceButton(Player.O, selectedPlayer == Player.O) { selectedPlayer = Player.O }
            }
        }

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
                canTap = isHumanTurn && vm.result == GameResult.Ongoing,
                onTap = { index -> vm.place(index, selectedPlayer) }
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
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4CAF50)),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun PieceButton(player: Player, isSelected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .background(if (isSelected) player.color.copy(alpha = 0.2f) else Color.Transparent)
            .border(2.dp, if (isSelected) player.color else Color.Gray.copy(alpha = 0.3f), CircleShape)
            .clickable { onClick() },
        contentAlignment = Alignment.Center
    ) {
        Text(player.name, color = if (isSelected) player.color else Color.Gray, fontWeight = FontWeight.Bold)
    }
}
