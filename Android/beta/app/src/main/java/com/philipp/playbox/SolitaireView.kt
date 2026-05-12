package com.philipp.playbox

import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlin.math.roundToInt

// ── Card Model ──────────────────────────────────────────────────────────────

enum class Suit(val symbol: String, val isRed: Boolean) {
    SPADES("♠", false), HEARTS("♥", true),
    DIAMONDS("♦", true), CLUBS("♣", false)
}

enum class Rank(val display: String, val value: Int) {
    ACE("A", 1), TWO("2", 2), THREE("3", 3), FOUR("4", 4),
    FIVE("5", 5), SIX("6", 6), SEVEN("7", 7), EIGHT("8", 8),
    NINE("9", 9), TEN("10", 10), JACK("J", 11), QUEEN("Q", 12), KING("K", 13)
}

data class Card(
    val id: Int,
    val suit: Suit,
    val rank: Rank,
    var isFaceUp: Boolean = false
) {
    val isRed get() = suit.isRed
}

// ── ViewModel ───────────────────────────────────────────────────────────────

class SolitaireViewModel : ViewModel() {
    var stock by mutableStateOf(listOf<Card>())
    var waste by mutableStateOf(listOf<Card>())
    var foundations by mutableStateOf(List(4) { listOf<Card>() })
    var tableau by mutableStateOf(List(7) { listOf<Card>() })
    var moves by mutableStateOf(0)
    var won by mutableStateOf(false)

    // Selection state
    var selectedSource by mutableStateOf<String?>(null) // "waste", "tableau_0", "foundation_2"
    var selectedCardIndex by mutableStateOf(0)

    private var nextId = 0

    init { newGame() }

    fun newGame() {
        nextId = 0
        var deck = Suit.entries.flatMap { suit ->
            Rank.entries.map { rank -> Card(nextId++, suit, rank) }
        }.shuffled().toMutableList()

        tableau = (0..6).map { col ->
            val pile = deck.take(col + 1).toMutableList()
            deck = deck.drop(col + 1).toMutableList()
            pile.forEachIndexed { i, card ->
                if (i == pile.size - 1) card.isFaceUp = true
            }
            pile
        }
        stock = deck
        waste = emptyList()
        foundations = List(4) { emptyList() }
        moves = 0
        won = false
        selectedSource = null
    }

    fun drawFromStock() {
        if (stock.isEmpty()) {
            stock = waste.reversed().map { it.also { it.isFaceUp = false } }
            waste = emptyList()
        } else {
            val card = stock.last().also { it.isFaceUp = true }
            stock = stock.dropLast(1)
            waste = waste + card
        }
        moves++
        selectedSource = null
    }

    fun canPlaceOnFoundation(card: Card, foundationIndex: Int): Boolean {
        val pile = foundations[foundationIndex]
        if (pile.isEmpty()) return card.rank == Rank.ACE
        val top = pile.last()
        return top.suit == card.suit && top.rank.value + 1 == card.rank.value
    }

    fun canPlaceOnTableau(card: Card, col: Int): Boolean {
        val pile = tableau[col]
        if (pile.isEmpty()) return card.rank == Rank.KING
        val top = pile.last()
        return top.isFaceUp && top.isRed != card.isRed && top.rank.value - 1 == card.rank.value
    }

    fun selectWaste() {
        if (waste.isEmpty()) return
        selectedSource = "waste"
        selectedCardIndex = waste.size - 1
    }

    fun selectTableauCard(col: Int, index: Int) {
        val pile = tableau[col]
        if (index >= pile.size || !pile[index].isFaceUp) return
        selectedSource = "tableau_$col"
        selectedCardIndex = index
    }

    fun tapFoundation(fi: Int) {
        if (selectedSource != null) {
            // Try to move selected to foundation
            moveToFoundation(fi)
        } else if (foundations[fi].isNotEmpty()) {
            selectedSource = "foundation_$fi"
            selectedCardIndex = foundations[fi].size - 1
        }
    }

    fun tapTableau(col: Int) {
        if (selectedSource != null) {
            moveToTableau(col)
        }
    }

