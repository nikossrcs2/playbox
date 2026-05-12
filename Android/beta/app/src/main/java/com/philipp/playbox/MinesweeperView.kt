package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlin.random.Random

data class Cell(
    var isMine: Boolean = false,
    var isRevealed: Boolean = false,
    var isFlagged: Boolean = false,
    var adjacentMines: Int = 0
)

class MinesweeperViewModel : ViewModel() {
    companion object {
        const val ROWS = 9
        const val COLS = 9
        const val MINE_COUNT = 10
    }

    var board by mutableStateOf(List(ROWS) { List(COLS) { Cell() } })
    var gameOver by mutableStateOf(false)
    var win by mutableStateOf(false)
    var flagsRemaining by mutableStateOf(MINE_COUNT)

    init { reset() }

    fun reset() {
        gameOver = false
        win = false
        flagsRemaining = MINE_COUNT
        board = List(ROWS) { List(COLS) { Cell() } }

        // Place mines
        val newBoard = List(ROWS) { MutableList(COLS) { Cell() } }
        var placed = 0
        while (placed < MINE_COUNT) {
            val r = Random.nextInt(ROWS)
            val c = Random.nextInt(COLS)
            if (!newBoard[r][c].isMine) {
                newBoard[r][c] = newBoard[r][c].copy(isMine = true)
                placed++
            }
        }

        // Calculate adjacent
        board = newBoard.mapIndexed { r, row ->
            row.mapIndexed { c, cell ->
                if (cell.isMine) cell
                else {
                    var count = 0
                    for (dr in -1..1) {
                        for (dc in -1..1) {
                            val nr = r + dr
                            val nc = c + dc
                            if (nr in 0 until ROWS && nc in 0 until COLS && newBoard[nr][nc].isMine) count++
                        }
                    }
                    cell.copy(adjacentMines = count)
                }
            }
        }
    }

    fun revealCell(r: Int, c: Int) {
        if (gameOver || win || board[r][c].isFlagged || board[r][c].isRevealed) return

        if (board[r][c].isMine) {
            // Game over - reveal all mines
            board = board.map { row -> row.map { if (it.isMine) it.copy(isRevealed = true) else it } }
            gameOver = true
            return
        }

        revealRecursive(r, c)
        checkWin()
    }

    private fun revealRecursive(r: Int, c: Int) {
        if (r !in 0 until ROWS || c !in 0 until COLS) return
        if (board[r][c].isRevealed || board[r][c].isFlagged || board[r][c].isMine) return

        val newBoard = board.map { it.toMutableList() }.toMutableList()
        newBoard[r][c] = newBoard[r][c].copy(isRevealed = true)
        board = newBoard

        if (board[r][c].adjacentMines == 0) {
            for (dr in -1..1) {
                for (dc in -1..1) {
                    if (dr != 0 || dc != 0) revealRecursive(r + dr, c + dc)
                }
            }
        }
    }

    fun toggleFlag(r: Int, c: Int) {
        if (gameOver || win || board[r][c].isRevealed) return

        val newBoard = board.map { it.toMutableList() }.toMutableList()
        val newRow = newBoard[r].toMutableList()
        newRow[c] = newRow[c].copy(isFlagged = !newRow[c].isFlagged)
        newBoard[r] = newRow
        
        if (newRow[c].isFlagged) {
            if (flagsRemaining > 0) {
                flagsRemaining--
            } else {
                // Don't flag if no flags left
                return
            }
        } else {
            flagsRemaining++
        }
        board = newBoard
        checkWin()
    }

    private fun checkWin() {
        val revealed = board.sumOf { row -> row.count { !it.isMine && it.isRevealed } }
        val totalSafe = ROWS * COLS - MINE_COUNT
        if (revealed == totalSafe) {
            win = true
            gameOver = true
        }
    }
}

@Composable
fun MinesweeperView(onBack: () -> Unit = {}) {
    val vm: MinesweeperViewModel = viewModel()

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
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
            }

            if (vm.gameOver) {
                Text(
                    if (vm.win) "You Win! 🎉" else "Game Over 💀",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (vm.win) Color(0xFF4CAF50) else Color.Red
                )
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("🚩", fontSize = 18.sp)
                Spacer(modifier = Modifier.width(4.dp))
                Text("${vm.flagsRemaining}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
            }

            Button(onClick = { vm.reset() }) {
                Text("↻", fontSize = 18.sp)
            }
        }

        // Board
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(16.dp)
        ) {
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val cellSize = maxWidth / MinesweeperViewModel.COLS

                Column {
                    for (r in 0 until MinesweeperViewModel.ROWS) {
                        Row {
                            for (c in 0 until MinesweeperViewModel.COLS) {
                                MineCell(
                                    cell = vm.board[r][c],
                                    size = cellSize,
                                    onTap = { vm.revealCell(r, c) },
                                    onLongPress = { vm.toggleFlag(r, c) }
                                )
                            }
                        }
                    }
                }
            }
        }

        Text(
            "Tap to reveal • Long press to flag",
            fontSize = 12.sp,
            color = Color.Gray,
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}

@Composable
fun MineCell(cell: Cell, size: androidx.compose.ui.unit.Dp, onTap: () -> Unit, onLongPress: () -> Unit) {
    val bgColor = if (cell.isRevealed) Color(0xFFE8E8ED) else Color(0xFFD1D1D6)
    val numberColor = when (cell.adjacentMines) {
        1 -> Color.Blue; 2 -> Color(0xFF4CAF50); 3 -> Color.Red
        4 -> Color(0xFF9C27B0); 5 -> Color(0xFFFF9800)
        else -> Color.Black
    }

    Box(
        modifier = Modifier
            .size(size)
            .border(0.5.dp, Color.Gray.copy(alpha = 0.3f))
            .background(bgColor)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { onTap() },
                    onLongPress = { onLongPress() }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        when {
            cell.isFlagged && !cell.isRevealed -> Text("🚩", fontSize = (size.value * 0.45f).sp)
            cell.isRevealed && cell.isMine -> Text("💣", fontSize = (size.value * 0.45f).sp)
            cell.isRevealed && cell.adjacentMines > 0 -> Text(
                "${cell.adjacentMines}",
                fontSize = (size.value * 0.4f).sp,
                fontWeight = FontWeight.Bold,
                color = numberColor
            )
        }
    }
}