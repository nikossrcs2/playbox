package com.philipp.playbox

import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectTapGestures
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
import kotlin.random.Random

data class Point(val x: Int, val y: Int)

enum class Direction {
    UP, DOWN, LEFT, RIGHT;

    val opposite: Direction get() = when (this) {
        UP -> DOWN; DOWN -> UP; LEFT -> RIGHT; RIGHT -> LEFT
    }
}

enum class SnakeGameState { WAITING, PLAYING, DEAD }

class SnakeViewModel : ViewModel() {
    companion object {
        const val COLS = 20
        const val ROWS = 20
    }

    var snake by mutableStateOf(listOf<Point>())
    var food by mutableStateOf(Point(0, 0))
    var score by mutableStateOf(0)
    var highScore by mutableStateOf(0)
    var gameState by mutableStateOf(SnakeGameState.WAITING)
    var direction by mutableStateOf(Direction.RIGHT)
    private var nextDirection = Direction.RIGHT

    init {
        highScore = 0 // Could load from SharedPreferences
        setupGame()
    }

    fun setupGame() {
        val midX = COLS / 2
        val midY = ROWS / 2
        snake = listOf(Point(midX, midY), Point(midX - 1, midY), Point(midX - 2, midY))
        direction = Direction.RIGHT
        nextDirection = Direction.RIGHT
        score = 0
        spawnFood()
    }

    fun start() {
        gameState = SnakeGameState.PLAYING
    }

    fun restart() {
        setupGame()
        gameState = SnakeGameState.PLAYING
    }

    fun steer(dir: Direction) {
        if (dir != direction.opposite) {
            nextDirection = dir
        }
    }

    fun tick(): Boolean {
        if (gameState != SnakeGameState.PLAYING) return false

        direction = nextDirection
        val head = snake.first()
        val newHead = when (direction) {
            Direction.UP -> Point(head.x, head.y - 1)
            Direction.DOWN -> Point(head.x, head.y + 1)
            Direction.LEFT -> Point(head.x - 1, head.y)
            Direction.RIGHT -> Point(head.x + 1, head.y)
        }

        // Collision check
        if (newHead.x < 0 || newHead.x >= COLS || newHead.y < 0 || newHead.y >= ROWS) {
            gameState = SnakeGameState.DEAD
            if (score > highScore) highScore = score
            return false
        }
        if (snake.dropLast(1).contains(newHead)) {
            gameState = SnakeGameState.DEAD
            if (score > highScore) highScore = score
            return false
        }

        val atFood = newHead == food
        val newSnake = mutableListOf(newHead)
        newSnake.addAll(snake)
        if (!atFood) newSnake.removeLast()

        snake = newSnake

        if (atFood) {
            score += 10
            if (score > highScore) highScore = score
            spawnFood()
        }
        return true
    }

    private fun spawnFood() {
        var candidate: Point
        do {
            candidate = Point(Random.nextInt(COLS), Random.nextInt(ROWS))
        } while (snake.contains(candidate))
        food = candidate
    }
}

@Composable
fun SnakeView(onBack: () -> Unit = {}) {
    val vm: SnakeViewModel = viewModel()
    val accentColor = Color(0xFF00BCD4)

    // Game loop
    LaunchedEffect(vm.gameState) {
        if (vm.gameState == SnakeGameState.PLAYING) {
            while (vm.gameState == SnakeGameState.PLAYING) {
                delay(130)
                vm.tick()
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Top bar
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
                Text("SCORE", fontSize = 10.sp, color = Color.Gray)
                Text("${vm.score}", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = accentColor)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("BEST", fontSize = 10.sp, color = Color.Gray)
                Text("${vm.highScore}", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.Gray)
            }
        }

        // Board
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .padding(16.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surface)
                .border(2.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), RoundedCornerShape(12.dp))
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val cellW = size.width / SnakeViewModel.COLS
                val cellH = size.height / SnakeViewModel.ROWS

                // Grid dots
                for (r in 0 until SnakeViewModel.ROWS) {
                    for (c in 0 until SnakeViewModel.COLS) {
                        drawCircle(
                            color = Color.Gray.copy(alpha = 0.15f),
                            radius = 1f,
                            center = Offset(c * cellW + cellW / 2, r * cellH + cellH / 2)
                        )
                    }
                }

                // Food
                drawCircle(
                    color = Color.Red,
                    radius = cellW * 0.4f,
                    center = Offset(vm.food.x * cellW + cellW / 2, vm.food.y * cellH + cellH / 2)
                )

                // Snake
                vm.snake.forEachIndexed { index, point ->
                    val isHead = index == 0
                    val alpha = if (isHead) 1f else 0.9f - (index.toFloat() / vm.snake.size * 0.5f)
                    drawRoundRect(
                        color = accentColor.copy(alpha = alpha),
                        topLeft = Offset(point.x * cellW + 2, point.y * cellH + 2),
                        size = Size(cellW - 4, cellH - 4),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(if (isHead) 6f else 4f)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // D-Pad
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Spacer(modifier = Modifier.width(68.dp))
                DPadButton("▲", Direction.UP, accentColor) {
                    if (vm.gameState == SnakeGameState.WAITING) vm.start()
                    vm.steer(Direction.UP)
                }
                Spacer(modifier = Modifier.width(68.dp))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                DPadButton("◄", Direction.LEFT, accentColor) {
                    if (vm.gameState == SnakeGameState.WAITING) vm.start()
                    vm.steer(Direction.LEFT)
                }
                Spacer(modifier = Modifier.width(68.dp))
                DPadButton("►", Direction.RIGHT, accentColor) {
                    if (vm.gameState == SnakeGameState.WAITING) vm.start()
                    vm.steer(Direction.RIGHT)
                }
            }
            DPadButton("▼", Direction.DOWN, accentColor) {
                if (vm.gameState == SnakeGameState.WAITING) vm.start()
                vm.steer(Direction.DOWN)
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // New Game
        Button(
            onClick = { vm.restart() },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .height(50.dp),
            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
            shape = RoundedCornerShape(14.dp)
        ) {
            Text("New Game", color = Color.White, fontWeight = FontWeight.SemiBold)
        }

        Spacer(modifier = Modifier.height(24.dp))
    }

    // Overlays
    if (vm.gameState == SnakeGameState.WAITING || vm.gameState == SnakeGameState.DEAD) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f))
                .clickable { },
            contentAlignment = Alignment.Center
        ) {
            Card(
                shape = RoundedCornerShape(24.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(
                    modifier = Modifier.padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (vm.gameState == SnakeGameState.WAITING) {
                        Text("🐍", fontSize = 56.sp)
                        Text("Snake", fontSize = 32.sp, fontWeight = FontWeight.Bold)
                        Text("Tap a direction to start", fontSize = 16.sp, color = Color.Gray)
                    } else {
                        Text("💀", fontSize = 56.sp)
                        Text("Game Over", fontSize = 32.sp, fontWeight = FontWeight.Bold)
                        Text("Score: ${vm.score}", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = accentColor)
                        if (vm.score >= vm.highScore && vm.score > 0) {
                            Text("🎉 New High Score!", fontSize = 15.sp, color = Color(0xFFFFC107))
                        }
                        Button(
                            onClick = { vm.restart() },
                            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
                            shape = RoundedCornerShape(14.dp)
                        ) {
                            Text("Play Again", color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun DPadButton(label: String, direction: Direction, color: Color, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.size(60.dp),
        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(14.dp),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 2.dp)
    ) {
        Text(label, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = color)
    }
}
