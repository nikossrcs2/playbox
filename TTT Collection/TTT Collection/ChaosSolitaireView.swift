import SwiftUI
internal import Combine

// MARK: - Chaos Solitaire Models

// Extended rank supporting values from -30 to 15 (cursed cards)
private enum ChaosRank: Int, CaseIterable, Comparable {
    case negThirty = -30, negTwentyNine = -29, negTwentyEight = -28
    case negTwentySeven = -27, negTwentySix = -26, negTwentyFive = -25
    case negTwentyFour = -24, negTwentyThree = -23, negTwentyTwo = -22
    case negTwentyOne = -21, negTwenty = -20, negNineteen = -19
    case negEighteen = -18, negSeventeen = -17, negSixteen = -16
    case negFifteen = -15, negFourteen = -14, negThirteen = -13
    case negTwelve = -12, negEleven = -11, negTen = -10
    case negNine = -9, negEight = -8, negSeven = -7
    case negSix = -6, negFive = -5, negFour = -4
    case negThree = -3, negTwo = -2, negOne = -1
    case zero = 0
    case ace = 1, two, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king
    case fourteen = 14, fifteen = 15

    static func < (lhs: ChaosRank, rhs: ChaosRank) -> Bool { lhs.rawValue < rhs.rawValue }

    var display: String {
        switch self {
        case .ace:      return "A"
        case .jack:     return "J"
        case .queen:    return "Q"
        case .king:     return "K"
        case .fourteen: return "X"
        case .fifteen:  return "Ω"
        case .zero:     return "0"
        default:        return "\(rawValue)"
        }
    }

    var isCursed: Bool { rawValue < 1 || rawValue > 13 }

    static var standardRanks: [ChaosRank] {
        [.ace, .two, .three, .four, .five, .six, .seven,
         .eight, .nine, .ten, .jack, .queen, .king]
    }

    static var cursedRanks: [ChaosRank] {
        [.negThirty, .negTwentyNine, .negTwentyEight, .negTwentySeven, .negTwentySix,
         .negTwentyFive, .negTwentyFour, .negTwentyThree, .negTwentyTwo, .negTwentyOne,
         .negTwenty, .negNineteen, .negEighteen, .negSeventeen, .negSixteen,
         .negFifteen, .negFourteen, .negThirteen, .negTwelve, .negEleven, .negTen,
         .negNine, .negEight, .negSeven, .negSix, .negFive, .negFour,
         .negThree, .negTwo, .negOne, .zero, .fourteen, .fifteen]
    }
}

private enum ChaosSuit: String, CaseIterable {
    case spades = "♠", hearts = "♥", diamonds = "♦", clubs = "♣"
    case voidSuit = "✦", cursedHeart = "💀"

    var isRed: Bool { self == .hearts || self == .diamonds || self == .cursedHeart }
    var isCursed: Bool { self == .voidSuit || self == .cursedHeart }

    static var standardSuits: [ChaosSuit] { [.spades, .hearts, .diamonds, .clubs] }
    static var cursedSuits:   [ChaosSuit] { [.voidSuit, .cursedHeart] }

    // First rank that goes on the foundation for this suit
    var foundationStartRank: Int { isCursed ? -30 : 1 }

    // Total cards expected on a completed foundation pile
    var foundationSize: Int { isCursed ? 46 : 13 }  // -30..15 = 46 values, A..K = 13
}

private struct ChaosCard: Identifiable, Equatable {
    let id = UUID()
    let suit: ChaosSuit
    let rank: ChaosRank
    var isFaceUp: Bool = false
    var isRed: Bool { suit.isRed }
    var isCursed: Bool { suit.isCursed || rank.isCursed }
    var displayText: String { rank.display }
    var suitText: String { suit.rawValue }
}

private enum ChaosSrc: Equatable {
    case waste
    case tableau(col: Int, fromIdx: Int)
    case foundation(idx: Int)
}

private struct ChaosSelection: Equatable {
    var source: ChaosSrc
    var cards: [ChaosCard]
}

private struct ChaosSnapshot {
    let stock: [ChaosCard]
    let waste: [ChaosCard]
    let foundations: [[ChaosCard]]
    let tableau: [[ChaosCard]]
    let moves: Int
}

// MARK: - Chaos Game Logic

private class ChaosGame: ObservableObject {
    @Published var stock: [ChaosCard] = []
    @Published var waste: [ChaosCard] = []
    @Published var foundations: [[ChaosCard]] = Array(repeating: [], count: 6)
    @Published var tableau: [[ChaosCard]] = Array(repeating: [], count: 7)
    @Published var moves: Int = 0
    @Published var isWon: Bool = false

    let cursedDeckEnabled: Bool

    private var undoStack: [ChaosSnapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }

    var activeFoundationCount: Int { cursedDeckEnabled ? 6 : 4 }

    private var activeSuits: [ChaosSuit] {
        cursedDeckEnabled
            ? ChaosSuit.standardSuits + ChaosSuit.cursedSuits
            : ChaosSuit.standardSuits
    }

    init(cursed: Bool = false) {
        cursedDeckEnabled = cursed
        newGame()
    }

