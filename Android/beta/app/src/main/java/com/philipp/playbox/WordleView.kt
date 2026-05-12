package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class TileState { EMPTY, FILLED, CORRECT, PRESENT, ABSENT }

class WordleViewModel : ViewModel() {
    var grid by mutableStateOf(List(6) { MutableList(5) { ' ' } })
    var tileStates by mutableStateOf(List(6) { MutableList(5) { TileState.EMPTY } })
    var currentRow by mutableStateOf(0)
    var currentCol by mutableStateOf(0)
    var gameOver by mutableStateOf(false)
    var won by mutableStateOf(false)
    var message by mutableStateOf("")
    var keyStates by mutableStateOf(mapOf<Char, TileState>())
    var shakeRow by mutableStateOf<Int?>(null)

    private val wordList = listOf(
        "SWIFT", "REACT", "FLUTT", "DART", "KOTLN", "JAVAS", "PYTHN", "RUBY", "GOAL", "RUSTY",
        "APPLE", "BRAVE", "CLOUD", "DREAM", "EAGLE", "FLAME", "GRAPE", "HEART", "IVORY", "JEWEL",
        "KNIFE", "LEMON", "MANGO", "NOBLE", "OCEAN", "PEARL", "QUEEN", "RIVER", "STONE", "TIGER"
    )
    private var targetWord = "SWIFT"

    init { pickWord() }

    fun pickWord() {
        targetWord = wordList.random().uppercase()
    }

    fun reset() {
        grid = List(6) { MutableList(5) { ' ' } }
        tileStates = List(6) { MutableList(5) { TileState.EMPTY } }
        currentRow = 0; currentCol = 0; gameOver = false; won = false; message = ""
        keyStates = mapOf(); shakeRow = null
        pickWord()
    }

    fun letterPressed(ch: Char) {
        if (gameOver || currentCol >= 5) return
        grid[currentRow][currentCol] = ch
        tileStates[currentRow][currentCol] = TileState.FILLED
        currentCol++
    }

    fun deletePressed() {
        if (gameOver || currentCol <= 0) return
        currentCol--
        grid[currentRow][currentCol] = ' '
        tileStates[currentRow][currentCol] = TileState.EMPTY
    }

    fun enterPressed() {
        if (gameOver || currentCol < 5 || currentRow >= 6) {
            shakeRow = currentRow
            return
        }

        val guess = grid[currentRow].joinToString("")

        // Evaluate
        val result = MutableList(5) { TileState.ABSENT }
        val remaining = targetWord.toMutableList()

        // Correct positions
        for (i in 0..4) {
            if (guess[i] == targetWord[i]) {
                result[i] = TileState.CORRECT
                remaining[i] = '_'
            }
        }

        // Present but wrong position
        for (i in 0..4) {
            if (result[i] == TileState.CORRECT) continue
            val idx = remaining.indexOf(guess[i])
            if (idx >= 0) {
                result[i] = TileState.PRESENT
                remaining[idx] = '_'
            }
        }

        val row = currentRow
        val snapshotResult = result.toList()
        (0..4).forEach { i ->
            viewModelScope.launch {
                delay(i * 80L)
                val newTileStates = tileStates.map { it.toMutableList() }.toMutableList()
                newTileStates[row][i] = snapshotResult[i]
                tileStates = newTileStates
            }
        }

        // Update keyboard
        (0..4).forEach { i ->
            val ch = guess[i]
            val state = result[i]
            val existing = keyStates[ch]
            keyStates = keyStates + when (state) {
                TileState.CORRECT -> ch to TileState.CORRECT
                TileState.PRESENT -> ch to (if (existing == TileState.CORRECT) TileState.CORRECT else TileState.PRESENT)
                TileState.ABSENT -> ch to (existing ?: TileState.ABSENT)
                else -> ch to state
            }
        }

        if (guess == targetWord) {
            won = true; gameOver = true
            message = listOf("Brilliant! 🎉", "Excellent! 🌟", "Great! 👏", "Nice!", "Phew! 😅", "Lucky! 🍀")[row]
        } else {
            currentRow++; currentCol = 0
            if (currentRow == 6) { gameOver = true; message = targetWord }
        }
    }
}

@Composable
fun WordleView(onBack: () -> Unit = {}) {
    val vm: WordleViewModel = viewModel()
    val accentColor = Color(0xFF4CAF50)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = accentColor)
            }
            Text("Wordle", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onBackground)
            IconButton(onClick = { vm.reset() }) {
                Icon(Icons.Default.Refresh, contentDescription = null, tint = accentColor)
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Grid
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            for (r in 0..5) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (c in 0..4) {
                        val state = vm.tileStates[r][c]
                        val ch = vm.grid[r][c]
                        Box(
                            modifier = Modifier
                                .size(56.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(
                                    when (state) {
                                        TileState.EMPTY -> MaterialTheme.colorScheme.surfaceVariant
                                        TileState.FILLED -> MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
                                        TileState.CORRECT -> Color(0xFF66BB6A)
                                        TileState.PRESENT -> Color(0xFFD4A843)
                                        TileState.ABSENT -> Color(0xFF9E9E9E)
                                    }
                                )
                                .border(
                                    1.dp,
                                    if (r == vm.currentRow && ch != ' ' && !vm.gameOver) accentColor.copy(alpha = 0.5f)
                                    else Color.Transparent,
                                    RoundedCornerShape(6.dp)
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                if (ch == ' ') "" else ch.toString(),
                                fontSize = 26.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (state == TileState.EMPTY || state == TileState.FILLED) MaterialTheme.colorScheme.onSurface else Color.White
                            )
                        }
                    }
                }
            }
        }

        // Message
        if (vm.message.isNotEmpty()) {
            Text(
                if (vm.gameOver && !vm.won) "Answer: ${vm.message}" else vm.message,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (vm.won) accentColor else MaterialTheme.colorScheme.onBackground,
                modifier = Modifier.fillMaxWidth().padding(12.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        // Keyboard
        val rows = listOf(
            listOf('Q','W','E','R','T','Y','U','I','O','P'),
            listOf('A','S','D','F','G','H','J','K','L'),
            listOf('↵','Z','X','C','V','B','N','M','⌫')
        )

        Column(
            modifier = Modifier.fillMaxWidth().padding(4.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            rows.forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    row.forEach { ch ->
                        val ks = vm.keyStates[ch]
                        val bg = when (ks) {
                            TileState.CORRECT -> Color(0xFF66BB6A)
                            TileState.PRESENT -> Color(0xFFD4A843)
                            TileState.ABSENT -> Color(0xFF9E9E9E)
                            else -> Color.White
                        }
                        val fg = if (ks != null && ks != TileState.EMPTY) Color.White else Color.Black
                        val isWide = ch == '↵' || ch == '⌫'
                        Button(
                            onClick = {
                                when (ch) {
                                    '⌫' -> vm.deletePressed()
                                    '↵' -> vm.enterPressed()
                                    else -> vm.letterPressed(ch)
                                }
                            },
                            modifier = Modifier
                                .width(if (isWide) 50.dp else 32.dp)
                                .height(46.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = bg),
                            shape = RoundedCornerShape(6.dp),
                            contentPadding = PaddingValues(0.dp)
                        ) {
                            Text(
                                when (ch) {
                                    '↵' -> "ENTER"
                                    '⌫' -> "⌫"
                                    else -> ch.toString()
                                },
                                fontSize = if (isWide) 10.sp else 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = fg
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))
    }
}