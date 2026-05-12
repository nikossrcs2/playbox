package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

data class StackBlock(
    val id: Int,
    val x: Float,
    val width: Float,
    val y: Float,
    val color: Color
)

enum class StackGameState { PLAYING, PERFECT, MISSED, GAME_OVER }

class StackViewModel : ViewModel() {
    var blocks by mutableStateOf(listOf<StackBlock>())
    var score by mutableStateOf(0)
    var bestScore by mutableStateOf(0)
    var state by mutableStateOf(StackGameState.PLAYING)
    var movingX by mutableStateOf(0f)
    var movingWidth by mutableStateOf(200f)
    var showPerfect by mutableStateOf(false)

    private var canvasWidth = 0f
    private var direction = 1f
    private var speed = 2.5f
    private var nextId = 0

    private val colors = listOf(
        Color(0xFF00BCD4), Color(0xFF009688), Color(0xFF2196F3),
        Color(0xFF3F51B5), Color(0xFF9C27B0), Color(0xFFE91E63),
        Color(0xFFF44336), Color(0xFFFF9800), Color(0xFFFFEB3B),
        Color(0xFF4CAF50), Color(0xFF8BC34A)
    )

    fun start(w: Float) {
        canvasWidth = w
        if (blocks.isEmpty()) restart(w)
    }

    fun restart(w: Float) {
        canvasWidth = w
        blocks = listOf(StackBlock(nextId++, 0f, 300f, 0f, colors[0]))
        score = 0
        state = StackGameState.PLAYING
        movingX = -canvasWidth / 2
        movingWidth = 300f
        direction = 1f
        speed = 2.5f
    }

    fun tick() {
        if (state != StackGameState.PLAYING) return
        movingX += direction * speed
        if (abs(movingX) > canvasWidth / 2) direction = -direction
    }

    fun drop() {
        if (state != StackGameState.PLAYING) return

        val topBlock = blocks.last()
        val prevCenter = topBlock.x
        val prevWidth = topBlock.width

        val leftEdgePrev = prevCenter - prevWidth / 2
        val rightEdgePrev = prevCenter + prevWidth / 2
        val leftEdgeNew = movingX - movingWidth / 2
        val rightEdgeNew = movingX + movingWidth / 2

        val overlapLeft = maxOf(leftEdgePrev, leftEdgeNew)
        val overlapRight = minOf(rightEdgePrev, rightEdgeNew)
        val overlapWidth = overlapRight - overlapLeft

        if (overlapWidth <= 0) {
            state = StackGameState.MISSED
            viewModelScope.launch {
                delay(600)
                state = StackGameState.GAME_OVER
            }
            return
        }

        val perfectThreshold = 6f
        val isPerfect = abs(overlapWidth - prevWidth) < perfectThreshold
        val actualWidth = if (isPerfect) prevWidth else overlapWidth
        val actualCenter = if (isPerfect) prevCenter else (overlapLeft + overlapRight) / 2

        if (isPerfect) {
            showPerfect = true
            viewModelScope.launch {
                delay(600)
                showPerfect = false
            }
        }

        val nextColor = colors[(blocks.size) % colors.size]
        val newBlock = StackBlock(nextId++, actualCenter, actualWidth, blocks.size.toFloat(), nextColor)
        blocks = blocks + newBlock
        score += if (isPerfect) 2 else 1
        if (score > bestScore) bestScore = score
        
        movingWidth = actualWidth
        movingX = -canvasWidth / 2
        direction = 1f
        speed = minOf(6f, speed + 0.1f)
    }
}

@Composable
fun StackView(onBack: () -> Unit = {}) {
    val vm: StackViewModel = viewModel()
    val accentColor = Color(0xFF00BCD4)

    LaunchedEffect(vm.state) {
        while (vm.state == StackGameState.PLAYING) {
            delay(16)
            vm.tick()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = accentColor)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${vm.score}", fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onBackground)
                    Text("BEST: ${vm.bestScore}", fontSize = 11.sp, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.4f))
                }
                IconButton(onClick = { vm.restart(300f) }) {
                    Icon(Icons.Default.Refresh, contentDescription = null, tint = accentColor)
                }
            }

            // Perfect label
            if (vm.showPerfect) {
                Text(
                    "PERFECT +2",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Black,
                    color = Color(0xFFFFEB3B),
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            } else {
                Spacer(modifier = Modifier.height(20.dp))
            }

            // Game canvas
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                val density = LocalDensity.current
                val canvasW = with(density) { maxWidth.toPx() }
                val blockHeight = with(density) { 44.dp.toPx() }

                LaunchedEffect(canvasW) {
                    vm.start(canvasW)
                }

                Canvas(modifier = Modifier.fillMaxSize().clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) { vm.drop() }) {
                    val h = size.height
                    val visible = (h / blockHeight).toInt() + 2
                    val cameraOffset = maxOf(0f, (vm.blocks.size + 1 - visible) * blockHeight)
                    val yShift = cameraOffset

                    // Placed blocks
                    vm.blocks.forEach { block ->
                        val drawY = h - (block.y * blockHeight + blockHeight - yShift)
                        val bh = (blockHeight - 3).coerceAtLeast(0f)
                        if (block.width > 0f && bh > 0f) {
                            drawRoundRect(
                                color = block.color,
                                topLeft = Offset(size.width / 2 + block.x - block.width / 2, drawY - blockHeight / 2),
                                size = Size(block.width, bh),
                                cornerRadius = androidx.compose.ui.geometry.CornerRadius(6f)
                            )
                        }
                    }

                    // Moving block
                    if (vm.state == StackGameState.PLAYING) {
                        val movingY = vm.blocks.size * blockHeight
                        val drawY = h - (movingY + blockHeight - yShift)
                        val nextColor = listOf(
                            Color(0xFF00BCD4), Color(0xFF009688), Color(0xFF2196F3),
                            Color(0xFF3F51B5), Color(0xFF9C27B0), Color(0xFFE91E63),
                            Color(0xFFF44336), Color(0xFFFF9800), Color(0xFFFFEB3B),
                            Color(0xFF4CAF50), Color(0xFF8BC34A)
                        )[vm.blocks.size % 11]
                        val bh = (blockHeight - 3).coerceAtLeast(0f)
                        if (vm.movingWidth > 0f && bh > 0f) {
                            drawRoundRect(
                                color = nextColor,
                                topLeft = Offset(size.width / 2 + vm.movingX - vm.movingWidth / 2, drawY - blockHeight / 2),
                                size = Size(vm.movingWidth, bh),
                                cornerRadius = androidx.compose.ui.geometry.CornerRadius(6f)
                            )
                        }
                    }
                }
            }

            // Tap instruction
            Text(
                "TAP TO DROP",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.3f),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }

        // Game over overlay
        if (vm.state == StackGameState.GAME_OVER) {
            Box(
                modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)),
                contentAlignment = Alignment.Center
            ) {
                Card(
                    shape = RoundedCornerShape(28.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                ) {
                    Column(
                        modifier = Modifier.padding(36.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Text("💥", fontSize = 52.sp)
                        Text("Game Over", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.onSurface)
                        Text("Score: ${vm.score}", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = accentColor)
                        if (vm.score >= vm.bestScore && vm.score > 0) {
                            Text("🎉 New Best!", fontSize = 14.sp, color = Color(0xFFFFEB3B))
                        }
                        Button(
                            onClick = { vm.restart(300f) },
                            colors = ButtonDefaults.buttonColors(containerColor = accentColor),
                            shape = RoundedCornerShape(14.dp)
                        ) {
                            Text("Try Again", color = Color.White, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