    private func saveSnapshot() {
        undoStack.append(ChaosSnapshot(
            stock: stock, waste: waste,
            foundations: foundations, tableau: tableau, moves: moves
        ))
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            stock = snap.stock; waste = snap.waste
            foundations = snap.foundations; tableau = snap.tableau
            moves = snap.moves; isWon = false
        }
    }

    func newGame() {
        let suits = activeSuits
        let ranks = cursedDeckEnabled
            ? ChaosRank.standardRanks + ChaosRank.cursedRanks
            : ChaosRank.standardRanks

        var deck = suits.flatMap { suit in
            ranks.map { ChaosCard(suit: suit, rank: $0) }
        }.shuffled()

        tableau = (0..<7).map { col in
            var pile = Array(deck.prefix(col + 1))
            deck.removeFirst(col + 1)
            pile[pile.count - 1].isFaceUp = true
            return pile
        }
        stock = deck.map { var c = $0; c.isFaceUp = false; return c }
        waste = []
        foundations = Array(repeating: [], count: 6)
        moves = 0
        isWon = false
        undoStack = []
    }

    // MARK: - Foundation helpers

    private func foundationIdx(for suit: ChaosSuit) -> Int {
        switch suit {
        case .spades:      return 0
        case .hearts:      return 1
        case .diamonds:    return 2
        case .clubs:       return 3
        case .voidSuit:    return 4
        case .cursedHeart: return 5
        }
    }

    private func suitForFoundationIdx(_ idx: Int) -> ChaosSuit {
        let suits = activeSuits
        return idx < suits.count ? suits[idx] : .spades
    }

    func canPlaceOnFoundation(_ card: ChaosCard, idx: Int) -> Bool {
        guard idx < activeFoundationCount else { return false }
        let pile = foundations[idx]
        let expectedSuit = suitForFoundationIdx(idx)
        guard card.suit == expectedSuit else { return false }
        if pile.isEmpty {
            return card.rank.rawValue == expectedSuit.foundationStartRank
        }
        guard let top = pile.last else { return false }
        return top.rank.rawValue + 1 == card.rank.rawValue
    }

    // MARK: - Tableau helpers

    func canPlaceOnTableau(_ card: ChaosCard, col: Int) -> Bool {
        let pile = tableau[col]
        if pile.isEmpty {
            // Cursed mode: any card on empty; standard: kings only
            return cursedDeckEnabled ? true : card.rank == .king
        }
        guard let top = pile.last, top.isFaceUp else { return false }
        // Cursed cards (cursed suit OR cursed rank) skip the color-alternation rule —
        // they only need to be one rank lower than the top card.
        if card.isCursed || top.isCursed {
            return top.rank.rawValue - 1 == card.rank.rawValue
        }
        return top.isRed != card.isRed && top.rank.rawValue - 1 == card.rank.rawValue
    }

    private func flipTopCard(col: Int) {
        guard !tableau[col].isEmpty else { return }
        let i = tableau[col].count - 1
        if !tableau[col][i].isFaceUp { tableau[col][i].isFaceUp = true }
    }

    func flipTopCardPublic(col: Int) {
        guard !tableau[col].isEmpty,
              let last = tableau[col].last, !last.isFaceUp else { return }
        saveSnapshot()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            tableau[col][tableau[col].count - 1].isFaceUp = true
            moves += 1
        }
    }

    // MARK: - Standard moves (animated, with undo snapshot)

    func drawFromStock() {
        saveSnapshot()
        internalDraw()
        moves += 1
    }

    // Internal draw: no snapshot, no move increment — used by auto-solve loops
    private func internalDraw() {
        if stock.isEmpty {
            stock = waste.reversed().map { var c = $0; c.isFaceUp = false; return c }
            waste = []
        } else {
            var card = stock.removeLast()
            card.isFaceUp = true
            waste.append(card)
        }
    }

    @discardableResult func wasteToFoundation() -> Bool {
        guard let card = waste.last, canPlaceOnFoundation(card, idx: foundationIdx(for: card.suit)) else { return false }
        let fi = foundationIdx(for: card.suit)
        saveSnapshot()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            foundations[fi].append(waste.removeLast()); moves += 1; checkWin()
        }
        return true
    }

    @discardableResult func wasteToTableau(col: Int) -> Bool {
        guard let card = waste.last, canPlaceOnTableau(card, col: col) else { return false }
        saveSnapshot()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            tableau[col].append(waste.removeLast()); moves += 1
        }
        return true
    }

    @discardableResult func tableauToFoundation(col: Int) -> Bool {
        guard let card = tableau[col].last, card.isFaceUp else { return false }
        let fi = foundationIdx(for: card.suit)
        guard canPlaceOnFoundation(card, idx: fi) else { return false }
        saveSnapshot()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            foundations[fi].append(tableau[col].removeLast())
            flipTopCard(col: col); moves += 1; checkWin()
        }
        return true
    }

    @discardableResult func tableauToTableau(fromCol: Int, fromIdx: Int, toCol: Int) -> Bool {
        guard fromCol != toCol, fromIdx < tableau[fromCol].count else { return false }
        let card = tableau[fromCol][fromIdx]
        guard card.isFaceUp, canPlaceOnTableau(card, col: toCol) else { return false }
        saveSnapshot()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            let run = Array(tableau[fromCol][fromIdx...])
            tableau[fromCol].removeSubrange(fromIdx...)
            tableau[toCol].append(contentsOf: run)
            flipTopCard(col: fromCol); moves += 1
        }
        return true
    }

    @discardableResult func foundationToTableau(fi: Int, toCol: Int) -> Bool {
        guard let card = foundations[fi].last, canPlaceOnTableau(card, col: toCol) else { return false }
        saveSnapshot()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            tableau[toCol].append(foundations[fi].removeLast()); moves += 1
        }
        return true
    }

    private func checkWin() {
        isWon = (0..<activeFoundationCount).allSatisfy { idx in
            let suit = suitForFoundationIdx(idx)
            return foundations[idx].count == suit.foundationSize
        }
    }

    // MARK: - Auto Move (tap mode)

    @discardableResult func autoMoveWaste() -> Bool {
        if wasteToFoundation() { return true }
        // Prefer non-empty columns first, then empty ones (to avoid wasting empty columns)
        let sorted = (0..<7).sorted { tableau[$0].isEmpty && !tableau[$1].isEmpty ? false : !tableau[$0].isEmpty || tableau[$1].isEmpty }
        for col in sorted { if wasteToTableau(col: col) { return true } }
        return false
    }

    @discardableResult func autoMoveTableau(col: Int, fromIdx: Int) -> Bool {
        // Always try foundation first (any card, not just top)
        if tableauToFoundation(col: col) { return true }
        // Try to move to a non-empty column first (uncovers hidden cards / useful moves)
        for toCol in 0..<7 where toCol != col {
            if !tableau[toCol].isEmpty,
               tableauToTableau(fromCol: col, fromIdx: fromIdx, toCol: toCol) { return true }
        }
        // Then allow moving to empty columns
        for toCol in 0..<7 where toCol != col {
            if tableau[toCol].isEmpty,
               tableauToTableau(fromCol: col, fromIdx: fromIdx, toCol: toCol) { return true }
        }
        return false
    }

    // MARK: - CHEAT MOVES 🃏

    func revealAllCards() {
        saveSnapshot()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            for col in 0..<7 {
                for i in 0..<tableau[col].count { tableau[col][i].isFaceUp = true }
            }
            moves += 1
        }
    }

    /// Draw from stock/waste until a card matching the predicate surfaces on the waste.
    private func drawUntilCondition(_ condition: (ChaosCard) -> Bool) {
        let totalCards = stock.count + waste.count
        guard totalCards > 0 else { return }
        // Check if waste top already matches
        if let top = waste.last, condition(top) { return }
        var drawn = 0
        while drawn < totalCards {
            internalDraw()
            drawn += 1
            if let top = waste.last, condition(top) { break }
        }
    }

    func drawUntilAce() {
        saveSnapshot()
        drawUntilCondition { $0.rank == .ace }
        moves += 1
    }

    func drawUntilRed() {
        saveSnapshot()
        drawUntilCondition { $0.isRed }
        moves += 1
    }

    /// Draw until a card matching the given color and/or rank appears on waste.
    /// Pass nil for either to match any value of that dimension.
    func drawUntil(rank: ChaosRank?, isRed: Bool?) {
        saveSnapshot()
        drawUntilCondition { card in
            let rankOK  = rank  == nil || card.rank == rank!
            let colorOK = isRed == nil || card.isRed == isRed!
            return rankOK && colorOK
        }
        moves += 1
    }

    func shuffleWasteToStock() {
        saveSnapshot()
        stock = (stock + waste).map { var c = $0; c.isFaceUp = false; return c }.shuffled()
        waste = []
        moves += 1
    }

    /// Teleport the next "foundation-startable" card (ace for standard, -30 for cursed) to its foundation.
    func teleportNextFoundationStarter() {
        saveSnapshot()
        // For each foundation that is still empty, find and move its starting card
        for fi in 0..<activeFoundationCount {
            guard foundations[fi].isEmpty else { continue }
            let suit = suitForFoundationIdx(fi)
            let startRank = suit.foundationStartRank

            let matchesStart = { (c: ChaosCard) -> Bool in
                c.suit == suit && c.rank.rawValue == startRank
            }

            // Search waste
            if let idx = waste.indices.reversed().first(where: { matchesStart(waste[$0]) }) {
                foundations[fi].append({ var c = waste[idx]; c.isFaceUp = true; return c }())
                waste.remove(at: idx)
                moves += 1; checkWin(); return
            }
            // Search stock
            if let idx = stock.indices.reversed().first(where: { matchesStart(stock[$0]) }) {
                foundations[fi].append({ var c = stock[idx]; c.isFaceUp = true; return c }())
                stock.remove(at: idx)
                moves += 1; checkWin(); return
            }
            // Search tableau (any position, not just top)
            for col in 0..<7 {
                if let idx = tableau[col].indices.reversed().first(where: { matchesStart(tableau[col][$0]) }) {
                    foundations[fi].append({ var c = tableau[col][idx]; c.isFaceUp = true; return c }())
                    tableau[col].remove(at: idx)
                    flipTopCard(col: col)
                    moves += 1; checkWin(); return
                }
            }
        }
        // Fallback: teleport any card that can legally go to its foundation right now
        for col in 0..<7 {
            if let card = tableau[col].last, card.isFaceUp {
                let fi = foundationIdx(for: card.suit)
                if canPlaceOnFoundation(card, idx: fi) {
                    foundations[fi].append(tableau[col].removeLast())
                    flipTopCard(col: col)
                    moves += 1; checkWin(); return
                }
            }
        }
        if let card = waste.last {
            let fi = foundationIdx(for: card.suit)
            if canPlaceOnFoundation(card, idx: fi) {
                foundations[fi].append(waste.removeLast())
                moves += 1; checkWin()
            }
        }
    }

    /// Teleport ALL cards that can legally go to foundations right now (clears obvious moves instantly).
    func teleportAllPlayable() {
        saveSnapshot()
        var anyMoved = true
        while anyMoved {
            anyMoved = false
            // Tableau tops → foundation
            for col in 0..<7 {
                if let card = tableau[col].last, card.isFaceUp {
                    let fi = foundationIdx(for: card.suit)
                    if canPlaceOnFoundation(card, idx: fi) {
                        foundations[fi].append(tableau[col].removeLast())
                        flipTopCard(col: col)
                        moves += 1; checkWin()
                        anyMoved = true
                    }
                }
            }
            // Waste top → foundation
            if let card = waste.last {
                let fi = foundationIdx(for: card.suit)
                if canPlaceOnFoundation(card, idx: fi) {
                    foundations[fi].append(waste.removeLast())
                    moves += 1; checkWin()
                    anyMoved = true
                }
            }
        }
    }

    /// One pass of auto-solve: repeatedly moves cards to foundations and rearranges
    /// tableau, drawing from stock when stuck. Stops when no progress for a full stock cycle.
    func autoSolve() {
        saveSnapshot()
        var stockDrawsSinceProgress = 0
        let maxIter = 3000
        // Track tableau state hashes to avoid infinite loops between columns
        var seenTableauStates = Set<String>()

        func tableauStateKey() -> String {
            tableau.map { col in
                col.map { "\($0.rank.rawValue)\($0.suit.rawValue)\($0.isFaceUp ? "u" : "d")" }.joined(separator: ",")
            }.joined(separator: "|")
        }

        for _ in 0..<maxIter {
            var madeMove = false

            // Waste → foundation
            if let top = waste.last {
                let fi = foundationIdx(for: top.suit)
                if canPlaceOnFoundation(top, idx: fi) {
                    foundations[fi].append(waste.removeLast())
                    moves += 1; checkWin()
                    madeMove = true; stockDrawsSinceProgress = 0
                }
            }

            // Tableau → foundation (all columns each pass)
            var foundationMoved = true
            while foundationMoved {
                foundationMoved = false
                for col in 0..<7 {
                    if let card = tableau[col].last, card.isFaceUp {
                        let fi = foundationIdx(for: card.suit)
                        if canPlaceOnFoundation(card, idx: fi) {
                            foundations[fi].append(tableau[col].removeLast())
                            flipTopCard(col: col)
                            moves += 1; checkWin()
                            madeMove = true; stockDrawsSinceProgress = 0
                            foundationMoved = true
                        }
                    }
                }
            }

            if isWon { break }

            // Tableau → tableau (prefer moves that uncover hidden cards, avoid loops)
            let stateKey = tableauStateKey()
            if !seenTableauStates.contains(stateKey) {
                seenTableauStates.insert(stateKey)
                outerTT: for fromCol in 0..<7 {
                    guard let fromIdx = tableau[fromCol].indices.first(where: { tableau[fromCol][$0].isFaceUp }) else { continue }
                    let card = tableau[fromCol][fromIdx]
                    let hasHidden = fromIdx > 0 && !tableau[fromCol][fromIdx - 1].isFaceUp
                    // Prioritise moves that reveal hidden cards
                    for toCol in 0..<7 where toCol != fromCol {
                        if !tableau[toCol].isEmpty && canPlaceOnTableau(card, col: toCol) {
                            if hasHidden {
                                let run = Array(tableau[fromCol][fromIdx...])
                                tableau[fromCol].removeSubrange(fromIdx...)
                                flipTopCard(col: fromCol)
                                tableau[toCol].append(contentsOf: run)
                                moves += 1
                                madeMove = true; stockDrawsSinceProgress = 0
                                seenTableauStates.removeAll() // state changed, reset loop detection
                                break outerTT
                            }
                        }
                    }
                    // Then allow moving to empty columns only if it reveals something or moves a king
                    for toCol in 0..<7 where toCol != fromCol {
                        if tableau[toCol].isEmpty && canPlaceOnTableau(card, col: toCol) {
                            let revealsHidden = hasHidden
                            let isKingRun = card.rank == .king && fromIdx == 0
                            // In cursed mode any card can go on empty; only move if we reveal something
                            if revealsHidden || (!cursedDeckEnabled && isKingRun) {
                                let run = Array(tableau[fromCol][fromIdx...])
                                tableau[fromCol].removeSubrange(fromIdx...)
                                flipTopCard(col: fromCol)
                                tableau[toCol].append(contentsOf: run)
                                moves += 1
                                madeMove = true; stockDrawsSinceProgress = 0
                                seenTableauStates.removeAll()
                                break outerTT
                            }
                        }
                    }
                }
            }

            // Waste → tableau
            if !madeMove, let top = waste.last {
                // Non-empty columns first
                for col in 0..<7 where !tableau[col].isEmpty {
                    if canPlaceOnTableau(top, col: col) {
                        tableau[col].append(waste.removeLast())
                        moves += 1
                        madeMove = true; stockDrawsSinceProgress = 0
                        seenTableauStates.removeAll()
                        break
                    }
                }
                // Empty columns only as last resort
                if !madeMove {
                    for col in 0..<7 where tableau[col].isEmpty {
                        if canPlaceOnTableau(top, col: col) {
                            tableau[col].append(waste.removeLast())
                            moves += 1
                            madeMove = true; stockDrawsSinceProgress = 0
                            seenTableauStates.removeAll()
                            break
                        }
                    }
                }
            }

            if isWon { break }

            if !madeMove {
                let total = stock.count + waste.count
                if total == 0 { break }
                if stockDrawsSinceProgress >= total { break }  // full cycle with no progress
                internalDraw()
                moves += 1
                stockDrawsSinceProgress += 1
            }
        }
    }

    func bestHint() -> String {
        // Check for cards that can go to foundations
        if let card = waste.last {
            let fi = foundationIdx(for: card.suit)
            if canPlaceOnFoundation(card, idx: fi) {
                return "Move \(card.displayText)\(card.suitText) from waste → foundation"
            }
        }
        for col in 0..<7 {
            if let card = tableau[col].last, card.isFaceUp {
                let fi = foundationIdx(for: card.suit)
                if canPlaceOnFoundation(card, idx: fi) {
                    return "Move \(card.displayText)\(card.suitText) from col \(col+1) → foundation"
                }
            }
        }
        // Moves that uncover hidden cards
        for fromCol in 0..<7 {
            guard let fi = tableau[fromCol].indices.first(where: { tableau[fromCol][$0].isFaceUp }) else { continue }
            let card = tableau[fromCol][fi]
            let hasHidden = fi > 0 && !tableau[fromCol][fi - 1].isFaceUp
            for toCol in 0..<7 where toCol != fromCol {
                if canPlaceOnTableau(card, col: toCol) && (hasHidden || !tableau[toCol].isEmpty) {
                    if hasHidden {
                        return "Move \(card.displayText)\(card.suitText) col \(fromCol+1) → col \(toCol+1) (reveals hidden)"
                    }
                    return "Move \(card.displayText)\(card.suitText) col \(fromCol+1) → col \(toCol+1)"
                }
            }
        }
        // Any valid tableau move
        for col in 0..<7 {
            if let card = tableau[col].last, card.isFaceUp {
                for toCol in 0..<7 where toCol != col {
                    if canPlaceOnTableau(card, col: toCol) {
                        return "Move \(card.displayText)\(card.suitText) col \(col+1) → col \(toCol+1)"
                    }
                }
            }
        }
        if let top = waste.last {
            for col in 0..<7 {
                if canPlaceOnTableau(top, col: col) {
                    return "Move waste \(top.displayText)\(top.suitText) → col \(col+1)"
                }
            }
        }
        // Check if a foundation starter is stuck in stock/tableau
        for fi in 0..<activeFoundationCount where foundations[fi].isEmpty {
            let suit = suitForFoundationIdx(fi)
            let startRank = suit.foundationStartRank
            let stuck = stock.contains { $0.suit == suit && $0.rank.rawValue == startRank }
                     || tableau.flatMap { $0 }.contains { $0.suit == suit && $0.rank.rawValue == startRank }
            if stuck {
                return "Use Teleport to find \(suit.rawValue)\(startRank == 1 ? "A" : "\(startRank)") for foundation"
            }
        }
        return "Draw from stock"
    }

    func injectCursedCards(count: Int = 5) {
        saveSnapshot()
        let cursedSuits = ChaosSuit.cursedSuits
        let cursedRanks = ChaosRank.cursedRanks
        for _ in 0..<count {
            let suit = cursedSuits.randomElement()!
            let rank = cursedRanks.randomElement()!
            stock.insert(ChaosCard(suit: suit, rank: rank, isFaceUp: false), at: stock.startIndex)
        }
        moves += 1
    }
}

