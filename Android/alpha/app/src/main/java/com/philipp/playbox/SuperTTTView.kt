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

class SuperTTTViewModel : androidx.lifecycle.ViewModel() {
    var boards by mutableStateOf(List(9) { List(9) { null as Player? } })
    var boardResults by mutableStateOf(List(9) { GameResult.Ongoing as GameResult })
    var currentPlayer by mutableStateOf(Player.X)
    var activeBoardIndex by mutableStateOf<Int?>(null) // null means any board
    var overallResult by mutableStateOf<GameResult>(GameResult.Ongoing)
    var isThinking by mutableStateOf(false)

    fun place(boardIdx: Int, cellIdx: Int, player: Player) {
        if (overallResult != GameResult.Ongoing) return
        if (activeBoardIndex != null && boardIdx != activeBoardIndex) return
        if (boardResults[boardIdx] != GameResult.Ongoing) return
        if (boards[boardIdx][cellIdx] != null) return

        val newBoards = boards.map { it.toMutableList() }.toMutableList()
        newBoards[boardIdx][cellIdx] = player
        boards = newBoards

        // Check local board result
        val localRes = WinChecker.result(boards[boardIdx])
        if (localRes != GameResult.Ongoing) {
            val newBoardResults = boardResults.toMutableList()
            newBoardResults[boardIdx] = localRes
            boardResults = newBoardResults
            
            // Check overall game result
            val mainBoard = boardResults.map { 
                when(it) {
                    is GameResult.Win -> it.player
                    else -> null
                }
            }
            overallResult = WinChecker.result(mainBoard)
        }

        if (overallResult == GameResult.Ongoing) {
            // Determine next active board
            activeBoardIndex = if (boardResults[cellIdx] == GameResult.Ongoing) {
                cellIdx
            } else {
                null
            }
            currentPlayer = player.opposite
        }
    }

    fun reset() {
        boards = List(9) { List(9) { null } }
        boardResults = List(9) { GameResult.Ongoing }
        currentPlayer = Player.X
        activeBoardIndex = null
        overallResult = GameResult.Ongoing
        isThinking = false
    }
}

