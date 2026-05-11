package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlin.random.Random

data class AimTarget(
    val id: Int,
    val x: Float,
    val y: Float,
    val size: Float,
    val spawnedAt: Long = System.currentTimeMillis()
)

enum class AimMode { CLICK, AIM, REFLEX }

enum class ReflexState { WAITING, READY, GO, TOO_EARLY, DONE }

class AimTrainerViewModel : ViewModel() {
    var mode by mutableStateOf(AimMode.AIM)
    var targets by mutableStateOf(listOf<AimTarget>())
    var score by mutableStateOf(0)
    var misses by mutableStateOf(0)
    var reactionTimes by mutableStateOf(listOf<Int>())
    var sessionActive by mutableStateOf(false)
    var countdown by mutableStateOf(3)
    var timeLeft by mutableStateOf(30)
    var showResults by mutableStateOf(false)
    var reflexState by mutableStateOf(ReflexState.WAITING)
    var reflexReactionMs by mutableStateOf<Int?>(null)
    var reflexHistory by mutableStateOf(listOf<Int>())
    var reflexStartTime by mutableStateOf(0L)
    var canvasWidth by mutableStateOf(0f)
    var canvasHeight by mutableStateOf(0f)

    val avgReaction: Int get() = if (reactionTimes.isEmpty()) 0 else reactionTimes.average().toInt()
    val bestReaction: Int get() = reactionTimes.minOrNull() ?: 0
    val accuracy: Int get() {
        val total = score + misses
        return if (total == 0) 100 else (score * 100 / total)
    }
    val reflexAvg: Int get() = if (reflexHistory.isEmpty()) 0 else reflexHistory.average().toInt()

    private var nextId = 0

    fun setCanvas(w: Float, h: Float) {
        canvasWidth = w
        canvasHeight = h
    }

    fun startSession() {
        score = 0; misses = 0; reactionTimes = listOf(); targets = listOf()
        timeLeft = 30; showResults = false; countdown = 3; sessionActive = false
    }

    fun onCountdownTick(): Boolean {
        if (countdown > 1) { countdown--; return false }
        else {
            sessionActive = true
            spawnTarget()
            return true
        }
    }

    fun onSessionTick(): Boolean {
        if (timeLeft > 1) { timeLeft--; return true }
        else {
            sessionActive = false
            targets = listOf()
            showResults = true
            return false
        }
    }

    fun hitTarget(target: AimTarget) {
        if (!sessionActive) return
        val ms = (System.currentTimeMillis() - target.spawnedAt).toInt()
        reactionTimes = reactionTimes + ms
        score++
        targets = targets.filter { it.id != target.id }
    }

    fun missedTap() {
        if (sessionActive && mode == AimMode.AIM) misses++
    }

    fun spawnTarget() {
        if (!sessionActive || canvasWidth == 0f || canvasHeight == 0f) return
        val size = if (mode == AimMode.AIM) Random.nextFloat() * 34f + 36f else 56f
        val padding = size / 2 + 10
        val x = Random.nextFloat() * (canvasWidth - padding * 2) + padding
        val y = Random.nextFloat() * (canvasHeight - padding * 2) + padding
        targets = listOf(AimTarget(nextId++, x, y, size))
    }

    // Reflex mode
    fun startReflexRound() {
        reflexState = ReflexState.READY
        reflexReactionMs = null
    }

    fun onReflexGo() {
        reflexState = ReflexState.GO
        reflexStartTime = System.currentTimeMillis()
    }

    fun reflexTap() {
        when (reflexState) {
            ReflexState.WAITING -> startReflexRound()
            ReflexState.READY -> reflexState = ReflexState.TOO_EARLY
            ReflexState.GO -> {
                val ms = (System.currentTimeMillis() - reflexStartTime).toInt()
                reflexReactionMs = ms
                reflexHistory = reflexHistory + ms
                reflexState = ReflexState.DONE
            }
            ReflexState.TOO_EARLY, ReflexState.DONE -> startReflexRound()
        }
    }

    fun resetReflex() {
        reflexHistory = listOf()
        reflexState = ReflexState.WAITING
    }
}