// MARK: - Cheat Menu Sheet

private struct CheatMenuView: View {
    @ObservedObject var game: ChaosGame
    @Binding var hintText: String
    @Environment(\.dismiss) private var dismiss
    private let accent = Color.purple

    // Smart Draw picker state
    // Color: 0 = any, 1 = red, 2 = black
    @State private var drawColor: Int = 0
    // Rank picker — nil means "any"
    @State private var drawRankIndex: Int = 0   // index into rankOptions

    private var rankOptions: [(label: String, rank: ChaosRank?)] {
        var opts: [(String, ChaosRank?)] = [("Any", nil)]
        let standard: [(String, ChaosRank)] = [
            ("A",  .ace), ("2", .two), ("3", .three), ("4", .four),
            ("5",  .five), ("6", .six), ("7", .seven), ("8", .eight),
            ("9",  .nine), ("10", .ten), ("J", .jack), ("Q", .queen), ("K", .king)
        ]
        opts += standard.map { ($0.0, $0.1) }
        if game.cursedDeckEnabled {
            let cursed: [(String, ChaosRank)] = [
                ("0", .zero), ("-1", .negOne), ("-2", .negTwo), ("-3", .negThree),
                ("-4", .negFour), ("-5", .negFive), ("-6", .negSix), ("-7", .negSeven),
                ("-8", .negEight), ("-9", .negNine), ("-10", .negTen),
                ("-15", .negFifteen), ("-20", .negTwenty), ("-30", .negThirty),
                ("X", .fourteen), ("Ω", .fifteen)
            ]
            opts += cursed.map { ($0.0, $0.1) }
        }
        return opts
    }

