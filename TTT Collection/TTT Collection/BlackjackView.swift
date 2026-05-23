//
//  BlackjackCard.swift
//  TTT Collection
//
//  Created by Philipp on 10.05.26.
//


import SwiftUI
internal import Combine

// MARK: - Card Model

struct BlackjackCard: Identifiable, Equatable {
    let id = UUID()
    let suit: Suit
    let rank: Rank
    var isFaceDown: Bool = false

    enum Suit: String, CaseIterable {
        case spades = "♠", hearts = "♥", diamonds = "♦", clubs = "♣"
        var isRed: Bool { self == .hearts || self == .diamonds }
    }

    enum Rank: String, CaseIterable {
        case two = "2", three = "3", four = "4", five = "5", six = "6"
        case seven = "7", eight = "8", nine = "9", ten = "10"
        case jack = "J", queen = "Q", king = "K", ace = "A"

        var value: Int {
            switch self {
            case .two:   return 2
            case .three: return 3
            case .four:  return 4
            case .five:  return 5
            case .six:   return 6
            case .seven: return 7
            case .eight: return 8
            case .nine:  return 9
            case .ten, .jack, .queen, .king: return 10
            case .ace:   return 11
            }
        }
    }
}

// MARK: - Hand Value

func handValue(_ hand: [BlackjackCard]) -> Int {
    var total = 0
    var aces = 0
    for card in hand where !card.isFaceDown {
        total += card.rank.value
        if card.rank == .ace { aces += 1 }
    }
    while total > 21 && aces > 0 {
        total -= 10
        aces -= 1
    }
    return total
}

// MARK: - Game State

enum BlackjackPhase {
    case betting, playerTurn, dealerTurn, result
}

enum BlackjackOutcome {
    case playerWin, dealerWin, push, blackjack
    var message: String {
        switch self {
        case .playerWin:  return "You Win! 🎉"
        case .dealerWin:  return "Dealer Wins"
        case .push:       return "Push — Tie"
        case .blackjack:  return "Blackjack! 🃏"
        }
    }
    var color: Color {
        switch self {
        case .playerWin, .blackjack: return .green
        case .dealerWin:             return .red
        case .push:                  return .yellow
        }
    }
}

// MARK: - ViewModel

@MainActor
class BlackjackViewModel: ObservableObject {
    @Published var deck: [BlackjackCard] = []
    @Published var playerHand: [BlackjackCard] = []
    @Published var dealerHand: [BlackjackCard] = []
    @Published var phase: BlackjackPhase = .betting
    @Published var chips: Int = 1000
    @Published var bet: Int = 0
    @Published var outcome: BlackjackOutcome? = nil
    @Published var dealerThinking: Bool = false
    @Published var message: String = ""

    let betOptions = [25, 50, 100, 200]

    // MARK: - Setup

    func buildDeck() {
        var d: [BlackjackCard] = []
        for suit in BlackjackCard.Suit.allCases {
            for rank in BlackjackCard.Rank.allCases {
                d.append(BlackjackCard(suit: suit, rank: rank))
            }
        }
        // Use 6 decks
        deck = (d + d + d + d + d + d).shuffled()
    }

    func draw(faceDown: Bool = false) -> BlackjackCard {
        if deck.isEmpty { buildDeck() }
        var card = deck.removeFirst()
        card.isFaceDown = faceDown
        return card
    }
    private let chipsKey = "blackjack_chips"

    init() {
        loadChips()
        buildDeck()
    }

    private func loadChips() {
        chips = UserDefaults.standard.integer(forKey: chipsKey)
        if chips == 0 { chips = 1000 }
    }

    private func saveChips() {
        UserDefaults.standard.set(chips, forKey: chipsKey)
    }

    // Update these functions:
    func placeBet(_ amount: Int) {
        guard chips >= amount else { return }
        bet += amount
        chips -= amount
        saveChips()
    }

    func clearBet() {
        chips += bet
        bet = 0
        saveChips()
    }

    private func settle(playerValue pv: Int, dealerValue dv: Int) {
        if pv > 21 {
            outcome = .dealerWin
            message = "Bust!"
        } else if dv > 21 {
            outcome = .playerWin
            chips += bet * 2
            bet = 0
            message = "Dealer busts!"
            saveChips()
        } else if pv > dv {
            outcome = .playerWin
            chips += bet * 2
            bet = 0
            message = "Higher hand wins!"
            saveChips()
        } else if dv > pv {
            outcome = .dealerWin
            bet = 0
            message = "Dealer has higher hand."
            saveChips()
        } else {
            outcome = .push
            chips += bet
            bet = 0
            message = "Same value — push."
            saveChips()
        }
    }