@Composable
fun AimTrainerView(onBack: () -> Unit = {}) {
    val vm: AimTrainerViewModel = viewModel()
    val accentColor = Color(0xFFFF9800)

    // Countdown timer
    LaunchedEffect(vm.countdown) {
        if (vm.countdown > 0 && !vm.sessionActive) {
            delay(1000)
            if (vm.onCountdownTick()) {
                // Session started
            }
        }
    }

    // Session timer
    LaunchedEffect(vm.sessionActive) {
        while (vm.sessionActive) {
            delay(1000)
            vm.onSessionTick()
        }
    }

    // Reflex delay timer
    LaunchedEffect(vm.reflexState) {
        if (vm.reflexState == ReflexState.READY) {
            delay((1500..4500).random().toLong())
            vm.onReflexGo()
        }
        if (vm.reflexState == ReflexState.TOO_EARLY) {
            delay(1500)
            vm.startReflexRound()
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
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Button(onClick = onBack) { Text("←") }
            Text("Aim Trainer", fontSize = 17.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.width(40.dp))
        }

        // Mode picker
        if (!vm.sessionActive && !vm.showResults) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White)
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(0.dp)
            ) {
                listOf(AimMode.CLICK to "Click Speed", AimMode.AIM to "Aim Training", AimMode.REFLEX to "Reflex Test").forEach { (mode, label) ->
                    Button(
                        onClick = { vm.mode = mode; vm.showResults = false; vm.sessionActive = false; vm.reflexState = ReflexState.WAITING },
                        modifier = Modifier.weight(1f).height(40.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (vm.mode == mode) accentColor else Color.Transparent
                        ),
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        Text(label, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                            color = if (vm.mode == mode) Color.White else Color.Gray)
                    }
                }
            }
        }

        when (vm.mode) {
            AimMode.REFLEX -> ReflexView(vm, accentColor)
            else -> AimView(vm, accentColor)
        }
    }
}

