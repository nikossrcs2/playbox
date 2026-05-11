package com.philipp.playbox

import android.annotation.SuppressLint
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

data class MemoryCard(
    val id: Int,
    val symbol: String,
    var isFaceUp: Boolean = false,
    var isMatched: Boolean = false
)

class MemoryMatchViewModel : ViewModel() {
    companion object {
        val allSymbols = listOf(
            "⭐","❤️","⚡","🌙","☀️","🍀","🔥","💧","❄️","☁️",
            "🎵","🔔","🎁","📷","🎧","🎮","🚗","✈️","🚲","🚩","👑","💎"
        )
        val levels = listOf(
            4 to 3,  // 12 cards, 6 pairs
            4 to 4,  // 16 cards, 8 pairs
            4 to 5,  // 20 cards, 10 pairs
            6 to 5   // 30 cards, 15 pairs
        )
    }

    var cards by mutableStateOf(listOf<MemoryCard>())
    var moves by mutableStateOf(0)
    var matches by mutableStateOf(0)
    var isGameOver by mutableStateOf(false)
    var level by mutableStateOf(1)
    var elapsedSeconds by mutableStateOf(0)
    var showLevelUp by mutableStateOf(false)
    var gridCols by mutableStateOf(4)
    var gridRows by mutableStateOf(3)

    private var faceUpIndices = mutableListOf<Int>()
    private var isChecking = false
    var timerStarted = false

    val totalPairs get() = cards.size / 2

    init { startLevel(1) }

    fun startLevel(lvl: Int) {
        level = lvl
        val (cols, rows) = levels[minOf(lvl - 1, levels.size - 1)]
        gridCols = cols
        gridRows = rows
        val pairCount = (cols * rows) / 2
        val symbols = allSymbols.shuffled().take(pairCount)
        cards = (symbols + symbols).shuffled().mapIndexed { index, symbol ->
            MemoryCard(id = index, symbol = symbol)
        }
        moves = 0
        matches = 0
        isGameOver = false
        faceUpIndices.clear()
        isChecking = false
        elapsedSeconds = 0
        showLevelUp = false
        timerStarted = true
    }

    fun restart() { startLevel(level) }

    fun nextLevel() {
        val next = minOf(level + 1, levels.size)
        startLevel(next)
    }

    fun flip(index: Int) {
        if (isChecking || cards[index].isFaceUp || cards[index].isMatched) return

        cards = cards.toMutableList().also { it[index] = it[index].copy(isFaceUp = true) }
        faceUpIndices.add(index)

        if (faceUpIndices.size == 2) {
            moves++
            isChecking = true
            val a = faceUpIndices[0]
            val b = faceUpIndices[1]

            // Use coroutine for delay
            kotlinx.coroutines.MainScope().launch {
                delay(850)
                if (cards[a].symbol == cards[b].symbol) {
                    cards = cards.toMutableList().also {
                        it[a] = it[a].copy(isMatched = true)
                        it[b] = it[b].copy(isMatched = true)
                    }
                    matches++
                    if (matches == totalPairs) {
                        if (level < levels.size) showLevelUp = true
                        else isGameOver = true
                    }
                } else {
                    cards = cards.toMutableList().also {
                        it[a] = it[a].copy(isFaceUp = false)
                        it[b] = it[b].copy(isFaceUp = false)
                    }
                }
                faceUpIndices.clear()
                isChecking = false
            }
        }
    }
}

@SuppressLint("UnusedBoxWithConstraintsScope")
@Composable
fun MemoryMatchView(onBack: () -> Unit = {}) {
    val vm: MemoryMatchViewModel = viewModel()
    val accentColor = Color(0xFFE91E63)

    // Timer
    LaunchedEffect(vm.timerStarted) {
        while (!vm.isGameOver && !vm.showLevelUp) {
            delay(1000)
            vm.elapsedSeconds++
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
            Button(onClick = onBack) { Text("←") }
            Text("Memory Match", fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Button(onClick = { vm.restart() }) { Text("↻") }
        }

        // Stats
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            StatChip("🏆", "Level ${vm.level}", accentColor)
            StatChip("👆", "${vm.moves}", Color.Gray)
            StatChip("⏱", "${vm.elapsedSeconds}s", Color.Gray)
            StatChip("✅", "${vm.matches}/${vm.totalPairs}", Color(0xFF4CAF50))
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Grid
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        ) {
            BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                val spacing = 4.dp
                val cellW = (maxWidth - spacing * (vm.gridCols + 1)) / vm.gridCols
                val cellH = cellW * 1.25f

                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(spacing),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    for (r in 0 until vm.gridRows) {
                        Row(horizontalArrangement = Arrangement.spacedBy(spacing)) {
                            for (c in 0 until vm.gridCols) {
                                val idx = r * vm.gridCols + c
                                if (idx < vm.cards.size) {
                                    MemoryCardView(
                                        card = vm.cards[idx],
                                        width = cellW,
                                        height = cellH,
                                        color = accentColor,
                                        onClick = { vm.flip(idx) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Level up overlay
    if (vm.showLevelUp) {
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
                    Text("⭐", fontSize = 52.sp)
                    Text("Level ${vm.level} Complete!", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Text("${vm.moves} moves · ${vm.elapsedSeconds}s", color = Color.Gray)
                    Button(
                        onClick = { vm.nextLevel() },
                        colors = ButtonDefaults.buttonColors(containerColor = accentColor)
                    ) {
                        Text("Next Level →", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }

    // Game over overlay
    if (vm.isGameOver) {
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
                    Text("🏆", fontSize = 52.sp)
                    Text("You Finished!", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Text("All levels complete\n${vm.moves} moves · ${vm.elapsedSeconds}s", color = Color.Gray)
                    Button(
                        onClick = { vm.startLevel(1) },
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
fun MemoryCardView(card: MemoryCard, width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp, color: Color, onClick: () -> Unit) {
    val rotation by animateFloatAsState(
        targetValue = if (card.isFaceUp) 0f else 180f,
        animationSpec = tween(durationMillis = 400)
    )

    Box(
        modifier = Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .graphicsLayer {
                rotationY = rotation
                cameraDistance = 12f * density
            },
        contentAlignment = Alignment.Center
    ) {
        if (rotation <= 90f) {
            // Front
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White)
                    .then(
                        if (card.isMatched) Modifier.border(2.dp, color, RoundedCornerShape(12.dp))
                        else Modifier.border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(12.dp))
                    ),
                contentAlignment = Alignment.Center
            ) {
                Text(card.symbol, fontSize = 22.sp)
            }
        } else {
            // Back
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(color)
                    .graphicsLayer { rotationY = 180f },
                contentAlignment = Alignment.Center
            ) {
                Text("?", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun StatChip(icon: String, value: String, color: Color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(Color.White)
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Text(icon, fontSize = 12.sp)
        Spacer(modifier = Modifier.width(4.dp))
        Text(value, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color)
    }
}

// Need this import for MainScope
