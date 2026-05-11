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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlin.random.Random

enum class TetrominoType(val color: Color) {
    I(Color(0xFF00D4DC)),
    O(Color(0xFFFFD600)),
    T(Color(0xFF9933CC)),
    S(Color(0xFF33CC33)),
    Z(Color(0xFFEE3333)),
    J(Color(0xFF3344CC)),
    L(Color(0xFFFF8C00))
}

class TetrisViewModel : ViewModel() {
    companion object {
        const val COLS = 10
        const val ROWS = 20
    }

    var board by mutableStateOf(List(ROWS) { MutableList(COLS) { null as Color? } })
    var currentPiece by mutableStateOf<TetrisPiece?>(null)
    var nextType by mutableStateOf(TetrominoType.I)
    var score by mutableStateOf(0)
    var level by mutableStateOf(1)
    var linesCleared by mutableStateOf(0)
    var isGameOver by mutableStateOf(false)
    var isPaused by mutableStateOf(false)
    var ghostCells by mutableStateOf(listOf<Pair<Int, Int>>())

    private var bag = mutableListOf<TetrominoType>()

    init { spawnPiece() }

    private fun nextFromBag(): TetrominoType {
        if (bag.isEmpty()) bag = TetrominoType.entries.shuffled().toMutableList()
        return bag.removeAt(0)
    }

    private fun spawnPiece() {
        val type = nextType
        nextType = nextFromBag()
        val piece = TetrisPiece(type, 0, COLS / 2 - 2, 0)
        if (!isValid(piece)) {
            isGameOver = true
            currentPiece = null
        } else {
            currentPiece = piece
            updateGhost()
        }
    }

    fun isValid(piece: TetrisPiece): Boolean {
        for ((c, r) in piece.cells) {
            if (c !in 0 until COLS) return false
            if (r >= ROWS) return false
            if (r >= 0 && board[r][c] != null) return false
        }
        return true
    }

    fun moveLeft() { move(-1, 0) }
    fun moveRight() { move(1, 0) }
    fun softDrop() { move(0, 1) }

    private fun move(dc: Int, dr: Int) {
        if (isPaused || isGameOver) return
        val piece = currentPiece ?: return
        val moved = piece.moved(dc, dr)
        if (isValid(moved)) {
            currentPiece = moved
            updateGhost()
        } else if (dr == 1) lock()
    }

    fun rotate() {
        if (isPaused || isGameOver) return
        val piece = currentPiece ?: return
        val rotated = piece.rotated()
        for (kick in listOf(0, -1, 1, -2, 2)) {
            val kicked = rotated.moved(kick, 0)
            if (isValid(kicked)) {
                currentPiece = kicked
                updateGhost()
                return
            }
        }
    }

    fun hardDrop() {
        if (isPaused || isGameOver) return
        var piece = currentPiece ?: return
        var dropped = 0
        while (isValid(piece.moved(0, 1))) {
            piece = piece.moved(0, 1)
            dropped++
        }
        score += dropped * 2
        currentPiece = piece
        lock()
    }

    private fun updateGhost() {
        val piece = currentPiece ?: return
        var ghost = piece
        while (isValid(ghost.moved(0, 1))) ghost = ghost.moved(0, 1)
        ghostCells = ghost.cells
    }

    private fun lock() {
        val piece = currentPiece ?: return
        piece.cells.forEach { (c, r) ->
            if (r in 0 until ROWS) board[r][c] = piece.type.color
        }
        clearLines()
        spawnPiece()
    }

    private fun clearLines() {
        var cleared = 0
        val newBoard = mutableListOf<MutableList<Color?>>()
        for (row in board) {
            if (row.all { it != null }) cleared++
            else newBoard.add(row)
        }
        repeat(cleared) { newBoard.add(0, MutableList(COLS) { null }) }
        board = newBoard
        linesCleared += cleared
        score += listOf(0, 100, 300, 500, 800)[minOf(cleared, 4)] * level
        level = linesCleared / 10 + 1
    }

    fun tick() {
        if (!isPaused && !isGameOver) softDrop()
    }