    fun moveToFoundation(fi: Int): Boolean {
        when {
            selectedSource == "waste" -> {
                if (waste.isEmpty()) return false
                val card = waste.last()
                if (!canPlaceOnFoundation(card, fi)) return false
                foundations = foundations.toMutableList().also { it[fi] = it[fi] + card }
                waste = waste.dropLast(1)
            }
            selectedSource?.startsWith("tableau_") == true -> {
                val col = selectedSource!!.split("_")[1].toInt()
                val pile = tableau[col]
                if (selectedCardIndex >= pile.size) return false
                val card = pile[selectedCardIndex]
                if (!canPlaceOnFoundation(card, fi)) return false
                if (selectedCardIndex == pile.size - 1) {
                    foundations = foundations.toMutableList().also { it[fi] = it[fi] + card }
                    tableau = tableau.toMutableList().also {
                        val newPile = it[col].dropLast(1).toMutableList()
                        if (newPile.isNotEmpty() && !newPile.last().isFaceUp) newPile.last().isFaceUp = true
                        it[col] = newPile
                    }
                }
            }
            selectedSource?.startsWith("foundation_") == true -> {
                val sfi = selectedSource!!.split("_")[1].toInt()
                if (sfi == fi) { selectedSource = null; return false }
                val card = foundations[sfi].last()
                if (!canPlaceOnFoundation(card, fi)) return false
                foundations = foundations.toMutableList().also {
                    it[fi] = it[fi] + card
                    it[sfi] = it[sfi].dropLast(1)
                }
            }
        }
        selectedSource = null
        moves++
        checkWin()
        return true
    }

    fun moveToTableau(col: Int): Boolean {
        var moved = false
        when {
            selectedSource == "waste" -> {
                if (waste.isEmpty()) return false
                val card = waste.last()
                if (!canPlaceOnTableau(card, col)) return false
                tableau = tableau.toMutableList().also { it[col] = it[col] + card }
                waste = waste.dropLast(1)
                moved = true
            }
            selectedSource?.startsWith("tableau_") == true -> {
                val fromCol = selectedSource!!.split("_")[1].toInt()
                if (fromCol == col) { selectedSource = null; return false }
                val fromPile = tableau[fromCol]
                if (selectedCardIndex >= fromPile.size) return false
                val cards = fromPile.drop(selectedCardIndex)
                if (!canPlaceOnTableau(cards.first(), col)) return false
                tableau = tableau.toMutableList().also {
                    it[col] = it[col] + cards
                    val remaining = it[fromCol].take(selectedCardIndex).toMutableList()
                    if (remaining.isNotEmpty() && !remaining.last().isFaceUp) remaining.last().isFaceUp = true
                    it[fromCol] = remaining
                }
                moved = true
            }
            selectedSource?.startsWith("foundation_") == true -> {
                val fi = selectedSource!!.split("_")[1].toInt()
                val card = foundations[fi].last()
                if (!canPlaceOnTableau(card, col)) return false
                foundations = foundations.toMutableList().also { it[fi] = it[fi].dropLast(1) }
                tableau = tableau.toMutableList().also { it[col] = it[col] + card }
                moved = true
            }
        }
        if (moved) {
            selectedSource = null
            moves++
        }
        return moved
    }

    fun autoMoveToFoundation(): Boolean {
        // Auto-move waste to foundation
        if (waste.isNotEmpty()) {
            for (fi in 0..3) {
                if (canPlaceOnFoundation(waste.last(), fi)) {
                    return moveToFoundation(fi)
                }
            }
        }
        // Auto-move tableau top cards
        for (col in 0..6) {
            if (tableau[col].isNotEmpty()) {
                val card = tableau[col].last()
                for (fi in 0..3) {
                    if (canPlaceOnFoundation(card, fi)) {
                        selectedSource = "tableau_$col"
                        selectedCardIndex = tableau[col].size - 1
                        return moveToFoundation(fi)
                    }
                }
            }
        }
        return false
    }

    private fun checkWin() {
        won = foundations.all { it.size == 13 }
    }

    fun deselect() { selectedSource = null }
}

// ── Composable ──────────────────────────────────────────────────────────────

