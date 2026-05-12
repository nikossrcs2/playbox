package com.philipp.playbox

import android.annotation.SuppressLint
import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlin.random.Random
import androidx.compose.ui.graphics.Brush
data class Pipe(val id: Int, var x: Float, val gapY: Float, var passed: Boolean = false)

class FlappyBirdViewModel : ViewModel() {
    var birdY by mutableStateOf(0f)
    var birdVelocity by mutableStateOf(0f)
    var pipes by mutableStateOf(listOf<Pipe>())
    var score by mutableStateOf(0)
    var highScore by mutableStateOf(0)
    var isGameOver by mutableStateOf(false)
    var isStarted by mutableStateOf(false)

    private val gravity = 0.4f
    private val jumpStrength = -7f
    private val pipeSpeed = 3f
    private val pipeWidth = 60f
    private val pipeGap = 140f
    private val birdSize = 40f
    private var canvasWidth = 0f
    private var canvasHeight = 0f
    private var frameCount = 0
    private var nextPipeId = 0

    fun setCanvas(w: Float, h: Float) {
        canvasWidth = w
        canvasHeight = h
        if (!isStarted && !isGameOver) birdY = h / 2
    }

    fun startGame() {
        if (isStarted && !isGameOver) return
        isStarted = true
        isGameOver = false
        birdY = canvasHeight / 2
        birdVelocity = 0f
        pipes = listOf()
        score = 0
        frameCount = 0
    }

    fun jump() {
        if (!isStarted) { startGame(); return }
        if (isGameOver) { startGame(); return }
        birdVelocity = jumpStrength
    }

    fun update() {
        if (!isStarted || isGameOver) return

        birdVelocity += gravity
        birdY += birdVelocity

        frameCount++
        if (frameCount >= 90 && canvasWidth > 0) {
            spawnPipe()
            frameCount = 0
        }

        // Move pipes
        pipes = pipes.map { it.copy(x = it.x - pipeSpeed) }
            .filter { it.x + pipeWidth > 0 }

        // Check score
        pipes = pipes.map { pipe ->
            if (!pipe.passed && pipe.x + pipeWidth < canvasWidth / 3) {
                score++
                pipe.copy(passed = true)
            } else pipe
        }

        // Save high score
        if (score > highScore) highScore = score

        // Check collisions
        if (birdY - birdSize / 2 <= 0 || birdY + birdSize / 2 >= canvasHeight) {
            gameOver(); return
        }

        val birdLeft = canvasWidth / 3 - birdSize / 2
        val birdRight = canvasWidth / 3 + birdSize / 2
        val birdTop = birdY - birdSize / 2
        val birdBottom = birdY + birdSize / 2

        pipes.forEach { pipe ->
            if (birdRight > pipe.x && birdLeft < pipe.x + pipeWidth) {
                if (birdTop < pipe.gapY || birdBottom > pipe.gapY + pipeGap) {
                    gameOver(); return
                }
            }
        }
    }

    private fun spawnPipe() {
        val minGapY = 100f
        val maxGapY = canvasHeight - pipeGap - 100f
        val gapY = Random.nextFloat() * (maxGapY - minGapY) + minGapY
        pipes = pipes + Pipe(nextPipeId++, canvasWidth, gapY)
    }

    private fun gameOver() {
        isGameOver = true
        isStarted = false
    }
}

@SuppressLint("UnusedBoxWithConstraintsScope")
@Composable
fun FlappyBirdView(onBack: () -> Unit = {}) {
    val vm: FlappyBirdViewModel = viewModel()

    // Game loop
    LaunchedEffect(vm.isStarted) {
        while (vm.isStarted && !vm.isGameOver) {
            delay(16)
            vm.update()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(Color(0xFF4FC3F7), Color(0xFF29B6F6))
                )
            )
            .clickable { vm.jump() }
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = Color.White)
                }
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color.White.copy(alpha = 0.2f))
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text("👑 $", color = Color(0xFFFFEB3B), fontSize = 14.sp)
                    Text("${vm.highScore}", color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                }
            }

            // Game canvas
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                LaunchedEffect(maxWidth, maxHeight) {
                    vm.setCanvas(maxWidth.value, maxHeight.value)
                }

                Canvas(modifier = Modifier.fillMaxSize()) {
                    val w = size.width
                    val h = size.height

                    // Pipes
                    vm.pipes.forEach { pipe ->
                        // Top pipe
                        drawRoundRect(
                            color = Color(0xFF4CAF50),
                            topLeft = Offset(pipe.x, 0f),
                            size = Size(60f, pipe.gapY),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8f)
                        )
                        drawRoundRect(
                            color = Color(0xFF388E3C),
                            topLeft = Offset(pipe.x - 5f, pipe.gapY - 30f),
                            size = Size(70f, 30f),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(4f)
                        )
                        // Bottom pipe
                        drawRoundRect(
                            color = Color(0xFF4CAF50),
                            topLeft = Offset(pipe.x, pipe.gapY + 140f),
                            size = Size(60f, h - (pipe.gapY + 140f)),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8f)
                        )
                        drawRoundRect(
                            color = Color(0xFF388E3C),
                            topLeft = Offset(pipe.x - 5f, pipe.gapY + 140f),
                            size = Size(70f, 30f),
                            cornerRadius = androidx.compose.ui.geometry.CornerRadius(4f)
                        )
                    }

                    // Bird
                    val birdX = w / 3
                    val rotation = minOf(maxOf(vm.birdVelocity * 3f, -30f), 90f)
                    drawCircle(
                        color = Color(0xFFFFEB3B),
                        radius = 20f,
                        center = Offset(birdX, vm.birdY)
                    )
                }

                // Score
                if (vm.isStarted && !vm.isGameOver) {
                    Text(
                        "${vm.score}",
                        fontSize = 48.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp)
                    )
                }

                // Start overlay
                if (!vm.isStarted && !vm.isGameOver) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Card(
                            shape = RoundedCornerShape(30.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))
                        ) {
                            Column(
                                modifier = Modifier.padding(30.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Text("🐤", fontSize = 60.sp)
                                Text("Flappy Bird", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                                Text("Tap to Start", fontSize = 18.sp, color = Color.Gray)
                                Text("Tap screen to fly\nAvoid the pipes", fontSize = 14.sp, color = Color.Gray,
                                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            }
                        }
                    }
                }

                // Game over overlay
                if (vm.isGameOver) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Card(
                            shape = RoundedCornerShape(30.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f))
                        ) {
                            Column(
                                modifier = Modifier.padding(30.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Text("Game Over", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                                Text("Score: ${vm.score}", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color(0xFFFFEB3B))
                                if (vm.score == vm.highScore && vm.score > 0) {
                                    Text("👑 NEW HIGH SCORE!", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color(0xFFFFEB3B))
                                } else {
                                    Text("Best: ${vm.highScore}", fontSize = 14.sp, color = Color.Gray)
                                }
                                Button(
                                    onClick = { vm.startGame() },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2196F3)),
                                    shape = RoundedCornerShape(25.dp)
                                ) {
                                    Text("Play Again", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// Brush import needed
