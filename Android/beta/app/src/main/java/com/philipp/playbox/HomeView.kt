package com.philipp.playbox

import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun HomeView() {
    var selectedGame by remember { mutableStateOf<GameType?>(null) }
    var titleTapCount by remember { mutableStateOf(0) }
    var showEasterEgg by remember { mutableStateOf(false) }

    if (selectedGame != null) {
        when {
            selectedGame!!.needsSetup -> GameSetupView(selectedGame!!, onBack = { selectedGame = null })
            else -> DirectGameView(selectedGame!!, onBack = { selectedGame = null })
        }
        return
    }

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
            verticalAlignment = Alignment.Top
        ) {
            Column {
                Text(
                    "Game Collection",
                    fontSize = 34.sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) {
                        titleTapCount++
                        if (titleTapCount >= 5) {
                            titleTapCount = 0
                            showEasterEgg = true
                        }
                    }
                )
                Text("Classic games & variants", fontSize = 14.sp, color = Color.Gray)
            }
        }

        // Game categories
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            GameCategory.entries.forEach { category ->
                val games = GameType.entries.filter { it.category == category }
                item {
                    CategorySection(category, games) { selectedGame = it }
                }
            }
        }
    }

    if (showEasterEgg) {
        CreditsDialog(onDismiss = { showEasterEgg = false })
    }
}

@Composable
fun CreditsDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("✨ You found it ✨", fontWeight = FontWeight.Bold) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Easter egg image
                Image(
                    painter = androidx.compose.ui.res.painterResource(id = R.drawable.ee_img),
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth(0.8f)
                        .clip(RoundedCornerShape(20.dp)),
                    contentScale = androidx.compose.ui.layout.ContentScale.Fit
                )

                Text("Here's everyone who made this possible:", fontSize = 14.sp, color = Color.Gray, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    CreditItem("Quality Assurance", "BigMannn")
                    CreditItem("Translations (German)", "Niko")
                    CreditItem("Translations (Other)", "None yet!\nContribute at github.com/nikos-projects/playbox")
                    CreditItem("Coding", "Gemini, Claude & DeepSeek\n(Prompts by Niko — \"Do i look like i know swift?\" – Niko, python dev, 2026)")
                    CreditItem("Art", "App icon: Glow added by Gemini,\ninitially made by ChatGPT")
                    CreditItem("Music", "Google Lyria 3")
                    CreditItem("SFX", "Find a way to add 'em and\nyou get credit here 😄")
                    CreditItem("Contact", "steve.jobless.lololol@gmail.com\n@niko_3992 on Discord")
                }
                
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text("Done", fontWeight = FontWeight.Bold)
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text("🕹️ Thanks for playing!", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        },
        confirmButton = {}
    )
}

@Composable
fun CreditItem(label: String, value: String) {
    Column {
        Text(label.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color.Gray, letterSpacing = 0.8.sp)
        Text(value, fontSize = 14.sp)
    }
}

@Composable
fun CategorySection(category: GameCategory, games: List<GameType>, onGameClick: (GameType) -> Unit) {
    Column {
            Column {
                Text(
                    category.displayName.uppercase(),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = Color.Gray,
                    letterSpacing = 1.2.sp,
                    modifier = Modifier.padding(start = 4.dp)
                )
            }
        Spacer(modifier = Modifier.height(12.dp))

        // 2-column grid
        val rows = games.chunked(2)
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            rows.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    row.forEach { game ->
                        GameCard(game, modifier = Modifier.weight(1f)) { onGameClick(game) }
                    }
                    // Fill empty space if odd number
                    if (row.size < 2) {
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
fun GameCard(game: GameType, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Card(
        modifier = modifier.clickable { onClick() },
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, game.accentColor.copy(alpha = 0.2f))
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(game.accentColor.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = game.icon,
                    contentDescription = null,
                    tint = game.accentColor,
                    modifier = Modifier.size(24.dp)
                )
            }
            Column {
                Text(game.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                Text(game.subtitle, fontSize = 12.sp, color = Color.Gray, maxLines = 2)
            }
            Spacer(modifier = Modifier.weight(1f))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Icon(
                    imageVector = Icons.Default.ArrowForward,
                    contentDescription = null,
                    tint = game.accentColor,
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}

@Composable
fun DirectGameView(game: GameType, onBack: () -> Unit) {
    key(game) {
        when (game) {
            GameType.CLASSIC -> ClassicTTTView(onBack = onBack)
            GameType.SNAKE -> SnakeView(onBack = onBack)
            GameType.BRICK_BREAKER -> BrickBreakerView(onBack = onBack)
            GameType.MINESWEEPER -> MinesweeperView(onBack = onBack)
            GameType.TWENTY48 -> Twenty48View(onBack = onBack)
            GameType.WORDLE -> WordleView(onBack = onBack)
            GameType.MEMORY_MATCH -> MemoryMatchView(onBack = onBack)
            GameType.STACK -> StackView(onBack = onBack)
            GameType.AIM_TRAINER -> AimTrainerView(onBack = onBack)
            GameType.FLAPPY_BIRD -> FlappyBirdView(onBack = onBack)
            GameType.TETRIS -> TetrisView(onBack = onBack)
            GameType.BLACKJACK -> BlackjackView(onBack = onBack)
            GameType.SOLITAIRE -> SolitaireView(onBack = onBack)
            GameType.CHESS -> ChessView(onBack = onBack)
            GameType.CHECKERS -> CheckersView(onBack = onBack)
            else -> {
                // Setup-required games fallback
                GameSetupView(game, onBack = onBack)
            }
        }
    }
}