@Composable
fun SolitaireView(onBack: () -> Unit = {}) {
    val vm: SolitaireViewModel = viewModel()
    val accentColor = Color(0xFF3F51B5)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1B5E20))
    ) {
        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = Color.White)
            }
            Text("Solitaire", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${vm.moves} moves", color = Color.White.copy(alpha = 0.7f), fontSize = 11.sp)
                IconButton(onClick = { vm.newGame() }) {
                    Text("↻", color = Color.White, fontSize = 18.sp)
                }
            }
        }

        // Game area
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp)
        ) {
            val colW = (maxWidth - 32.dp) / 7
            val cardH = colW * 1.4f
            val cardOverlapFaceDown = cardH * 0.2f
            val cardOverlapFaceUp = cardH * 0.4f

            Column {
                // Top row: Stock, Waste, Foundations
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    // Stock
                    Box(
                        modifier = Modifier
                            .width(colW)
                            .height(cardH)
                            .clip(RoundedCornerShape(6.dp))
                            .background(
                                if (vm.stock.isEmpty()) Color.White.copy(alpha = 0.1f)
                                else accentColor.copy(alpha = 0.8f)
                            )
                            .clickable { vm.drawFromStock() },
                        contentAlignment = Alignment.Center
                    ) {
                        if (vm.stock.isEmpty()) {
                            Text("↻", color = Color.White.copy(alpha = 0.5f), fontSize = 24.sp)
                        } else {
                            Text("🂠", fontSize = 28.sp)
                        }
                    }

                    // Waste
                    Box(
                        modifier = Modifier
                            .width(colW)
                            .height(cardH)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color.White.copy(alpha = 0.1f))
                            .then(
                                if (vm.waste.isNotEmpty() && vm.selectedSource == "waste")
                                    Modifier.border(2.dp, Color.Yellow, RoundedCornerShape(6.dp))
                                else Modifier
                            )
                            .clickable { vm.selectWaste() },
                        contentAlignment = Alignment.Center
                    ) {
                        vm.waste.lastOrNull()?.let { card ->
                            CardFace(card, Modifier.fillMaxSize())
                        }
                    }

                    Spacer(modifier = Modifier.width(8.dp))

                    // Foundations
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (fi in 0..3) {
                            Box(
                                modifier = Modifier
                                    .width(colW)
                                    .height(cardH)
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(Color.White.copy(alpha = 0.1f))
                                    .border(1.dp, accentColor.copy(alpha = 0.4f), RoundedCornerShape(6.dp))
                                    .then(
                                        if (vm.selectedSource?.startsWith("foundation_$fi") == true)
                                            Modifier.border(2.dp, Color.Yellow, RoundedCornerShape(6.dp))
                                        else Modifier
                                    )
                                    .clickable {
                                        if (vm.selectedSource != null) vm.moveToFoundation(fi)
                                        else vm.tapFoundation(fi)
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                vm.foundations[fi].lastOrNull()?.let { card ->
                                    CardFace(card, Modifier.fillMaxSize().padding(2.dp))
                                } ?: Text(
                                    Suit.entries[fi].symbol,
                                    color = if (Suit.entries[fi].isRed) Color.Red.copy(alpha = 0.3f) else Color.White.copy(alpha = 0.3f),
                                    fontSize = 20.sp
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // Tableau
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    for (col in 0..6) {
                        val pile = vm.tableau[col]
                        Column(
                            modifier = Modifier
                                .width(colW)
                                .clickable {
                                    if (vm.selectedSource != null) vm.moveToTableau(col)
                                }
                        ) {
                            // Empty column indicator
                            if (pile.isEmpty()) {
                                Box(
                                    modifier = Modifier
                                        .width(colW)
                                        .height(cardH)
                                        .clip(RoundedCornerShape(6.dp))
                                        .border(1.dp, Color.White.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
                                )
                            } else {
                                pile.forEachIndexed { index, card ->
                                    val isSelected = vm.selectedSource == "tableau_$col" &&
                                            index >= vm.selectedCardIndex
                                    Box(
                                        modifier = Modifier
                                            .width(colW)
                                            .height(cardH)
                                            .offset(y = if (index > 0) {
                                                val prevCards = pile.take(index)
                                                var totalOffset = 0f
                                                prevCards.forEach { totalOffset += if (it.isFaceUp) cardOverlapFaceUp.value else cardOverlapFaceDown.value }
                                                (-cardH.value * index + totalOffset).dp
                                            } else 0.dp)
                                            .zIndex(index.toFloat())
                                            .clickable { vm.selectTableauCard(col, index) }
                                            .then(
                                                if (isSelected) Modifier.border(2.dp, Color.Yellow, RoundedCornerShape(4.dp))
                                                else Modifier
                                            )
                                    ) {
                                        if (card.isFaceUp) {
                                            CardFace(card, Modifier.fillMaxSize())
                                        } else {
                                            CardBack(Modifier.fillMaxSize())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Deselect button
        if (vm.selectedSource != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.5f))
                    .padding(8.dp),
                horizontalArrangement = Arrangement.Center
            ) {
                TextButton(onClick = { vm.deselect() }) {
                    Text("Cancel Selection", color = Color.White)
                }
            }
        }
    }

    // Win overlay
    if (vm.won) {
        Box(
            modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f)),
            contentAlignment = Alignment.Center
        ) {
            Card(shape = RoundedCornerShape(24.dp)) {
                Column(
                    modifier = Modifier.padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Text("🏆", fontSize = 64.sp)
                    Text("You Won!", fontSize = 34.sp, fontWeight = FontWeight.Bold)
                    Text("${vm.moves} moves", fontSize = 18.sp, color = Color.Gray)
                    Button(onClick = { vm.newGame() }) {
                        Text("New Game", color = Color.White)
                    }
                }
            }
        }
    }
}

@Composable
fun CardFace(card: Card, modifier: Modifier = Modifier) {
    val textColor = if (card.suit.isRed) Color.Red else Color.Black
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFFF5F5F5))
            .border(0.5.dp, Color.Gray.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
            .padding(3.dp)
    ) {
        Text(
            "${card.rank.display}${card.suit.symbol}",
            color = textColor,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
fun CardBack(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(Color(0xFF283593))
            .border(1.dp, Color.White.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
    )
}