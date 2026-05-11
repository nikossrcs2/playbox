package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay

data class Brick(val id: Int, var x: Int, var y: Int, var isAlive: Boolean = true, var hitsToBreak: Int = 1)

class BrickBreakerViewModel : ViewModel() {
    companion object {
        const val COLS = 8
        const val ROWS = 5
    }

    var paddleX by mutableStateOf(0.5f)
    var ballX by mutableStateOf(0.5f)
    var ballY by mutableStateOf(0.85f)
    var ballDX by mutableStateOf(0.008f)
    var ballDY by mutableStateOf(-0.012f)
    var score by mutableStateOf(0)
    var lives by mutableStateOf(3)
    var isGameOver by mutableStateOf(false)
    var isWin by mutableStateOf(false)
    var bricks by mutableStateOf(listOf<Brick>())
    var isRunning by mutableStateOf(false)

    init { setupBricks() }

    fun setupBricks() {
        val list = mutableListOf<Brick>()
        var id = 0
        for (row in 0 until ROWS) {
            for (col in 0 until COLS) {
                val hits = when {
                    row < 2 -> 1
                    row < 4 -> 2
                    else -> 3
                }
                list.add(Brick(id++, col, row, hitsToBreak = hits))
            }
        }
        bricks = list
    }

    fun start() { isRunning = true }

    fun reset() {
        paddleX = 0.5f
        ballX = 0.5f
        ballY = 0.85f
        ballDX = 0.008f
        ballDY = -0.012f
        score = 0
        lives = 3
        isGameOver = false
        isWin = false
        setupBricks()
        isRunning = true
    }

    fun movePaddle(to: Float) {
        paddleX = (to - 0.1f).coerceIn(0f, 0.8f)
    }

    fun update() {
        if (!isRunning || isGameOver || isWin) return

        ballX += ballDX
        ballY += ballDY

        // Wall collisions
        if (ballX <= 0f || ballX >= 1f) ballDX = -ballDX
        if (ballY <= 0f) ballDY = -ballDY

        // Paddle collision
        if (ballY >= 0.96f && ballY <= 1f && ballX >= paddleX && ballX <= paddleX + 0.2f) {
            val hitPos = (ballX - paddleX) / 0.2f
            ballDX = (hitPos - 0.5f) * 0.02f
            ballDY = -abs(ballDY)
            ballY = 0.95f
        }

        // Bottom (lose life)
        if (ballY >= 1f) {
            lives--
            if (lives <= 0) {
                isGameOver = true
                isRunning = false
            } else {
                ballX = paddleX + 0.1f
                ballY = 0.85f
                ballDX = 0.008f
                ballDY = -0.012f
            }
        }

        // Brick collisions
        val brickH = 0.05f
        val brickW = 1f / COLS
        val ballSize = 0.02f

        bricks = bricks.map { brick ->
            if (!brick.isAlive) return@map brick

            val bx = brick.x * brickW
            val by = brick.y * brickH + 0.02f

            if (ballX + ballSize > bx && ballX - ballSize < bx + brickW &&
                ballY + ballSize > by && ballY - ballSize < by + brickH) {

                val newHits = brick.hitsToBreak - 1
                if (newHits <= 0) {
                    score += 10
                    // Bounce
                    val overlapLeft = abs((ballX + ballSize) - bx)
                    val overlapRight = abs((ballX - ballSize) - (bx + brickW))
                    val overlapTop = abs((ballY + ballSize) - by)
                    val overlapBottom = abs((ballY - ballSize) - (by + brickH))
                    if (minOf(overlapLeft, overlapRight) < minOf(overlapTop, overlapBottom)) ballDX = -ballDX
                    else ballDY = -ballDY
                    brick.copy(isAlive = false, hitsToBreak = 0)
                } else {
                    score += 5
                    ballDY = -ballDY
                    brick.copy(hitsToBreak = newHits)
                }
            } else brick
        }

        // Check win
        if (bricks.all { !it.isAlive }) {
            isWin = true
            isRunning = false
        }
    }
}

@Composable
fun BrickBreakerView(onBack: () -> Unit = {}) {
    val vm: BrickBreakerViewModel = viewModel()
    val accentColor = Color(0xFFFF9800)

    // Game loop
    LaunchedEffect(vm.isRunning) {
        while (vm.isRunning && !vm.isGameOver && !vm.isWin) {
            delay(16)
            vm.update()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF2F2F7))
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Button(onClick = onBack) { Text("← Back") }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("SCORE", fontSize = 10.sp, color = Color.Gray)
                Text("${vm.score}", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = accentColor)
            }
            Row {
                repeat(vm.lives) {
                    Text("❤️", fontSize = 16.sp)
                }
            }
        }

        // Game canvas
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.8f)
                .padding(16.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF1A1A2E))
                .pointerInput(Unit) {
                    detectDragGestures { change, _ ->
                        vm.movePaddle(change.position.x / size.width)
                    }
                }
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val w = size.width
                val h = size.height
                val brickW = w / BrickBreakerViewModel.COLS
                val brickH = h * 0.05f

                // Bricks
                vm.bricks.filter { it.isAlive }.forEach { brick ->
                    val color = when (brick.hitsToBreak) {
                        1 -> Color.Red; 2 -> Color(0xFFFF9800); else -> Color(0xFFFFEB3B)
                    }
                    drawRoundRect(
                        color = color,
                        topLeft = Offset(brick.x * brickW + 1, brick.y * brickH + h * 0.02f),
                        size = Size(brickW - 2, brickH - 2),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(4f)
                    )
                }

                // Paddle
                drawRoundRect(
                    color = accentColor,
                    topLeft = Offset(vm.paddleX * w, h * 0.96f),
                    size = Size(w * 0.2f, h * 0.02f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(8f)
                )

                // Ball
                drawCircle(
                    color = Color.White,
                    radius = w * 0.01f,
                    center = Offset(vm.ballX * w, vm.ballY * h)
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            "Drag left/right to move paddle",
            fontSize = 12.sp,
            color = Color.Gray,
            modifier = Modifier.fillMaxWidth(),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )

        Spacer(modifier = Modifier.height(16.dp))

        // New Game button
        Button(
            onClick = { vm.reset() },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold)
        }

        Spacer(modifier = Modifier.height(24.dp))
    }

    // Overlays
    if (vm.isGameOver || vm.isWin) {
        Box(
            modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center
        ) {
            Card(shape = RoundedCornerShape(24.dp)) {
                Column(
                    modifier = Modifier.padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text(if (vm.isWin) "🏆" else "💀", fontSize = 56.sp)
                    Text(
                        if (vm.isWin) "You Win!" else "Game Over",
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

fun abs(value: Float): Float = if (value < 0) -value else value