    private var smartDrawLabel: String {
        let colorPart: String
        switch drawColor {
        case 1: colorPart = "Red"
        case 2: colorPart = "Black"
        default: colorPart = "Any color"
        }
        let rankPart = rankOptions[drawRankIndex].label == "Any"
            ? "any rank"
            : rankOptions[drawRankIndex].label
        return "Draw to \(colorPart), \(rankPart)"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("🎰 Cheat Menu")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                        Text("Absolute power. Zero shame.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    cheatSection("👁 Reveal", color: .blue) {
                        cheatButton("Reveal All Hidden Cards", icon: "eye.fill", color: .blue) {
                            game.revealAllCards(); dismiss()
                        }
                        cheatButton("Show Hint", icon: "lightbulb.fill", color: .yellow) {
                            hintText = game.bestHint(); dismiss()
                        }
                    }

                    // MARK: Smart Draw — inline pickers
                    smartDrawSection

                    cheatSection("✨ Teleport", color: .purple) {
                        cheatButton(
                            game.cursedDeckEnabled
                                ? "Teleport Next -30 Card to Foundation"
                                : "Teleport Next Ace to Foundation",
                            icon: "arrow.up.to.line.circle.fill", color: .purple
                        ) {
                            game.teleportNextFoundationStarter(); dismiss()
                        }
                        cheatButton("Teleport All Playable Cards", icon: "arrow.up.to.line.compact", color: .purple) {
                            game.teleportAllPlayable(); dismiss()
                        }
                        cheatButton("Auto-Solve (One Pass)", icon: "wand.and.sparkles", color: .indigo) {
                            game.autoSolve(); dismiss()
                        }
                    }

                    if game.cursedDeckEnabled {
                        cheatSection("☠️ Inject Chaos", color: .red) {
                            cheatButton("Inject 5 Cursed Cards into Stock", icon: "bolt.fill", color: .red) {
                                game.injectCursedCards(count: 5); dismiss()
                            }
                            cheatButton("Inject 15 Cursed Cards", icon: "bolt.slash.fill", color: .pink) {
                                game.injectCursedCards(count: 15); dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(accent)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Smart Draw section

    private var smartDrawSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("📤 Smart Draw")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.orange)
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 14) {

                // Color picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Color")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    HStack(spacing: 8) {
                        colorChip(label: "Any",      value: 0, activeColor: .gray)
                        colorChip(label: "♥♦ Red",   value: 1, activeColor: .red)
                        colorChip(label: "♠♣ Black",  value: 2, activeColor: Color(.label))
                    }
                }

                // Rank picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rank")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(rankOptions.enumerated()), id: \.offset) { idx, opt in
                                Button { drawRankIndex = idx } label: {
                                    Text(opt.label)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(drawRankIndex == idx ? .white : .primary)
                                        .frame(minWidth: 36)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 8)
                                        .background(drawRankIndex == idx ? Color.orange : Color(.tertiarySystemGroupedBackground))
                                        .cornerRadius(9)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // Draw button — shows exactly what it will do
                Button {
                    let selectedRank  = rankOptions[drawRankIndex].rank
                    let selectedColor: Bool? = drawColor == 1 ? true : drawColor == 2 ? false : nil
                    game.drawUntil(rank: selectedRank, isRed: selectedColor)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.orange.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: "arrow.down.to.line.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(smartDrawLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Cycles through stock until match")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Shuffle shortcut
                Button {
                    game.shuffleWasteToStock(); dismiss()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.mint.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: "shuffle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.mint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shuffle Waste into Stock")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Randomises draw order")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
        }
    }

    private func colorChip(label: String, value: Int, activeColor: Color) -> some View {
        Button { drawColor = value } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(drawColor == value ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(drawColor == value ? activeColor : Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func cheatSection<Content: View>(_ title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .textCase(.uppercase)
                .padding(.leading, 4)
            VStack(spacing: 8) { content() }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
        }
    }

    private func cheatButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mode Selection

struct ChaosSolitaireView: View {
    @State private var mode: SolitaireGameMode = .menu

    enum SolitaireGameMode { case menu, normal, cursed, tutorial }

    var body: some View {
        switch mode {
        case .menu:     modeMenu
        case .normal:   ChaosGameView(cursed: false, backToMenu: { mode = .menu })
        case .cursed:   ChaosGameView(cursed: true,  backToMenu: { mode = .menu })
        case .tutorial: ChaosTutorialView(backToMenu: { mode = .menu })
        }
    }

    private var modeMenu: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("🃏").font(.system(size: 56))
                        Text("Chaos Solitaire")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text("Klondike, but completely unfair")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.top, 24)

                    modeCard(
                        title: "Cheat Mode",
                        subtitle: "Standard Klondike with a full cheat menu.\nReveal cards, skip to aces, auto-solve.",
                        icon: "🕵️", color: .indigo,
                        action: { mode = .normal }
                    )
                    modeCard(
                        title: "Cursed Mode",
                        subtitle: "Cursed cards: 💀15, ✦ suits, ranks from -30.\nFoundations run -30 all the way to 15.\nInject chaos mid-game. Truly broken.",
                        icon: "☠️", color: .red,
                        action: { mode = .cursed }
                    )
                    modeCard(
                        title: "How to Play",
                        subtitle: "New to Chaos Solitaire? Learn the rules, cursed cards, foundations, and cheat menu step by step.",
                        icon: "📖", color: .teal,
                        action: { mode = .tutorial }
                    )
                }
                .padding(.horizontal, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chaos Solitaire")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private func modeCard(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Text(icon).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color).padding(.top, 4)
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.3), lineWidth: 1.5))
            .cornerRadius(20)
        }
        .buttonStyle(ChaosCardButtonStyle())
    }
}

