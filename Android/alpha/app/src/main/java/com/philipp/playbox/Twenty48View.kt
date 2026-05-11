package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlin.random.Random

class Twenty48ViewModel : ViewModel() {
    var board by mutableStateOf(List(4) { List(4) { 0 } })
    var score by mutableStateOf(0)
    var gameOver by mutableStateOf(false)
    var won by mutableStateOf(false)

    init { reset() }

    fun reset() {
        board = List(4) { List(4) { 0 } }
        score = 0
        gameOver = false
        won = false
        addRandomTile()
        addRandomTile()
    }

    private fun addRandomTile() {
        val empty = mutableListOf<Pair<Int, Int>>()
        for (r in 0..3) for (c in 0..3) if (board[r][c] == 0) empty.add(r to c)
        if (empty.isNotEmpty()) {
            val (r, c) = empty[Random.nextInt(empty.size)]
            board = board.toMutableList().also {
                it[r] = it[r].toMutableList().also { row -> row[c] = if (Random.nextBoolean()) 2 else 4 }
            }
        }
    }

    fun move(dr: Int, dc: Int) {
        if (gameOver || won) return
        var moved = false
        val newBoard = board.map { it.toMutableList() }.toMutableList()

        if (dc != 0) {
            for (r in 0..3) {
                val row = newBoard[r].toList()
                val merged = slideAndMerge(row, dc > 0)
                if (merged != row) {
                    moved = true
                    newBoard[r] = merged.toMutableList()
                }
            }
        } else {
            for (c in 0..3) {
                val col = (0..3).map { newBoard[it][c] }
                val merged = slideAndMerge(col, dr > 0)
                if (merged != col) {
                    moved = true
                    for (r in 0..3) newBoard[r][c] = merged[r]
                }
            }
        }

        if (moved) {
            board = newBoard
            addRandomTile()
            checkGameState()
        }
    }

    private fun slideAndMerge(line: List<Int>, reverse: Boolean): List<Int> {
        var list = if (reverse) line.reversed() else line
        val filtered = list.filter { it != 0 }.toMutableList()
        var i = 0
        while (i < filtered.size - 1) {
            if (filtered[i] == filtered[i + 1]) {
                val merged = filtered[i] * 2
                score += merged
                filtered[i] = merged
                filtered.removeAt(i + 1)
            }
            i++
        }
        while (filtered.size < 4) filtered.add(0)
        return if (reverse) filtered.reversed() else filtered
    }

    private fun checkGameState() {
        for (r in 0..3) for (c in 0..3) if (board[r][c] == 2048) { won = true; return }
        for (r in 0..3) for (c in 0..3) {
            if (board[r][c] == 0) return
            if (c < 3 && board[r][c] == board[r][c + 1]) return
            if (r < 3 && board[r][c] == board[r + 1][c]) return
        }
        gameOver = true
    }
}

@Composable
fun Twenty48View(onBack: () -> Unit = {}) {
    val vm: Twenty48ViewModel = viewModel()
    val accentColor = Color(0xFF795548)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF2F2F7))
            .pointerInput(Unit) {
                detectHorizontalDragGestures { _, dragAmount ->
                    if (kotlin.math.abs(dragAmount) > 20) {
                        vm.move(0, if (dragAmount > 0) 1 else -1)
                    }
                }
            }
            .pointerInput(Unit) {
                detectVerticalDragGestures { _, dragAmount ->
                    if (kotlin.math.abs(dragAmount) > 20) {
                        vm.move(if (dragAmount > 0) 1 else -1, 0)
                    }
                }
            }
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Button(onClick = onBack) { Text("← Back", fontSize = 14.sp) }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("SCORE", fontSize = 10.sp, color = Color.Gray)
                Text("${vm.score}", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = accentColor)
            }
            Button(onClick = { vm.reset() }) { Text("↻ New", fontSize = 14.sp) }
        }

        // Board
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(16.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFBBADA0))
        ) {
            Column(
                modifier = Modifier.fillMaxSize().padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                for (r in 0..3) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        for (c in 0..3) {
                            TileView(
                                value = vm.board[r][c],
                                modifier = Modifier.weight(1f).aspectRatio(1f)
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Direction buttons
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            DirButton("▲") { vm.move(-1, 0) }
            Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                DirButton("◄") { vm.move(0, -1) }
                DirButton("►") { vm.move(0, 1) }
            }
            DirButton("▼") { vm.move(1, 0) }
        }

        Spacer(modifier = Modifier.height(24.dp))
    }

    // Overlays
    if (vm.gameOver || vm.won) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f))
                .clickable { },
            contentAlignment = Alignment.Center
        ) {
            Card(shape = RoundedCornerShape(24.dp)) {
                Column(
                    modifier = Modifier.padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(if (vm.won) "🏆" else "💀", fontSize = 56.sp)
                    Text(
                        if (vm.won) "You Win!" else "Game Over",
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text("Score: ${vm.score}", fontSize = 18.sp, color = Color.Gray)
                    Button(
                        onClick = { vm.reset() },
                        colors = ButtonDefaults.buttonColors(containerColor = accentColor)
                    ) {
                        Text("Play Again", color = Color.White)
                    }
                }
            }
        }
    }
}

@Composable
fun TileView(value: Int, modifier: Modifier = Modifier) {
    val bgColor = when (value) {
        0 -> Color(0xFFCDC1B4)
        2 -> Color(0xFFEEE4DA)
        4 -> Color(0xFFEDE0C8)
        8 -> Color(0xFFF2B179)
        16 -> Color(0xFFF59563)
        32 -> Color(0xFFF67C5F)
        64 -> Color(0xFFF65E3B)
        128 -> Color(0xFFEDCF72)
        256 -> Color(0xFFEDCC61)
        512 -> Color(0xFFEDC850)
        1024 -> Color(0xFFEDC53F)
        2048 -> Color(0xFFEDC22E)
        else -> Color(0xFF3C3A32)
    }
    val textColor = if (value <= 4) Color(0xFF776E65) else Color.White
    val fontSize = when {
        value < 100 -> 28.sp
        value < 1000 -> 22.sp
        else -> 16.sp
    }

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(bgColor),
        contentAlignment = Alignment.Center
    ) {
        if (value > 0) {
            Text(
                "$value",
                fontSize = fontSize,
                fontWeight = FontWeight.Bold,
                color = textColor
            )
        }
    }
}

@Composable
fun DirButton(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.size(60.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF795548)),
        shape = RoundedCornerShape(14.dp)
    ) {
        Text(label, fontSize = 20.sp, color = Color.White)
    }
}