@Composable
fun SuperTTTView(
    mode: GameMode = GameMode.VS_HUMAN,
    difficulty: BotDifficulty = BotDifficulty.HARD,
    onBack: () -> Unit = {}
) {
    val context = LocalContext.current
    val vm: SuperTTTViewModel = viewModel()
    val isBot = mode == GameMode.VS_BOT
    val isAiVsAi = mode == GameMode.AI_VS_AI
    val botPlayer = Player.O
    
    // Bot logic (Simplified for Super TTT)
    LaunchedEffect(vm.boards, vm.currentPlayer, vm.overallResult) {
        if (vm.overallResult != GameResult.Ongoing || vm.isThinking) return@LaunchedEffect
        val aiTurn = isAiVsAi || (isBot && vm.currentPlayer == botPlayer)
        if (!aiTurn) return@LaunchedEffect

        vm.isThinking = true
        delay(600)

        // Simple Bot: Pick a valid move
        val possibleMoves = mutableListOf<Pair<Int, Int>>()
        for (b in 0..8) {
            if (vm.activeBoardIndex != null && b != vm.activeBoardIndex) continue
            if (vm.boardResults[b] != GameResult.Ongoing) continue
            for (c in 0..8) {
                if (vm.boards[b][c] == null) possibleMoves.add(b to c)
            }
        }
        
        if (possibleMoves.isNotEmpty()) {
            val move = possibleMoves.random()
            vm.place(move.first, move.second, vm.currentPlayer)
        }
        
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
            PlayerChip(Player.X, vm.currentPlayer, vm.overallResult, isBot, isAiVsAi, botPlayer)
            StatusLabel(vm.currentPlayer, vm.overallResult, vm.isThinking)
            PlayerChip(Player.O, vm.currentPlayer, vm.overallResult, isBot, isAiVsAi, botPlayer)
        }

        Spacer(modifier = Modifier.weight(1f))

        // Main Board
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(10.dp)
        ) {
            SuperBoardView(
                boards = vm.boards,
                boardResults = vm.boardResults,
                activeBoardIndex = vm.activeBoardIndex,
                overallResult = vm.overallResult,
                canTap = vm.overallResult == GameResult.Ongoing && !vm.isThinking &&
                        !isAiVsAi && !(isBot && vm.currentPlayer == botPlayer),
                onTap = { b, c -> vm.place(b, c, vm.currentPlayer) }
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
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF9C27B0)),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun SuperBoardView(
    boards: List<List<Player?>>,
    boardResults: List<GameResult>,
    activeBoardIndex: Int?,
    overallResult: GameResult,
    canTap: Boolean,
    onTap: (Int, Int) -> Unit
) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val size = minOf(maxWidth, maxHeight)
        val smallBoardSize = size / 3

        // Big Grid lines
        Canvas(modifier = Modifier.fillMaxSize()) {
            val cell = size / 3
            for (i in 1..2) {
                drawLine(
                    color = Color.Gray,
                    start = Offset(cell.toPx() * i, 0f),
                    end = Offset(cell.toPx() * i, size.toPx()),
                    strokeWidth = 4f
                )
                drawLine(
                    color = Color.Gray,
                    start = Offset(0f, cell.toPx() * i),
                    end = Offset(size.toPx(), cell.toPx() * i),
                    strokeWidth = 4f
                )
            }
        }

        // Small Boards
        for (bIdx in 0..8) {
            val row = bIdx / 3
            val col = bIdx % 3
            val isActive = activeBoardIndex == null || activeBoardIndex == bIdx
            val result = boardResults[bIdx]

            Box(
                modifier = Modifier
                    .size(smallBoardSize)
                    .offset(x = smallBoardSize * col, y = smallBoardSize * row)
                    .padding(4.dp)
                    .then(if (isActive && overallResult == GameResult.Ongoing) Modifier.background(Color.Gray.copy(alpha = 0.1f)) else Modifier)
            ) {
                if (result is GameResult.Win) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(result.player.name, fontSize = 40.sp, fontWeight = FontWeight.Black, color = result.player.color.copy(alpha = 0.5f))
                    }
                } else if (result is GameResult.Draw) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text("D", fontSize = 40.sp, color = Color.Gray.copy(alpha = 0.5f))
                    }
                }

                SmallBoard(
                    board = boards[bIdx],
                    canTap = canTap && isActive && result == GameResult.Ongoing,
                    onTap = { cIdx -> onTap(bIdx, cIdx) }
                )
            }
        }
    }
}

@Composable
fun SmallBoard(board: List<Player?>, canTap: Boolean, onTap: (Int) -> Unit) {
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val size = minOf(maxWidth, maxHeight)
        val cellSize = size / 3

        Canvas(modifier = Modifier.fillMaxSize()) {
            val cell = size / 3
            for (i in 1..2) {
                drawLine(
                    color = Color.Gray.copy(alpha = 0.3f),
                    start = Offset(cell.toPx() * i, 0f),
                    end = Offset(cell.toPx() * i, size.toPx()),
                    strokeWidth = 1f
                )
                drawLine(
                    color = Color.Gray.copy(alpha = 0.3f),
                    start = Offset(0f, cell.toPx() * i),
                    end = Offset(size.toPx(), cell.toPx() * i),
                    strokeWidth = 1f
                )
            }
        }

        for (cIdx in 0..8) {
            val row = cIdx / 3
            val col = cIdx % 3
            Box(
                modifier = Modifier
                    .size(cellSize)
                    .offset(x = cellSize * col, y = cellSize * row)
                    .clickable(enabled = canTap && board[cIdx] == null) { onTap(cIdx) },
                contentAlignment = Alignment.Center
            ) {
                board[cIdx]?.let { player ->
                    Text(player.name, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = player.color)
                }
            }
        }
    }
}