    private func settleBlackjack() {
        let dv = handValue(dealerHand)
        if dv == 21 && dealerHand.count == 2 {
            outcome = .push
            chips += bet
            bet = 0
            message = "Both Blackjack — push."
        } else {
            outcome = .blackjack
            chips += Int(Double(bet) * 2.5)
            bet = 0
            message = "Natural Blackjack!"
        }
        saveChips()
    }

    func deal() {
        guard phase == .betting, bet > 0 else { return }
        if deck.count < 10 { buildDeck() }
        playerHand = [draw(), draw()]
        dealerHand = [draw(), draw(faceDown: true)]
        outcome = nil
        message = ""
        let pv = handValue(playerHand)
        if pv == 21 {
            dealerHand[1].isFaceDown = false
            settleBlackjack()
            phase = .result
        } else {
            phase = .playerTurn
        }
    }

    func hit() {
        guard phase == .playerTurn else { return }
        playerHand.append(draw())
        let pv = handValue(playerHand)
        if pv > 21 {
            dealerHand[1].isFaceDown = false
            outcome = .dealerWin
            message = "Bust!"
            bet = 0
            saveChips()
            phase = .result
        } else if pv == 21 {
            stand()
        }
    }

    func stand() {
        guard phase == .playerTurn else { return }
        dealerHand[1].isFaceDown = false
        phase = .dealerTurn
        runDealerTurn()
    }

    func doubleDown() {
        guard phase == .playerTurn, playerHand.count == 2, chips >= bet else { return }
        chips -= bet
        bet *= 2
        saveChips()
        playerHand.append(draw())
        let pv = handValue(playerHand)
        if pv > 21 {
            dealerHand[1].isFaceDown = false
            outcome = .dealerWin
            message = "Bust!"
            bet = 0
            saveChips()
            phase = .result
        } else {
            stand()
        }
    }