// MARK: - Main Game View

private struct ChaosGameView: View {
    let cursed: Bool
    let backToMenu: () -> Void

    @StateObject private var game: ChaosGame
    @AppStorage("solitaireTapMode") private var tapMode: String = "tap"
    @State private var selection: ChaosSelection? = nil
    @State private var winCelebration = false
    @State private var showCheatMenu = false
    @State private var hintText: String = ""
    @State private var showHint = false
    @State private var autoPlaying = false
    @State private var autoPlayTimer: Timer? = nil
    @State private var stockDrawsSinceMove = 0

    private let cardCorner: CGFloat = 7
    private var accent: Color { cursed ? .red : .indigo }
    private var cheatColor: Color { cursed ? .orange : .purple }

    init(cursed: Bool, backToMenu: @escaping () -> Void) {
        self.cursed = cursed
        self.backToMenu = backToMenu
        _game = StateObject(wrappedValue: ChaosGame(cursed: cursed))
    }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let hPad: CGFloat = 8
                let spacing: CGFloat = 3
                // Always 7 tableau columns; foundations overflow handled by scrolling top row
                let colW = (geo.size.width - hPad * 2 - spacing * 6) / 7
                let cardH = colW * 1.45

                ZStack {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                        .onTapGesture { selection = nil }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            topRow(colW: colW, cardH: cardH)
                                .padding(.horizontal, hPad)
                                .padding(.top, 6)

                            tableauArea(colW: colW, cardH: cardH, hPad: hPad, spacing: spacing)
                                .padding(.horizontal, hPad)
                                .padding(.bottom, 24)
                        }
                    }

                    if showHint && !hintText.isEmpty {
                        VStack {
                            hintBanner.padding(.top, 8)
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if selection != nil && tapMode == "tap" {
                        VStack {
                            Spacer()
                            selectionBanner.padding(.bottom, 12)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if game.isWon { winOverlay }
                }
            }
            .navigationTitle(cursed ? "☠️ Cursed Solitaire" : "🕵️ Cheat Solitaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showCheatMenu) {
            CheatMenuView(game: game, hintText: $hintText)
        }
        .onChange(of: hintText) { val in
            guard !val.isEmpty else { return }
            withAnimation { showHint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showHint = false; hintText = "" }
            }
        }
        .onChange(of: game.isWon) { won in if won { winCelebration = false; stopAutoPlay() } }
    }

    // MARK: - Auto Play (timer-based, mirrors SolitaireView)

    private func toggleAutoPlay() {
        if autoPlaying { stopAutoPlay() } else { startAutoPlay() }
    }

    private func startAutoPlay() {
        autoPlaying = true
        selection = nil
        stockDrawsSinceMove = 0
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if !performBestAutoMove() { stopAutoPlay() }
        }
    }

    private func stopAutoPlay() {
        autoPlaying = false
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
    }

    /// Performs one best move per tick. Returns false when stuck (stops the timer).
    private func performBestAutoMove() -> Bool {
        stockDrawsSinceMove = 0

        // 1. Waste → foundation
        if game.wasteToFoundation() { return true }

        // 2. Tableau → foundation
        for col in 0..<7 { if game.tableauToFoundation(col: col) { return true } }

        // 3. Tableau → tableau (prefer uncovering hidden cards)
        for fromCol in 0..<7 {
            let cards = game.tableau[fromCol]
            guard let fromIdx = cards.indices.first(where: { cards[$0].isFaceUp }) else { continue }
            let card = cards[fromIdx]
            let hasHidden = fromIdx > 0 && !cards[fromIdx - 1].isFaceUp
            for toCol in 0..<7 where toCol != fromCol {
                if game.tableau[toCol].isEmpty { continue } // skip empty cols unless revealing
                if game.tableauToTableau(fromCol: fromCol, fromIdx: fromIdx, toCol: toCol) { return true }
            }
            // Allow empty column only if it reveals hidden cards
            if hasHidden {
                for toCol in 0..<7 where toCol != fromCol {
                    if game.tableau[toCol].isEmpty,
                       game.tableauToTableau(fromCol: fromCol, fromIdx: fromIdx, toCol: toCol) { return true }
                }
            }
        }

        // 4. Waste → tableau
        if let top = game.waste.last {
            for col in 0..<7 where !game.tableau[col].isEmpty {
                if game.wasteToTableau(col: col) { return true }
            }
        }

        // 5. Draw from stock
        let stockSize = game.stock.count + game.waste.count
        if stockSize > 0 {
            if stockDrawsSinceMove >= stockSize { return false }
            game.drawFromStock()
            stockDrawsSinceMove += 1
            return true
        }

        return false
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { backToMenu() } label: {
                Image(systemName: "house.fill").foregroundColor(accent)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                Text("\(game.moves)")
                    .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                Button { showCheatMenu = true } label: {
                    ZStack {
                        Circle().fill(cheatColor.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(cheatColor)
                    }
                }
                Button {
                    toggleAutoPlay()
                } label: {
                    Image(systemName: autoPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(autoPlaying ? .orange : accent)
                }
                Button {
                    withAnimation { game.undo(); selection = nil }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(game.canUndo ? accent : .secondary.opacity(0.4))
                }
                .disabled(!game.canUndo)
                Button {
                    withAnimation { game.newGame(); selection = nil; stopAutoPlay() }
                } label: {
                    Image(systemName: "arrow.counterclockwise").foregroundColor(accent)
                }
            }
        }
    }

    // MARK: - Hint Banner

    private var hintBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
            Text(hintText)
                .font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(2)
            Spacer()
            Button { withAnimation { showHint = false; hintText = "" } } label: {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding(.horizontal, 12)
    }

    // MARK: - Selection Banner

    private var selectionBanner: some View {
        HStack {
            if let sel = selection {
                let label = sel.cards.count == 1
                    ? "\(sel.cards[0].displayText)\(sel.cards[0].suitText) selected"
                    : "\(sel.cards.count) cards selected"
                Text(label)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Button("Cancel") { selection = nil }
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(accent).cornerRadius(9)
        .padding(.horizontal, 10)
    }

    // MARK: - Top Row
    // Stock + Waste on left; foundations scroll horizontally on right (handles 6 in cursed mode)

    private func topRow(colW: CGFloat, cardH: CGFloat) -> some View {
        HStack(spacing: 3) {
            // Stock
            Button { game.drawFromStock(); selection = nil } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: cardCorner)
                        .fill(game.stock.isEmpty
                              ? Color(.secondarySystemGroupedBackground)
                              : accent.opacity(0.85))
                    if game.stock.isEmpty {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.secondary).font(.system(size: 14))
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundColor(.white).font(.system(size: 13))
                            Text("\(game.stock.count)")
                                .font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
            .frame(width: colW, height: cardH)

            wasteSlot(colW: colW, cardH: cardH)

            Spacer(minLength: 3)

            // Foundations — scrollable so 6 cursed piles fit without shrinking tableau
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(0..<game.activeFoundationCount, id: \.self) { fi in
                        foundationSlot(fi: fi, colW: colW, cardH: cardH)
                    }
                }
            }
            .frame(width: colW * CGFloat(min(game.activeFoundationCount, 5)) + 3 * CGFloat(min(game.activeFoundationCount, 5) - 1))
        }
    }

    private func wasteSlot(colW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(Color(.secondarySystemGroupedBackground))
            if let top = game.waste.last {
                let isSel = selection?.source == .waste
                cardFace(top, w: colW, h: cardH, isSelected: isSel)
                    .onTapGesture { handleWasteTap(card: top) }
            } else {
                Text("—").foregroundColor(Color(.tertiaryLabel)).font(.system(size: 14))
            }
        }
        .frame(width: colW, height: cardH)
    }

    private func handleWasteTap(card: ChaosCard) {
        if tapMode == "auto" { game.autoMoveWaste(); return }
        if selection != nil { selection = nil; return }
        if !game.wasteToFoundation() {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selection = ChaosSelection(source: .waste, cards: [card])
            }
        }
    }

    private func foundationSlot(fi: Int, colW: CGFloat, cardH: CGFloat) -> some View {
        let suits = cursed ? ChaosSuit.standardSuits + ChaosSuit.cursedSuits : ChaosSuit.standardSuits
        let suit = fi < suits.count ? suits[fi] : ChaosSuit.spades
        let pile = game.foundations[fi]
        let isSel: Bool = {
            if case .foundation(let s) = selection?.source { return s == fi }
            return false
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: cardCorner)
                .strokeBorder(suit.isCursed ? Color.red.opacity(0.5) : accent.opacity(0.35), lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: cardCorner)
                    .fill(suit.isCursed ? Color.red.opacity(0.05) : Color(.secondarySystemGroupedBackground)))
            if let top = pile.last {
                cardFace(top, w: colW, h: cardH, isSelected: isSel)
            } else {
                Text(suit.rawValue)
                    .font(.system(size: suit.isCursed ? 12 : 14))
                    .foregroundColor(suit.isRed ? .red.opacity(0.4) : Color(.tertiaryLabel))
            }
        }
        .frame(width: colW, height: cardH)
        .onTapGesture { handleFoundationTap(fi: fi) }
    }

    private func handleFoundationTap(fi: Int) {
        if tapMode == "auto" { return }
        guard let sel = selection else { return }
        switch sel.source {
        case .waste:             game.wasteToFoundation()
        case .tableau(let c, _): game.tableauToFoundation(col: c)
        case .foundation:        break
        }
        selection = nil
    }

    // MARK: - Tableau

    private func tableauArea(colW: CGFloat, cardH: CGFloat, hPad: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<7, id: \.self) { col in
                tableauColumn(col: col, colW: colW, cardH: cardH)
            }
        }
    }

    private func tableauColumn(col: Int, colW: CGFloat, cardH: CGFloat) -> some View {
        let cards = game.tableau[col]
        let fdOff: CGFloat = cardH * 0.13
        let fuOff: CGFloat = cardH * (cursed ? 0.20 : 0.25)

        var totalH: CGFloat = cardH
        for i in 0..<cards.count {
            if i < cards.count - 1 { totalH += cards[i].isFaceUp ? fuOff : fdOff }
        }

        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cardCorner)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                .frame(width: colW, height: cardH)
                .contentShape(Rectangle())
                .onTapGesture { tryDropOnTableau(col: col) }
            Color.clear.frame(width: colW, height: totalH)

            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                let yOff: CGFloat = {
                    var y: CGFloat = 0
                    for i in 0..<idx { y += cards[i].isFaceUp ? fuOff : fdOff }
                    return y
                }()
                let isSelHighlight: Bool = {
                    if case .tableau(let c, let si) = selection?.source { return c == col && idx >= si }
                    return false
                }()
                let isTopCard = idx == cards.count - 1

                Group {
                    if card.isFaceUp {
                        cardFace(card, w: colW, h: cardH, isSelected: isSelHighlight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if tapMode == "auto" || isTopCard {
                                    handleTableauCardTap(col: col, idx: idx)
                                }
                            }
                    } else {
                        cardBack(w: colW, h: cardH)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Tapping the top face-down card flips it
                                if isTopCard { game.flipTopCardPublic(col: col) }
                            }
                    }
                }
                .offset(y: yOff)
                .zIndex(Double(idx))
            }
        }
        .frame(width: colW, height: max(totalH, cardH))
        .contentShape(Rectangle())
        .onTapGesture { tryDropOnTableau(col: col) }
    }

    private func handleTableauCardTap(col: Int, idx: Int) {
        let cards = game.tableau[col]
        guard idx < cards.count, cards[idx].isFaceUp else { return }
        if tapMode == "auto" {
            game.autoMoveTableau(col: col, fromIdx: idx)
            return
        }
        if selection != nil {
            if tryDropOnTableau(col: col) { return }
        }
        let run = Array(cards[idx...])
        guard run.allSatisfy({ $0.isFaceUp }) else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            selection = ChaosSelection(source: .tableau(col: col, fromIdx: idx), cards: run)
        }
    }

    @discardableResult
    private func tryDropOnTableau(col: Int) -> Bool {
        guard let sel = selection else { return false }
        var moved = false
        switch sel.source {
        case .waste:                   moved = game.wasteToTableau(col: col)
        case .tableau(let fc, let fi): moved = game.tableauToTableau(fromCol: fc, fromIdx: fi, toCol: col)
        case .foundation(let fi):      moved = game.foundationToTableau(fi: fi, toCol: col)
        }
        if moved { withAnimation { selection = nil } }
        return moved
    }

    // MARK: - Card Views

    private func cardFace(_ card: ChaosCard, w: CGFloat, h: CGFloat, isSelected: Bool) -> some View {
        let isCardCursed = card.isCursed
        let bg: Color = isCardCursed
            ? Color(red: 0.18, green: 0.03, blue: 0.03)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
        let textColor: Color = isCardCursed
            ? (card.suit == .cursedHeart ? Color.pink : Color(red: 0.8, green: 0.4, blue: 1.0))
            : (card.isRed ? .red : Color(red: 0.08, green: 0.08, blue: 0.10))
        let borderColor: Color = isSelected
            ? .yellow
            : (isCardCursed ? Color.purple.opacity(0.7) : Color.clear)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(bg)
                .shadow(color: .black.opacity(isCardCursed ? 0.3 : 0.14), radius: 2, x: 0, y: 1)
                .overlay(RoundedRectangle(cornerRadius: cardCorner)
                    .strokeBorder(borderColor, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 0) {
                Text(card.displayText)
                    .font(.system(size: max(w * 0.18, 8), weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(card.suitText)
                    .font(.system(size: max(w * 0.16, 7)))
                    .foregroundColor(textColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)
            .padding(.top, 2)
        }
        .frame(width: w, height: h)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private func cardBack(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(cursed
                      ? Color(red: 0.4, green: 0.0, blue: 0.6).opacity(0.85)
                      : accent.opacity(0.85))
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            RoundedRectangle(cornerRadius: cardCorner - 2)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                .padding(3)
            if cursed {
                Text("💀").font(.system(size: w * 0.3))
            }
        }
        .frame(width: w, height: h)
    }

    // MARK: - Win Overlay

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(cursed ? "💀" : "🏆").font(.system(size: 64))
                    .scaleEffect(winCelebration ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: winCelebration)
                Text(cursed ? "You Survived!" : "You Won!")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text("\(game.moves) moves")
                    .font(.system(size: 18)).foregroundColor(.white.opacity(0.8))
                Button {
                    withAnimation { game.newGame(); selection = nil; winCelebration = false }
                } label: {
                    Label("New Game", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 32).padding(.vertical, 14)
                        .background(accent).cornerRadius(14)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        }
        .onAppear { winCelebration = true }
    }
}

// MARK: - Button Style

struct ChaosCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Tutorial

private struct TutorialPage {
    let emoji: String
    let title: String
    let body: String
    let cards: [TutorialCard]?   // optional mini card demo row
    let tip: String?
}

private struct TutorialCard {
    let rank: String
    let suit: String
    let isRed: Bool
    let isCursed: Bool
    let isFaceDown: Bool
}

private struct ChaosTutorialView: View {
    let backToMenu: () -> Void
    @State private var page = 0

    private let accent = Color.purple
    private let pages: [TutorialPage] = [
        TutorialPage(
            emoji: "🃏",
            title: "The Basics",
            body: "Chaos Solitaire is built on Klondike — the classic solitaire you already know.\n\nYou have:\n• 7 tableau columns (the main play area)\n• A stock pile + waste pile on the top-left\n• Foundation piles on the top-right (your goal)\n\nThe goal: move every card to the foundations.",
            cards: nil,
            tip: nil
        ),
        TutorialPage(
            emoji: "🏗️",
            title: "Building the Tableau",
            body: "Stack cards in descending order, alternating red and black.\n\nYou can move a whole run of face-up cards at once. Face-down cards flip automatically when uncovered.\n\nIn standard (Cheat) mode, only a King can start an empty column.",
            cards: [
                TutorialCard(rank: "8", suit: "♥", isRed: true,  isCursed: false, isFaceDown: false),
                TutorialCard(rank: "7", suit: "♠", isRed: false, isCursed: false, isFaceDown: false),
                TutorialCard(rank: "6", suit: "♦", isRed: true,  isCursed: false, isFaceDown: false),
            ],
            tip: "Red on black, black on red — descending rank."
        ),
        TutorialPage(
            emoji: "🏆",
            title: "Foundations",
            body: "There are 4 foundation piles (one per suit: ♠ ♥ ♦ ♣).\n\nEach starts with an Ace and builds up in order: A → 2 → 3 … → K.\n\nWhen all 52 cards are on the foundations, you win!",
            cards: [
                TutorialCard(rank: "A", suit: "♠", isRed: false, isCursed: false, isFaceDown: false),
                TutorialCard(rank: "2", suit: "♠", isRed: false, isCursed: false, isFaceDown: false),
                TutorialCard(rank: "3", suit: "♠", isRed: false, isCursed: false, isFaceDown: false),
            ],
            tip: "Tap a card in the waste or tableau to send it to its foundation when it's ready."
        ),
        TutorialPage(
            emoji: "💀",
            title: "Cursed Cards",
            body: "Cursed Mode adds two extra suits:\n\n✦  Void Suit — dark, mysterious cards\n💀  Cursed Hearts — chaotic pink cards\n\nCursed cards also use extended ranks:\n-30, -29 … -1, 0 and 14 (X), 15 (Ω)\n\nCursed cards skip the color-alternation rule — they stack on any card that is one rank higher, regardless of color.",
            cards: [
                TutorialCard(rank: "3",  suit: "♥", isRed: true,  isCursed: false, isFaceDown: false),
                TutorialCard(rank: "2",  suit: "✦", isRed: false, isCursed: true,  isFaceDown: false),
                TutorialCard(rank: "1",  suit: "💀", isRed: true,  isCursed: true,  isFaceDown: false),
            ],
            tip: "Cursed cards can stack on anything one rank above — color doesn't matter."
        ),
        TutorialPage(
            emoji: "🌑",
            title: "Cursed Foundations",
            body: "In Cursed Mode there are 6 foundations — the 4 standard suits plus ✦ and 💀.\n\nThe standard foundations still start at Ace (1) and end at King (13).\n\nThe cursed foundations start at -30 and run all the way up to 15 — that's 46 cards per cursed suit!\n\nYou need to fill all 6 to win. Good luck.",
            cards: [
                TutorialCard(rank: "-30", suit: "✦",  isRed: false, isCursed: true, isFaceDown: false),
                TutorialCard(rank: "-29", suit: "✦",  isRed: false, isCursed: true, isFaceDown: false),
                TutorialCard(rank: "…",  suit: "✦",   isRed: false, isCursed: true, isFaceDown: false),
            ],
            tip: "Use 'Teleport Next -30 Card' from the cheat menu to unstick a cursed foundation."
        ),
        TutorialPage(
            emoji: "🕵️",
            title: "The Cheat Menu",
            body: "Tap the ✦ wand button in the top-right to open the cheat menu. It's not cheating — it's a feature.\n\n👁 Reveal All — flip every hidden card face-up\n💡 Show Hint — highlights your best next move\n📤 Smart Draw — skip to the next ace / number / red card\n✨ Teleport — instantly send aces (or -30s) to foundations\n☠️ Inject Chaos — add more cursed cards mid-game (cursed mode only)",
            cards: nil,
            tip: "No shame. The game is already unfair."
        ),
        TutorialPage(
            emoji: "▶️",
            title: "Auto-Play",
            body: "Tap the ▶ play button in the toolbar to enable Auto-Play.\n\nThe game will automatically make the best available move every half second — you can watch it solve (or get stuck).\n\nTap ⏸ pause to take control back at any time.",
            cards: nil,
            tip: "Auto-Play is great for clearing obvious end-game moves."
        ),
        TutorialPage(
            emoji: "🎯",
            title: "Tips & Tricks",
            body: "• Always uncover face-down cards before anything else — they're your biggest unknowns.\n\n• Don't rush cards to the foundation if you still need them to build tableau runs.\n\n• Empty columns are powerful — use them to reorganise runs.\n\n• In Cursed Mode: use Teleport liberally. The -30 card for a cursed foundation is usually buried deep.",
            cards: nil,
            tip: nil
        ),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Circle()
                                .fill(i == page ? accent : Color(.systemGray4))
                                .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: page)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    // Page content
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                            tutorialPageView(p)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: page)

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if page > 0 {
                            Button {
                                withAnimation { page -= 1 }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(accent.opacity(0.1))
                                .cornerRadius(14)
                            }
                        }

                        if page < pages.count - 1 {
                            Button {
                                withAnimation { page += 1 }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Next")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(accent)
                                .cornerRadius(14)
                            }
                        } else {
                            Button {
                                backToMenu()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                    Text("Got It — Let's Play!")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.teal)
                                .cornerRadius(14)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { backToMenu() } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func tutorialPageView(_ p: TutorialPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Emoji + title
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.emoji)
                        .font(.system(size: 52))
                    Text(p.title)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                }

                // Body text
                Text(p.body)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                // Mini card demo (if any)
                if let cards = p.cards {
                    HStack(spacing: 8) {
                        ForEach(Array(cards.enumerated()), id: \.offset) { _, c in
                            miniCard(c)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Tip box
                if let tip = p.tip {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 14))
                            .padding(.top, 1)
                        Text(tip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func miniCard(_ c: TutorialCard) -> some View {
        let bg: Color = c.isFaceDown
            ? Color.purple.opacity(0.85)
            : (c.isCursed ? Color(red: 0.18, green: 0.03, blue: 0.03) : Color(red: 0.93, green: 0.93, blue: 0.95))
        let fg: Color = c.isCursed
            ? (c.suit == "💀" ? Color.pink : Color(red: 0.8, green: 0.4, blue: 1.0))
            : (c.isRed ? .red : Color(red: 0.08, green: 0.08, blue: 0.10))

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(bg)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            if c.isCursed {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.purple.opacity(0.6), lineWidth: 1.5)
            }
            if !c.isFaceDown {
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.rank)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(c.suit)
                        .font(.system(size: 11))
                        .foregroundColor(fg)
                }
                .padding(.horizontal, 4)
                .padding(.top, 3)
            } else {
                Text("🃏").font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 48, height: 68)
    }
}

#Preview {
    ChaosTutorialView(backToMenu: {})
}

#Preview { ChaosSolitaireView() }