@Composable
fun AimView(vm: AimTrainerViewModel, accentColor: Color) {
    Box(
        modifier = Modifier.fillMaxSize()
    ) {
        if (vm.showResults) {
            // Results
            Column(
                modifier = Modifier.fillMaxSize().padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text("Session Results", fontSize = 26.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(20.dp))
                Text("${vm.score}", fontSize = 64.sp, fontWeight = FontWeight.ExtraBold, color = accentColor)
                Text("Targets Hit", color = Color.Gray)
                Spacer(modifier = Modifier.height(24.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ResultCard("Accuracy", "${vm.accuracy}%", Color(0xFF4CAF50), Modifier.weight(1f))
                    ResultCard("Avg", "${vm.avgReaction}ms", Color(0xFF2196F3), Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ResultCard("Best", "${vm.bestReaction}ms", Color(0xFFFFEB3B), Modifier.weight(1f))
                    ResultCard("Misses", "${vm.misses}", Color.Red, Modifier.weight(1f))
                }

                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = { vm.startSession() },
                    colors = ButtonDefaults.buttonColors(containerColor = accentColor),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.width(200.dp).height(50.dp)
                ) {
                    Text("Play Again", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        } else if (vm.sessionActive) {
            // Live canvas
            BoxWithConstraints(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color.White)
                    .clickable { vm.missedTap() }
            ) {
                val density = LocalDensity.current
                LaunchedEffect(maxWidth, maxHeight) {
                    with(density) {
                        vm.setCanvas(maxWidth.toPx(), maxHeight.toPx())
                    }
                }

                // Targets
                vm.targets.forEach { target ->
                    Box(
                        modifier = Modifier
                            .offset(x = (target.x - target.size / 2).dp, y = (target.y - target.size / 2).dp)
                            .size(target.size.dp)
                            .clip(CircleShape)
                            .background(accentColor.copy(alpha = 0.15f))
                            .border(3.dp, accentColor, CircleShape)
                            .clickable { vm.hitTarget(target) },
                        contentAlignment = Alignment.Center
                    ) {
                        Box(
                            modifier = Modifier.size(10.dp).clip(CircleShape).background(accentColor)
                        )
                    }
                }

                // HUD
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    HudBadge("Hits", "${vm.score}", Color(0xFF4CAF50))
                    HudBadge("Time", "${vm.timeLeft}s", accentColor)
                    HudBadge("Miss", "${vm.misses}", Color.Red)
                }
            }
        } else if (vm.countdown < 3) {
            // Countdown
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "${vm.countdown}",
                    fontSize = 80.sp,
                    fontWeight = FontWeight.ExtraBold,
                    color = accentColor
                )
            }
        } else {
            // Start prompt
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text("🎯", fontSize = 64.sp)
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    if (vm.mode == AimMode.CLICK) "Click Speed Test" else "Aim Training",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    if (vm.mode == AimMode.CLICK) "Tap targets as fast as possible.\n30 seconds. Ready?"
                    else "Hit the targets. Accuracy matters.\n30 seconds. Ready?",
                    color = Color.Gray,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                Spacer(modifier = Modifier.height(20.dp))
                Button(
                    onClick = { vm.startSession() },
                    colors = ButtonDefaults.buttonColors(containerColor = accentColor),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.width(160.dp).height(50.dp)
                ) {
                    Text("Start", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
fun ReflexView(vm: AimTrainerViewModel, accentColor: Color) {
    Column(
        modifier = Modifier.fillMaxSize().padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // History
        if (vm.reflexHistory.isNotEmpty()) {
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                items(vm.reflexHistory.size) { i ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White)
                            .padding(horizontal = 10.dp, vertical = 8.dp)
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("${vm.reflexHistory[i]}", fontSize = 13.sp, fontWeight = FontWeight.Bold,
                                color = when {
                                    vm.reflexHistory[i] < 200 -> Color(0xFF4CAF50)
                                    vm.reflexHistory[i] < 300 -> Color(0xFFFFEB3B)
                                    else -> Color(0xFFFF9800)
                                })
                            Text("ms", fontSize = 9.sp, color = Color.Gray)
                        }
                    }
                }
                if (vm.reflexHistory.size >= 3) {
                    item {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(accentColor.copy(alpha = 0.1f))
                                .padding(horizontal = 10.dp, vertical = 8.dp)
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("Avg", fontSize = 11.sp, color = Color.Gray)
                                Text("${vm.reflexAvg}ms", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = accentColor)
                            }
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(16.dp))
        }

        // Big tap button
        val bgColor = when (vm.reflexState) {
            ReflexState.WAITING -> Color(0xFFBDBDBD)
            ReflexState.READY -> Color.Red.copy(alpha = 0.8f)
            ReflexState.GO -> Color(0xFF4CAF50)
            ReflexState.TOO_EARLY -> Color(0xFF9C27B0).copy(alpha = 0.8f)
            ReflexState.DONE -> Color(0xFF2196F3).copy(alpha = 0.7f)
        }

        val label = when (vm.reflexState) {
            ReflexState.WAITING -> "Tap to Start"
            ReflexState.READY -> "Wait for green…"
            ReflexState.GO -> "TAP NOW!"
            ReflexState.TOO_EARLY -> "Too early! Wait…"
            ReflexState.DONE -> "Tap for next round"
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(24.dp))
                .background(bgColor)
                .clickable { vm.reflexTap() },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    when (vm.reflexState) {
                        ReflexState.WAITING -> "👆"
                        ReflexState.READY -> "⏳"
                        ReflexState.GO -> "⚡"
                        ReflexState.TOO_EARLY -> "⚠️"
                        ReflexState.DONE -> "✅"
                    },
                    fontSize = 56.sp
                )
                Text(label, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
                vm.reflexReactionMs?.let { ms ->
                    Text("$ms ms", fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
                    Text(
                        when {
                            ms < 150 -> "⚡ Superhuman!"
                            ms < 200 -> "🔥 Elite"
                            ms < 250 -> "✅ Great"
                            ms < 300 -> "👍 Good"
                            ms < 400 -> "😐 Average"
                            else -> "🐢 Keep practicing"
                        },
                        fontSize = 14.sp,
                        color = Color.White.copy(alpha = 0.8f)
                    )
                }
            }
        }
    }
}

@Composable
fun ResultCard(title: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = color)
            Text(title, fontSize = 12.sp, color = Color.Gray)
        }
    }
}

@Composable
fun HudBadge(label: String, value: String, color: Color) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White.copy(alpha = 0.8f))
            .padding(horizontal = 14.dp, vertical = 8.dp)
    ) {
        Text(value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = color)
        Spacer(modifier = Modifier.width(4.dp))
        Text(label, fontSize = 11.sp, color = Color.Gray)
    }
}