    fun restart() {
        board = List(ROWS) { MutableList(COLS) { null } }
        score = 0; level = 1; linesCleared = 0; isGameOver = false; isPaused = false
        bag.clear(); nextType = nextFromBag(); spawnPiece()
    }

    fun togglePause() { isPaused = !isPaused }
}

data class TetrisPiece(val type: TetrominoType, val rotation: Int, val col: Int, val row: Int) {
    private val rotations = mapOf(
        TetrominoType.I to listOf(
            listOf(0 to 1, 1 to 1, 2 to 1, 3 to 1),
            listOf(2 to 0, 2 to 1, 2 to 2, 2 to 3),
            listOf(0 to 2, 1 to 2, 2 to 2, 3 to 2),
            listOf(1 to 0, 1 to 1, 1 to 2, 1 to 3)
        ),
        TetrominoType.O to listOf(
            listOf(1 to 0, 2 to 0, 1 to 1, 2 to 1),
            listOf(1 to 0, 2 to 0, 1 to 1, 2 to 1),
            listOf(1 to 0, 2 to 0, 1 to 1, 2 to 1),
            listOf(1 to 0, 2 to 0, 1 to 1, 2 to 1)
        ),
        TetrominoType.T to listOf(
            listOf(1 to 0, 0 to 1, 1 to 1, 2 to 1),
            listOf(1 to 0, 1 to 1, 2 to 1, 1 to 2),
            listOf(0 to 1, 1 to 1, 2 to 1, 1 to 2),
            listOf(1 to 0, 0 to 1, 1 to 1, 1 to 2)
        ),
        TetrominoType.S to listOf(
            listOf(1 to 0, 2 to 0, 0 to 1, 1 to 1),
            listOf(1 to 0, 1 to 1, 2 to 1, 2 to 2),
            listOf(1 to 1, 2 to 1, 0 to 2, 1 to 2),
            listOf(0 to 0, 0 to 1, 1 to 1, 1 to 2)
        ),
        TetrominoType.Z to listOf(
            listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1),
            listOf(2 to 0, 1 to 1, 2 to 1, 1 to 2),
            listOf(0 to 1, 1 to 1, 1 to 2, 2 to 2),
            listOf(1 to 0, 0 to 1, 1 to 1, 0 to 2)
        ),
        TetrominoType.J to listOf(
            listOf(0 to 0, 0 to 1, 1 to 1, 2 to 1),
            listOf(1 to 0, 2 to 0, 1 to 1, 1 to 2),
            listOf(0 to 1, 1 to 1, 2 to 1, 2 to 2),
            listOf(1 to 0, 1 to 1, 0 to 2, 1 to 2)
        ),
        TetrominoType.L to listOf(
            listOf(2 to 0, 0 to 1, 1 to 1, 2 to 1),
            listOf(1 to 0, 1 to 1, 1 to 2, 2 to 2),
            listOf(0 to 1, 1 to 1, 2 to 1, 0 to 2),
            listOf(0 to 0, 1 to 0, 1 to 1, 1 to 2)
        )
    )

    val cells: List<Pair<Int, Int>> get() = rotations[type]!![rotation].map { (dc, dr) -> col + dc to row + dr }

    fun rotated() = copy(rotation = (rotation + 1) % 4)
    fun moved(dc: Int, dr: Int) = copy(col = col + dc, row = row + dr)
}

