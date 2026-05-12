package com.philipp.playbox

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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlin.random.Random

data class BjCard(val suit: String, val rank: String, val value: Int, val isFaceDown: Boolean = false) {
    val display get() = "$rank$suit"
    val isRed get() = suit == "♥" || suit == "♦"
}

enum class BjPhase { BETTING, PLAYER_TURN, DEALER_TURN, RESULT }

class BlackjackViewModel : ViewModel() {
    var deck by mutableStateOf(listOf<BjCard>())
    var playerHand by mutableStateOf(listOf<BjCard>())
    var dealerHand by mutableStateOf(listOf<BjCard>())
    var phase by mutableStateOf(BjPhase.BETTING)
    var chips by mutableStateOf(1000)
    var bet by mutableStateOf(0)
    var outcome by mutableStateOf("")
    var message by mutableStateOf("")
    var dealerThinking by mutableStateOf(false)

    val betOptions = listOf(25, 50, 100, 200)

    val playerValue: Int get() = handValue(playerHand)
    val dealerValue: Int get() = handValue(dealerHand.filter { !it.isFaceDown })

    init { buildDeck() }

    fun buildDeck() {
        val suits = listOf("♠", "♥", "♦", "♣")
        val ranks = listOf("2" to 2, "3" to 3, "4" to 4, "5" to 5, "6" to 6, "7" to 7, "8" to 8, "9" to 9,
            "10" to 10, "J" to 10, "Q" to 10, "K" to 10, "A" to 11)
        deck = (1..6).flatMap {
            suits.flatMap { suit -> ranks.map { (rank, value) -> BjCard(suit, rank, value) } }
        }.shuffled()
    }

    fun draw(): BjCard {
        if (deck.isEmpty()) buildDeck()
        return deck.first().also { deck = deck.drop(1) }
    }

    fun placeBet(amount: Int) {
        if (chips >= amount && phase == BjPhase.BETTING) {
            bet += amount
            chips -= amount
        }
    }

    fun clearBet() {
        if (phase == BjPhase.BETTING) {
            chips += bet
            bet = 0
        }
    }

    fun deal() {
        if (bet == 0) return
        if (deck.size < 15) buildDeck()
        playerHand = listOf(draw(), draw())
        dealerHand = listOf(draw(), draw().copy(isFaceDown = true))
        outcome = ""
        phase = BjPhase.PLAYER_TURN

        if (playerValue == 21) stand()
    }

    fun hit() {
        if (phase != BjPhase.PLAYER_TURN) return
        playerHand = playerHand + draw()
        if (playerValue > 21) {
            outcome = "Bust!"
            revealDealer()
            phase = BjPhase.RESULT
        } else if (playerValue == 21) stand()
    }

    fun stand() {
        if (phase != BjPhase.PLAYER_TURN) return
        phase = BjPhase.DEALER_TURN
        dealerThinking = true
        revealDealer()
    }

    fun doubleDown() {
        if (phase != BjPhase.PLAYER_TURN || playerHand.size != 2 || chips < bet) return
        chips -= bet
        bet *= 2
        playerHand = playerHand + draw()
        if (playerValue > 21) {
            outcome = "Bust!"
            revealDealer()
            phase = BjPhase.RESULT
        } else stand()
    }

    fun revealDealer() {
        dealerHand = dealerHand.map { it.copy(isFaceDown = false) }
    }

    fun dealerPlayStep(): Boolean {
        val dv = handValue(dealerHand)
        if (dv >= 17) {
            dealerThinking = false
            settle()
            phase = BjPhase.RESULT
            return false
        } else {
            dealerHand = dealerHand + draw()
            return true
        }
    }

    private fun settle() {
        val pv = playerValue
        val dv = handValue(dealerHand)

        if (pv > 21) {
            outcome = "Bust! Dealer Wins"
            bet = 0
        } else if (dv > 21) {
            outcome = "Dealer Busts! You Win!"
            chips += bet * 2
            bet = 0
        } else if (pv > dv) {
            outcome = "You Win!"
            chips += bet * 2
            bet = 0
        } else if (dv > pv) {
            outcome = "Dealer Wins"
            bet = 0
        } else {
            outcome = "Push - Tie"
            chips += bet
            bet = 0
        }
    }

    fun newRound() {
        playerHand = listOf()
        dealerHand = listOf()
        bet = 0
        outcome = ""
        message = ""
        phase = BjPhase.BETTING
        if (chips == 0) chips = 1000
    }

    private fun handValue(hand: List<BjCard>): Int {
        var total = 0
        var aces = 0
        for (card in hand) {
            total += card.value
            if (card.rank == "A") aces++
        }
        while (total > 21 && aces > 0) { total -= 10; aces-- }
        return total
    }
}

