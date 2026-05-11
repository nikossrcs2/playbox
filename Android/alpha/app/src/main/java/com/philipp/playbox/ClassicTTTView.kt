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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.Canvas
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.viewmodel.compose.viewModel

import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.delay

class ClassicTTTViewModel : androidx.lifecycle.ViewModel() {
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
        if (result == GameResult.Ongoing) currentPlayer = player.opposite
    }

    fun reset() {
        board = List(9) { null }
        currentPlayer = Player.X
        result = GameResult.Ongoing
        isThinking = false
    }
}

@Composable
fun ClassicTTTView(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.HARD,
    onBack: () -> Unit = {}
) {
    val context = LocalContext.current
    val vm: ClassicTTTViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI
    val botPlayer = Player.O
    
    val neuralModel = remember { NeuralAIStore.getInstance(context).modelFor(GameType.CLASSIC) }

    // Bot logic
    LaunchedEffect(vm.board, vm.currentPlayer, vm.result) {
        if (vm.result != GameResult.Ongoing || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && vm.currentPlayer == botPlayer)
        if (!aiTurn) return@LaunchedEffect

        vm.isThinking = true
        delay(600)

        val move = when (difficulty) {
            BotDifficulty.EASY -> MinimaxAI.randomMove(vm.board) ?: 0
            BotDifficulty.HARD -> MinimaxAI.bestMove(vm.board, vm.currentPlayer)
            BotDifficulty.NEURAL -> neuralModel.pickTTTMove(vm.board, vm.currentPlayer)
        }

        vm.place(move, vm.currentPlayer)
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
            StatusLabel(vm.currentPlayer, vm.result, vm.isThinking)
            PlayerChip(Player.O, vm.currentPlayer, vm.result, isBot, isAiVsAi, botPlayer)
        }

        Spacer(modifier = Modifier.weight(1f))

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
                onTap = { index -> vm.place(index, vm.currentPlayer) }
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
            colors = ButtonDefaults.buttonColors(containerColor = Color.Blue),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun PlayerChip(
    player: Player,
    currentPlayer: Player,
    result: GameResult,
    isBot: Boolean,
    isAiVsAi: Boolean,
    botPlayer: Player
) {
    val isActive = result == GameResult.Ongoing && currentPlayer == player
    val isWinner = result is GameResult.Win && (result as GameResult.Win).player == player

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(player.color.copy(alpha = if (isActive || isWinner) 0.15f else 0.05f))
                .then(if (isActive) Modifier.border(2.dp, player.color, CircleShape) else Modifier),
            contentAlignment = Alignment.Center
        ) {
            Text(
                player.name,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = player.color.copy(alpha = if (isActive || isWinner) 1f else 0.3f)
            )
        }
        Text(
            if (isAiVsAi) "AI ${player.name}"
            else if (isBot && player == botPlayer) "Bot"
            else "Player ${player.name}",
            fontSize = 10.sp,
            color = Color.Gray
        )
    }
}

@Composable
fun StatusLabel(currentPlayer: Player, result: GameResult, isThinking: Boolean) {
    when (result) {
        is GameResult.Ongoing -> {
            if (isThinking) {
                Text("Thinking...", fontSize = 13.sp, color = Color.Gray)
            } else {
                Text("${currentPlayer.name}'s turn", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = currentPlayer.color)
            }
        }
        is GameResult.Win -> {
            Text("${result.player.name} wins! 🎉", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = result.player.color)
        }
        is GameResult.Draw -> {
            Text("It's a draw!", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.Gray)
        }
    }
}

@Composable
fun BoardView(
    board: List<Player?>,
    result: GameResult,
    canTap: Boolean,
    onTap: (Int) -> Unit
) {
    val density = LocalDensity.current
    fun centerOf(index: Int, cell: androidx.compose.ui.unit.Dp): Offset {
        val col = index % 3
        val row = index / 3
        return with(density) {
            Offset(cell.toPx() * col + cell.toPx() / 2, cell.toPx() * row + cell.toPx() / 2)
        }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val size = minOf(maxWidth, maxHeight)
        val cellSize = size / 3

        // Grid lines
        Canvas(modifier = Modifier.fillMaxSize()) {
            val cell = size / 3
            for (i in 1..2) {
                drawLine(
                    color = androidx.compose.ui.graphics.Color.Gray.copy(alpha = 0.5f),
                    start = Offset(cell.toPx() * i, 0f),
                    end = Offset(cell.toPx() * i, size.toPx()),
                    strokeWidth = 2f
                )
                drawLine(
                    color = androidx.compose.ui.graphics.Color.Gray.copy(alpha = 0.5f),
                    start = Offset(0f, cell.toPx() * i),
                    end = Offset(size.toPx(), cell.toPx() * i),
                    strokeWidth = 2f
                )
            }

            // Win line
            if (result is GameResult.Win) {
                val indices = result.indices
                val start = centerOf(indices[0], cell)
                val end = centerOf(indices[2], cell)
                drawLine(
                    color = Color.Red.copy(alpha = 0.7f),
                    start = start,
                    end = end,
                    strokeWidth = 5f,
                    cap = StrokeCap.Round
                )
            }
        }

        // Cells
        for (index in 0..8) {
            val row = index / 3
            val col = index % 3
            Box(
                modifier = Modifier
                    .size(cellSize)
                    .offset(x = cellSize * col, y = cellSize * row)
                    .clickable(enabled = canTap && board[index] == null) { onTap(index) },
                contentAlignment = Alignment.Center
            ) {
                board[index]?.let { player ->
                    Text(
                        player.name,
                        fontSize = (cellSize.value * 0.5f).sp,
                        fontWeight = FontWeight.Bold,
                        color = player.color
                    )
                }
            }
        }
    }
}