@Composable
fun TetrisView(onBack: () -> Unit = {}) {
    val vm: TetrisViewModel = viewModel()

    // Game loop
    LaunchedEffect(vm.isPaused, vm.isGameOver) {
        val interval = maxOf(100L, 800L - (vm.level - 1) * 70L)
        while (!vm.isGameOver) {
            delay(interval)
            if (!vm.isPaused) vm.tick()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) { detectHorizontalDragGestures { _, dragAmount ->
                if (kotlin.math.abs(dragAmount) > 30) {
                    if (dragAmount > 0) vm.moveRight() else vm.moveLeft()
                }
            }}
            .pointerInput(Unit) { detectVerticalDragGestures { _, dragAmount ->
                if (dragAmount > 50) vm.hardDrop()
            }}
            .clickable { vm.rotate() }
    ) {
        Row(modifier = Modifier.fillMaxSize().padding(8.dp)) {
            // Board
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color.White.copy(alpha = 0.06f))
                    .border(1.dp, Color.White.copy(alpha = 0.15f), RoundedCornerShape(6.dp))
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val cw = size.width / TetrisViewModel.COLS
                    val ch = size.height / TetrisViewModel.ROWS

                    // Board cells
                    for (r in 0 until TetrisViewModel.ROWS) {
                        for (c in 0 until TetrisViewModel.COLS) {
                            vm.board[r][c]?.let { color ->
                                drawRoundRect(color, Offset(c * cw + 1, r * ch + 1), Size(cw - 2, ch - 2), 3f)
                            }
                        }
                    }

                    // Ghost
                    vm.ghostCells.forEach { (c, r) ->
                        if (r >= 0) {
                            drawRoundRect(
                                Color.White.copy(alpha = 0.18f), Offset(c * cw + 1, r * ch + 1),
                                Size(cw - 2, ch - 2), 3f, style = Stroke(1.5f)
                            )
                        }
                    }

                    // Current piece
                    vm.currentPiece?.cells?.forEach { (c, r) ->
                        if (r >= 0) {
                            drawRoundRect(
                                vm.currentPiece!!.type.color, Offset(c * cw + 1, r * ch + 1),
                                Size(cw - 2, ch - 2), 3f
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            // Side panel
            Column(
                modifier = Modifier.width(80.dp).fillMaxHeight(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                StatCard("SCORE", "${vm.score}")
                StatCard("LEVEL", "${vm.level}")
                StatCard("LINES", "${vm.linesCleared}")

                Text("NEXT", color = Color.White.copy(alpha = 0.5f), fontSize = 8.sp, fontWeight = FontWeight.Bold)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color.White.copy(alpha = 0.07f)),
                    contentAlignment = Alignment.Center
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val piece = TetrisPiece(vm.nextType, 0, 0, 0)
                        val cells = piece.cells
                        val cellS = 14f
                        val offsetX = (size.width - 4 * cellS) / 2
                        val offsetY = (size.height - 2 * cellS) / 2
                        cells.forEach { (c, r) ->
                            drawRoundRect(vm.nextType.color, Offset(offsetX + c * cellS, offsetY + r * cellS), Size(cellS, cellS), 2f)
                        }
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                Button(
                    onClick = { vm.restart() },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.1f))
                ) { Text("↻", color = Color.White) }
            }
        }

        // Pause button
        Button(
            onClick = { vm.togglePause() },
            modifier = Modifier.align(Alignment.TopEnd).padding(4.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.1f))
        ) {
            Text(if (vm.isPaused) "▶" else "⏸", color = Color.White)
        }

        // Overlays
        if (vm.isGameOver) {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.75f)), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("GAME OVER", color = Color.White, fontSize = 26.sp, fontWeight = FontWeight.Black)
                    Text("Score: ${vm.score}", color = Color(0xFFFFD600), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    Button(onClick = { vm.restart() }, shape = RoundedCornerShape(10.dp)) {
                        Text("PLAY AGAIN", color = Color.Black, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        if (vm.isPaused && !vm.isGameOver) {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)), contentAlignment = Alignment.Center) {
                Text("PAUSED", color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.Black)
            }
        }
    }
}

@Composable
fun StatCard(title: String, value: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.07f))
            .padding(vertical = 8.dp, horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(title, color = Color.White.copy(alpha = 0.5f), fontSize = 8.sp, fontWeight = FontWeight.Bold)
        Text(value, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Black)
    }
}

fun DrawScope.drawRoundRect(color: Color, topLeft: Offset, size: Size, cornerRadius: Float, style: androidx.compose.ui.graphics.drawscope.DrawStyle = Fill) {
    val path = Path().apply {
        addRoundRect(RoundRect(
            left = topLeft.x,
            top = topLeft.y,
            right = topLeft.x + size.width,
            bottom = topLeft.y + size.height,
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(cornerRadius)
        ))
    }
    drawPath(path, color, style = style)
}