@Composable
fun BlackjackView(onBack: () -> Unit = {}) {
    val vm: BlackjackViewModel = viewModel()

    // Dealer AI
    LaunchedEffect(vm.phase) {
        if (vm.phase == BjPhase.DEALER_TURN && vm.dealerThinking) {
            delay(700)
            while (vm.dealerPlayStep()) {
                delay(700)
            }
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0F3D24))
    ) {
        val screenWidth = maxWidth
        val cardWidth = screenWidth / 7
        val cardHeight = cardWidth * 1.4f

        Column(
            modifier = Modifier.fillMaxSize().padding(16.dp)
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = Color.White)
                }
                Text("BLACKJACK", color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Color.Black.copy(alpha = 0.3f))
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                ) {
                    Text("💰", fontSize = 16.sp)
                    Text("${vm.chips}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Dealer
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("DEALER", color = Color.White.copy(alpha = 0.5f), fontSize = 11.sp)
                    if (vm.dealerThinking) {
                        Spacer(modifier = Modifier.width(8.dp))
                        CircularProgressIndicator(modifier = Modifier.size(12.dp), color = Color.White.copy(alpha = 0.5f), strokeWidth = 1.5.dp)
                    }
                }
                HandView(vm.dealerHand, if (vm.phase != BjPhase.PLAYER_TURN) vm.dealerValue else null, cardWidth, cardHeight)
            }

            // Center info
            Box(modifier = Modifier.fillMaxWidth().height(40.dp), contentAlignment = Alignment.Center) {
                if (vm.outcome.isNotEmpty()) {
                    Text(vm.outcome, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                        color = when {
                            vm.outcome.contains("Win") -> Color(0xFF4CAF50)
                            vm.outcome.contains("Dealer") -> Color.Red
                            else -> Color(0xFFFFEB3B)
                        })
                }
                if (vm.bet > 0 && vm.phase != BjPhase.RESULT) {
                    Text("Bet: ${vm.bet}", color = Color(0xFFFFEB3B).copy(alpha = 0.9f), fontSize = 14.sp)
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Player
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                HandView(vm.playerHand, if (vm.playerHand.isNotEmpty()) vm.playerValue else null, cardWidth, cardHeight)
                Text("YOU", color = Color.White.copy(alpha = 0.5f), fontSize = 11.sp)
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Actions
            when (vm.phase) {
                BjPhase.BETTING -> {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            vm.betOptions.forEach { amount ->
                                Button(
                                    onClick = { vm.placeBet(amount) },
                                    modifier = Modifier.weight(1f).height(48.dp),
                                    enabled = vm.chips >= amount,
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = when (amount) {
                                            25 -> Color(0xFF999999)
                                            50 -> Color(0xFFB71C1C)
                                            100 -> Color(0xFF1A237E)
                                            else -> Color(0xFF1B5E20)
                                        }
                                    ),
                                    shape = RoundedCornerShape(12.dp),
                                    contentPadding = PaddingValues(0.dp)
                                ) {
                                    Text("+$amount", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                                }
                            }
                        }
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                onClick = { vm.clearBet() },
                                modifier = Modifier.weight(1f).height(48.dp),
                                enabled = vm.bet > 0,
                                colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.1f)),
                                shape = RoundedCornerShape(14.dp)
                            ) { Text("Clear", color = Color.White, fontSize = 14.sp) }
                            Button(
                                onClick = { vm.deal() },
                                modifier = Modifier.weight(1f).height(48.dp),
                                enabled = vm.bet > 0,
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFEB3B)),
                                shape = RoundedCornerShape(14.dp)
                            ) { Text("Deal (${vm.bet})", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 14.sp) }
                        }
                    }
                }
                BjPhase.PLAYER_TURN -> {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        ActionBtn("Hit", "➕") { vm.hit() }
                        ActionBtn("Stand", "✋") { vm.stand() }
                        if (vm.playerHand.size == 2 && vm.chips >= vm.bet) {
                            ActionBtn("Double", "⏫") { vm.doubleDown() }
                        }
                    }
                }
                BjPhase.DEALER_TURN -> {
                    Text("Dealer is playing...", color = Color.White.copy(alpha = 0.6f))
                }
                BjPhase.RESULT -> {
                    Button(
                        onClick = { vm.newRound() },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFFEB3B)),
                        shape = RoundedCornerShape(14.dp)
                    ) {
                        Text("Next Round", color = Color.Black, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                    }
                }
            }
        }
    }
}

@Composable
fun HandView(cards: List<BjCard>, value: Int?, cardWidth: androidx.compose.ui.unit.Dp, cardHeight: androidx.compose.ui.unit.Dp) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.height(cardHeight + 40.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy((-cardWidth.value * 0.5f).dp)) {
            cards.forEach { card ->
                CardView(card, cardWidth, cardHeight)
            }
            if (cards.isEmpty()) {
                Box(
                    modifier = Modifier
                        .size(cardWidth, cardHeight)
                        .clip(RoundedCornerShape(10.dp))
                        .border(1.5.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
                )
            }
        }
        value?.let {
            Text("$it", color = if (it > 21) Color.Red else Color.White.copy(alpha = 0.85f),
                fontSize = 15.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 8.dp).clip(RoundedCornerShape(8.dp))
                    .background(Color.Black.copy(alpha = 0.25f)).padding(horizontal = 10.dp, vertical = 3.dp))
        }
    }
}

@Composable
fun CardView(card: BjCard, width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp) {
    Box(
        modifier = Modifier
            .size(width, height)
            .clip(RoundedCornerShape(8.dp))
            .background(if (card.isFaceDown) Color(0xFF1A237E) else Color.White)
            .border(0.5.dp, Color.Black.copy(alpha = 0.1f), RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center
    ) {
        if (card.isFaceDown) {
            Text("?", color = Color.White.copy(alpha = 0.3f), fontSize = (width.value * 0.4f).sp, fontWeight = FontWeight.Bold)
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(card.rank, fontSize = (width.value * 0.25f).sp, fontWeight = FontWeight.Bold,
                    color = if (card.isRed) Color.Red else Color.Black)
                Text(card.suit, fontSize = (width.value * 0.25f).sp,
                    color = if (card.isRed) Color.Red else Color.Black)
            }
        }
    }
}

@Composable
fun RowScope.ActionBtn(label: String, icon: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.weight(1f).height(60.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.15f)),
        shape = RoundedCornerShape(14.dp)
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(icon, fontSize = 20.sp)
            Text(label, fontSize = 12.sp, color = Color.White)
        }
    }
}