package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch

@Composable
fun GameSetupView(gameType: GameType, onBack: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val aiStore = NeuralAIStore.getInstance(context)
    val neuralModel = aiStore.modelFor(gameType)

    var mode by remember { mutableStateOf(GameMode.VS_HUMAN) }
    var difficulty by remember { mutableStateOf(BotDifficulty.HARD) }
    var startGame by remember { mutableStateOf<Pair<GameMode, BotDifficulty>?>(null) }
    var showTrainingDialog by remember { mutableStateOf(false) }

    if (startGame != null) {
        key(startGame) {
            when (gameType) {
                GameType.CLASSIC -> ClassicTTTView(mode = startGame!!.first, difficulty = startGame!!.second, onBack = { startGame = null })
                GameType.CONNECT4 -> Connect4View(mode = startGame!!.first, difficulty = startGame!!.second, onBack = { startGame = null })
                GameType.WILD -> WildTTTView(mode = startGame!!.first, difficulty = startGame!!.second, onBack = { startGame = null })
                GameType.NOTAKTO -> NotaktoView(mode = startGame!!.first, difficulty = startGame!!.second, onBack = { startGame = null })
                GameType.SUPER_TTT -> SuperTTTView(mode = startGame!!.first, difficulty = startGame!!.second, onBack = { startGame = null })
                else -> { startGame = null }
            }
        }
        return
    }

    Box(modifier = Modifier.fillMaxSize()) {
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
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Text("←", fontSize = 24.sp, color = MaterialTheme.colorScheme.onBackground)
                }
                Spacer(modifier = Modifier.width(12.dp))
                Text(gameType.title, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
            }

            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                // Game info
                Card(
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = gameType.icon,
                            contentDescription = null,
                            tint = gameType.accentColor,
                            modifier = Modifier.size(48.dp)
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(gameType.subtitle, fontSize = 14.sp, color = Color.Gray)
                    }
                }

                // Mode selection
                Text("GAME MODE", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.Gray)
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    GameMode.entries.forEach { m ->
                        ModeButton(
                            title = m.displayName,
                            isSelected = mode == m,
                            color = gameType.accentColor,
                            modifier = Modifier.weight(1f)
                        ) { mode = m }
                    }
                }

                // Difficulty selection
                if (mode == GameMode.VS_BOT || mode == GameMode.AI_VS_AI) {
                    Text("DIFFICULTY", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.Gray)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        BotDifficulty.entries.forEach { d ->
                            DifficultyButton(
                                difficulty = d,
                                isSelected = difficulty == d,
                                color = gameType.accentColor,
                                modifier = Modifier.weight(1f),
                                trainedEpisodes = if (d == BotDifficulty.NEURAL) neuralModel.trainedEpisodes else null
                            ) {
                                difficulty = d
                                if (d == BotDifficulty.NEURAL) showTrainingDialog = true
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                // Start button
                Button(
                    onClick = { startGame = mode to difficulty },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = gameType.accentColor),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Text("Start Game", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
            }
        }

        if (showTrainingDialog) {
            NeuralTrainingDialog(
                model = neuralModel,
                accentColor = gameType.accentColor,
                onDismiss = { showTrainingDialog = false }
            )
        }
    }
}

@Composable
fun NeuralTrainingDialog(
    model: NeuralAIModel,
    accentColor: Color,
    onDismiss: () -> Unit
) {
    var episodes by remember { mutableStateOf(1000f) }
    var trainingProgress by remember { mutableStateOf<Double?>(null) }
    val scope = rememberCoroutineScope()

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Neural AI Training") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Trained Episodes: ${model.trainedEpisodes}")
                Text("Last Win Rate: ${(model.lastWinRate * 100).toInt()}%")

                if (model.isTraining) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth(), color = accentColor)
                    Text("Training in progress...", fontSize = 12.sp, color = Color.Gray)
                } else {
                    Text("Train for ${episodes.toInt()} episodes")
                    Slider(
                        value = episodes,
                        onValueChange = { episodes = it },
                        valueRange = 100f..10000f,
                        steps = 9,
                        colors = SliderDefaults.colors(thumbColor = accentColor, activeTrackColor = accentColor)
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    scope.launch {
                        model.trainAsync(episodes.toInt()) { progress ->
                            trainingProgress = progress
                        }
                    }
                },
                enabled = !model.isTraining,
                colors = ButtonDefaults.buttonColors(containerColor = accentColor)
            ) {
                Text("Train")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Close") }
        }
    )
}

@Composable
fun ModeButton(
    title: String,
    isSelected: Boolean,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(60.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isSelected) color.copy(alpha = 0.2f) else MaterialTheme.colorScheme.surface
        ),
        shape = RoundedCornerShape(14.dp),
        border = if (isSelected) BorderStroke(2.dp, color) else null
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = title.let { t -> 
                    when(t) {
                        "Two Players" -> Icons.Default.Group
                        "vs Bot" -> Icons.Default.SmartToy
                        "AI Battle" -> Icons.Default.Psychology
                        else -> Icons.Default.Help
                    }
                },
                contentDescription = null,
                tint = if (isSelected) color else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                title,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = if (isSelected) color else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
        }
    }
}

@Composable
fun DifficultyButton(
    difficulty: BotDifficulty,
    isSelected: Boolean,
    color: Color,
    modifier: Modifier = Modifier,
    trainedEpisodes: Int? = null,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier.height(80.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isSelected) color.copy(alpha = 0.2f) else MaterialTheme.colorScheme.surface
        ),
        shape = RoundedCornerShape(14.dp),
        border = if (isSelected) BorderStroke(2.dp, color) else null,
        contentPadding = PaddingValues(4.dp)
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = difficulty.icon,
                contentDescription = null,
                tint = if (isSelected) color else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                difficulty.displayName,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (isSelected) color else MaterialTheme.colorScheme.onSurface
            )
            Text(difficulty.description, fontSize = 10.sp, color = Color.Gray)
            if (trainedEpisodes != null) {
                Text("($trainedEpisodes eps)", fontSize = 8.sp, color = color.copy(alpha = 0.7f))
            }
        }
    }
}