    private func runDealerTurn() {
        dealerThinking = true
        func drawNext() {
            let dv = handValue(dealerHand)
            if dv < 17 {
                dealerHand.append(draw())
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { drawNext() }
            } else {
                let pv = handValue(playerHand)
                settle(playerValue: pv, dealerValue: dv)
                dealerThinking = false
                phase = .result
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { drawNext() }
    }

    func newRound() {
        playerHand = []
        dealerHand = []
        bet = 0
        outcome = nil
        message = ""
        phase = .betting
        if chips == 0 {
            chips = 1000
            saveChips()
        }
    }
}

// MARK: - Main View

struct BlackjackView: View {
    @StateObject private var vm = BlackjackViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Felt background
            feltBackground

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                dealerArea
                Spacer(minLength: 0)
                centerInfo
                Spacer(minLength: 0)
                playerArea
                Spacer(minLength: 8)
                actionBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear { vm.buildDeck() }
        .navigationBarHidden(true)
    }

    // MARK: - Background

    private var feltBackground: some View {
        ZStack {
            Color(red: 0.06, green: 0.28, blue: 0.14)
                .ignoresSafeArea()
            // subtle felt texture via radial overlays
            RadialGradient(colors: [Color.white.opacity(0.03), Color.clear],
                           center: .center, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()
            // decorative oval
            Ellipse()
                .stroke(Color.white.opacity(0.08), lineWidth: 2)
                .padding(.horizontal, 24)
                .padding(.vertical, 80)
                .ignoresSafeArea()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            Spacer()
            Text("BLACKJACK")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .kerning(3)
            Spacer()
            chipsDisplay
        }
        .padding(.top, 8)
    }

    private var chipsDisplay: some View {
        HStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 16))
            Text("\(vm.chips)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
        .cornerRadius(20)
    }

    // MARK: - Dealer Area

    private var dealerArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("DEALER")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .kerning(2)
                if vm.dealerThinking {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white.opacity(0.5))
                }
            }
            handView(cards: vm.dealerHand,
                     value: vm.phase != .playerTurn ? handValue(vm.dealerHand) : nil,
                     showValue: vm.phase != .playerTurn && !vm.dealerHand.isEmpty)
        }
    }

    // MARK: - Center Info

    private var centerInfo: some View {
        VStack(spacing: 6) {
            if let outcome = vm.outcome {
                Text(outcome.message)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(outcome.color)
                    .shadow(color: outcome.color.opacity(0.5), radius: 8)
                    .transition(.scale.combined(with: .opacity))
            }
            if !vm.message.isEmpty {
                Text(vm.message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            // Bet indicator
            if vm.bet > 0 && vm.phase != .result {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.yellow.opacity(0.8))
                    Text("Bet: \(vm.bet)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow.opacity(0.9))
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color.black.opacity(0.25))
                .cornerRadius(12)
            }
        }
        .frame(minHeight: 64)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.outcome)
    }

    // MARK: - Player Area

    private var playerArea: some View {
        VStack(spacing: 8) {
            handView(cards: vm.playerHand,
                     value: handValue(vm.playerHand),
                     showValue: !vm.playerHand.isEmpty)
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("YOU")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .kerning(2)
            }
        }
    }

    // MARK: - Hand View

    private func handView(cards: [BlackjackCard], value: Int?, showValue: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if cards.isEmpty {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .frame(width: 56, height: 80)
                        .opacity(0.5)
                } else {
                    HStack(spacing: -28) {
                        ForEach(cards) { card in
                            CardView(card: card)
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: cards.count)
                }
            }
            .frame(minHeight: 84)

            if showValue, let v = value {
                Text("\(v)")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(v > 21 ? .red : (v == 21 ? .yellow : .white.opacity(0.85)))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        Group {
            switch vm.phase {
            case .betting:
                bettingActions
            case .playerTurn:
                playerActions
            case .dealerTurn:
                dealingIndicator
            case .result:
                resultActions
            }
        }
        .padding(.bottom, 12)
    }

    private var bettingActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(vm.betOptions, id: \.self) { amount in
                    Button {
                        withAnimation { vm.placeBet(amount) }
                    } label: {
                        Text("+\(amount)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(chipColor(amount))
                            .cornerRadius(12)
                            .shadow(color: chipColor(amount).opacity(0.4), radius: 4, y: 2)
                    }
                    .disabled(vm.chips < amount)
                    .opacity(vm.chips < amount ? 0.4 : 1)
                }
                
                // ALL-IN button
                Button {
                    withAnimation {
                        vm.placeBet(vm.chips)
                    }
                } label: {
                    Text("ALL IN")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.purple)
                        .cornerRadius(12)
                        .shadow(color: Color.purple.opacity(0.4), radius: 4, y: 2)
                }
                .disabled(vm.chips == 0)
                .opacity(vm.chips == 0 ? 0.4 : 1)
            }
            
            HStack(spacing: 12) {
                Button {
                    withAnimation { vm.clearBet() }
                } label: {
                    Text("Clear")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(14)
                }
                .disabled(vm.bet == 0)
                .opacity(vm.bet == 0 ? 0.4 : 1)

                Button {
                    withAnimation { vm.deal() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Deal  (Bet: \(vm.bet))")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.bet > 0 ? Color.yellow : Color.yellow.opacity(0.4))
                    .cornerRadius(14)
                    .shadow(color: Color.yellow.opacity(0.3), radius: 6, y: 3)
                }
                .disabled(vm.bet == 0)
            }
        }
    }

    private var playerActions: some View {
        HStack(spacing: 10) {
            actionBtn("Hit", icon: "plus.circle.fill", color: .white.opacity(0.15)) { vm.hit() }
            actionBtn("Stand", icon: "hand.raised.fill", color: Color(red: 0.8, green: 0.1, blue: 0.1).opacity(0.8)) { vm.stand() }
            if vm.playerHand.count == 2 && vm.chips >= vm.bet {
                actionBtn("Double", icon: "arrow.up.circle.fill", color: Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.8)) { vm.doubleDown() }
            }
        }
    }

    private var dealingIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white.opacity(0.7))
            Text("Dealer is playing…")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var resultActions: some View {
        Button {
            withAnimation { vm.newRound() }
        } label: {
            Label("Next Round", systemImage: "arrow.clockwise")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.yellow)
                .cornerRadius(14)
                .shadow(color: Color.yellow.opacity(0.35), radius: 8, y: 4)
        }
    }

    // MARK: - Helpers

    private func actionBtn(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color)
            .cornerRadius(14)
        }
    }

    private func chipColor(_ amount: Int) -> Color {
        switch amount {
        case 25:  return Color(red: 0.6, green: 0.6, blue: 0.6)
        case 50:  return Color(red: 0.7, green: 0.1, blue: 0.1)
        case 100: return Color(red: 0.1, green: 0.2, blue: 0.7)
        default:  return Color(red: 0.1, green: 0.5, blue: 0.1)
        }
    }
}

// MARK: - Card View

struct CardView: View {
    let card: BlackjackCard

    var body: some View {
        ZStack {
            if card.isFaceDown {
                faceDownCard
            } else {
                faceUpCard
            }
        }
        .frame(width: 56, height: 80)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var faceDownCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.45))
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                .padding(3)
            Image(systemName: "questionmark")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    private var faceUpCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
            VStack {
                HStack {
                    cardLabel(size: 13)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    cardLabel(size: 13)
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(4)
            Text(card.suit.rawValue)
                .font(.system(size: 20))
                .foregroundColor(card.suit.isRed ? .red : .black)
        }
    }

    private func cardLabel(size: CGFloat) -> some View {
        VStack(spacing: -2) {
            Text(card.rank.rawValue)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundColor(card.suit.isRed ? .red : .black)
            Text(card.suit.rawValue)
                .font(.system(size: size - 2))
                .foregroundColor(card.suit.isRed ? .red : .black)
        }
    }
}

#Preview {
    BlackjackView()
}
