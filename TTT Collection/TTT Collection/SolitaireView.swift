import SwiftUI
internal import Combine

// MARK: - Model

private enum Suit: String, CaseIterable {
    case spades = "♠", hearts = "♥", diamonds = "♦", clubs = "♣"
    var isRed: Bool { self == .hearts || self == .diamonds }
}

private enum Rank: Int, CaseIterable {
    case ace = 1, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king
    var display: String {
        switch self {
        case .ace:   return "A"
        case .jack:  return "J"
        case .queen: return "Q"
        case .king:  return "K"
        default:     return "\(rawValue)"
        }
    }
}

private struct Card: Identifiable, Equatable {
    let id = UUID()
    let suit: Suit
    let rank: Rank
    var isFaceUp: Bool = false
    var isRed: Bool { suit.isRed }
}

// MARK: - Selection / Tap source

private enum CardSource: Equatable {
    case waste
    case tableau(col: Int, fromIdx: Int)
    case foundation(idx: Int)
}

private struct Selection: Equatable {
    var source: CardSource
    var cards: [Card]
}

// MARK: - Game Logic

private struct GameSnapshot {
    let stock: [Card]
    let waste: [Card]
    let foundations: [[Card]]
    let tableau: [[Card]]
    let moves: Int
}

private class SolitaireGame: ObservableObject {
    @Published var stock: [Card] = []
    @Published var waste: [Card] = []
    @Published var foundations: [[Card]] = Array(repeating: [], count: 4)
    @Published var tableau: [[Card]] = Array(repeating: [], count: 7)
    @Published var moves: Int = 0
    @Published var isWon: Bool = false

    private var undoStack: [GameSnapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }

    init() { newGame() }

    private func saveSnapshot() {
        undoStack.append(GameSnapshot(
            stock: stock, waste: waste,
            foundations: foundations, tableau: tableau, moves: moves
        ))
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            stock = snap.stock
            waste = snap.waste
            foundations = snap.foundations
            tableau = snap.tableau
            moves = snap.moves
            isWon = false
        }
    }

    func newGame() {
        var attempts = 0
        repeat {
            deal()
            attempts += 1
        } while !isSolvable() && attempts < 100
        moves = 0
        isWon = false
        undoStack = []
    }

    private func deal() {
        var deck = Suit.allCases.flatMap { suit in
            Rank.allCases.map { Card(suit: suit, rank: $0) }
        }.shuffled()
        tableau = (0..<7).map { col in
            var pile = Array(deck.prefix(col + 1))
            deck.removeFirst(col + 1)
            pile[pile.count - 1].isFaceUp = true
            return pile
        }
        stock = deck.map { var c = $0; c.isFaceUp = false; return c }
        waste = []
        foundations = Array(repeating: [], count: 4)
    }

    /// Greedy heuristic solver — simulates autoplay and checks if the game
    /// can be completed. Not perfect but catches the vast majority of unwinnable deals.
    private func isSolvable() -> Bool {
        // Work on copies so we don't mutate real state
        var simStock = stock
        var simWaste = waste
        var simFoundations = foundations
        var simTableau = tableau

        func canPlaceOnFoundation(_ card: Card, idx: Int) -> Bool {
            let pile = simFoundations[idx]
            if pile.isEmpty { return card.rank == .ace }
            guard let top = pile.last else { return false }
            return top.suit == card.suit && top.rank.rawValue + 1 == card.rank.rawValue
        }
        func foundationIdx(for card: Card) -> Int {
            Suit.allCases.firstIndex(of: card.suit)!
        }
        func canPlaceOnTableau(_ card: Card, col: Int) -> Bool {
            let pile = simTableau[col]
            if pile.isEmpty { return card.rank == .king }
            guard let top = pile.last, top.isFaceUp else { return false }
            return top.isRed != card.isRed && top.rank.rawValue - 1 == card.rank.rawValue
        }
        func flipTops() {
            for col in 0..<7 {
                if let last = simTableau[col].indices.last, !simTableau[col][last].isFaceUp {
                    simTableau[col][last].isFaceUp = true
                }
            }
        }

        var stockDrawsSinceProgress = 0
        let maxIter = 500

        for _ in 0..<maxIter {
            var madeMove = false

            // Move aces and safe cards to foundation
            // "Safe" = won't block the other color's lower card from building
            func tryMoveToFoundation(_ card: Card) -> Bool {
                let fi = foundationIdx(for: card)
                guard canPlaceOnFoundation(card, idx: fi) else { return false }
                // Safety check: only auto-move if both same-rank opposite colors are already on foundation
                // (avoids stranding needed cards). For simplicity, always move aces/2s safely.
                if card.rank.rawValue <= 2 { return true }
                let minFoundation = simFoundations.map { $0.count }.min() ?? 0
                return card.rank.rawValue <= minFoundation + 2
            }

            // Waste to foundation
            if let top = simWaste.last, tryMoveToFoundation(top) {
                let fi = foundationIdx(for: top)
                simFoundations[fi].append(simWaste.removeLast())
                madeMove = true
            }

            // Tableau to foundation
            for col in 0..<7 {
                if let top = simTableau[col].last, top.isFaceUp, tryMoveToFoundation(top) {
                    let fi = foundationIdx(for: top)
                    simFoundations[fi].append(simTableau[col].removeLast())
                    flipTops()
                    madeMove = true
                }
            }

            // Tableau to tableau — prefer moves that uncover face-down cards
            outer: for col in 0..<7 {
                guard let fromIdx = simTableau[col].indices.first(where: { simTableau[col][$0].isFaceUp }) else { continue }
                let card = simTableau[col][fromIdx]
                let hasHidden = simTableau[col].prefix(fromIdx).contains(where: { !$0.isFaceUp })
                for toCol in 0..<7 where toCol != col {
                    if canPlaceOnTableau(card, col: toCol) {
                        // Only move if it uncovers hidden cards or places on non-empty column
                        if hasHidden || !simTableau[toCol].isEmpty {
                            let run = Array(simTableau[col][fromIdx...])
                            simTableau[col].removeSubrange(fromIdx...)
                            simTableau[toCol].append(contentsOf: run)
                            flipTops()
                            madeMove = true
                            break outer
                        }
                    }
                }
            }

            // Waste to tableau
            if let top = simWaste.last {
                for col in 0..<7 {
                    if canPlaceOnTableau(top, col: col) {
                        simTableau[col].append(simWaste.removeLast())
                        madeMove = true
                        break
                    }
                }
            }

            if madeMove {
                stockDrawsSinceProgress = 0
            } else {
                // Draw from stock
                let totalStock = simStock.count + simWaste.count
                if stockDrawsSinceProgress >= totalStock { break }
                if simStock.isEmpty {
                    simStock = simWaste.reversed().map { var c = $0; c.isFaceUp = false; return c }
                    simWaste = []
                }
                if !simStock.isEmpty {
                    var card = simStock.removeLast()
                    card.isFaceUp = true
                    simWaste.append(card)
                    stockDrawsSinceProgress += 1
                }
            }

            // Check win
            if simFoundations.allSatisfy({ $0.count == 13 }) { return true }
        }

        // If we moved most cards to foundations, consider it good enough
        let foundationCount = simFoundations.flatMap { $0 }.count
        return foundationCount >= 40
    }

    func drawFromStock() {
        saveSnapshot()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            if stock.isEmpty {
                stock = waste.reversed().map { var c = $0; c.isFaceUp = false; return c }
                waste = []
            } else {
                var card = stock.removeLast()
                card.isFaceUp = true
                waste.append(card)
            }
            moves += 1
        }
    }

    // MARK: Validation

    func canPlaceOnFoundation(_ card: Card, idx: Int) -> Bool {
        let pile = foundations[idx]
        if pile.isEmpty { return card.rank == .ace }
        guard let top = pile.last else { return false }
        return top.suit == card.suit && top.rank.rawValue + 1 == card.rank.rawValue
    }

    func canPlaceOnTableau(_ card: Card, col: Int) -> Bool {
        let pile = tableau[col]
        if pile.isEmpty { return card.rank == .king }
        guard let top = pile.last, top.isFaceUp else { return false }
        return top.isRed != card.isRed && top.rank.rawValue - 1 == card.rank.rawValue
    }

    private func flipTopCard(col: Int) {
        guard !tableau[col].isEmpty else { return }
        let i = tableau[col].count - 1
        if !tableau[col][i].isFaceUp { tableau[col][i].isFaceUp = true }
    }

    private func foundationIdx(for suit: Suit) -> Int { Suit.allCases.firstIndex(of: suit)! }

    // MARK: Moves

    @discardableResult func wasteToFoundation() -> Bool {
        guard let card = waste.last else { return false }
        let fi = foundationIdx(for: card.suit)
        guard canPlaceOnFoundation(card, idx: fi) else { return false }
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

    private func checkWin() { isWon = foundations.allSatisfy { $0.count == 13 } }

    // MARK: - Auto Move

    /// Try to move a card from waste to the best available spot.
    /// Priority: foundation first, then first valid tableau column.
    @discardableResult func autoMoveWaste() -> Bool {
        if wasteToFoundation() { return true }
        for col in 0..<7 {
            if wasteToTableau(col: col) { return true }
        }
        return false
    }

    /// Try to auto-move the top face-up card of a tableau column.
    @discardableResult func autoMoveTableau(col: Int, fromIdx: Int) -> Bool {
        let isTopCard = fromIdx == tableau[col].count - 1
        // Only try foundation if tapping the single top card
        if isTopCard && tableauToFoundation(col: col) { return true }
        for toCol in 0..<7 where toCol != col {
            if tableauToTableau(fromCol: col, fromIdx: fromIdx, toCol: toCol) { return true }
        }
        return false
    }
}

// MARK: - View

struct SolitaireView: View {
    @StateObject private var game = SolitaireGame()
    @AppStorage("solitaireTapMode") private var tapMode: String = "tap"

    // Tap selection (used in "tap" mode only)
    @State private var selection: Selection? = nil
    @State private var winCelebration = false
    @State private var autoPlaying = false
    @State private var autoPlayTimer: Timer? = nil
    @State private var stockDrawsSinceMove = 0

    private let accent      = Color.indigo
    private let cardCorner: CGFloat = 7

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let hPad:    CGFloat = 10
                let spacing: CGFloat = 4
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

                            tableauArea(colW: colW, cardH: cardH,
                                        hPad: hPad, spacing: spacing)
                                .padding(.horizontal, hPad)
                                .padding(.bottom, selection != nil ? 56 : 20)
                        }
                    }

                    // ── Selection banner (tap mode only) ───────────────────
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
            .navigationTitle("Solitaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Text("\(game.moves) moves")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Button {
                            withAnimation { game.undo(); selection = nil }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundColor(game.canUndo ? accent : .secondary.opacity(0.4))
                        }
                        .disabled(!game.canUndo)
                        Button {
                            toggleAutoPlay()
                        } label: {
                            Image(systemName: autoPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(autoPlaying ? .orange : accent)
                        }
                        Button {
                            withAnimation { game.newGame(); selection = nil; stopAutoPlay() }
                        } label: {
                            Image(systemName: "arrow.counterclockwise").foregroundColor(accent)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: game.isWon) { won in
            if won { stopAutoPlay() }
        }
    }

    // MARK: - Auto Play

    private func toggleAutoPlay() {
        if autoPlaying { stopAutoPlay() } else { startAutoPlay() }
    }

    private func startAutoPlay() {
        autoPlaying = true
        selection = nil
        stockDrawsSinceMove = 0
        autoPlayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let result = performBestAutoMove()
            if !result {
                stopAutoPlay()
            }
        }
    }

    private func stopAutoPlay() {
        autoPlaying = false
        autoPlayTimer?.invalidate()
        autoPlayTimer = nil
    }

    /// Try every possible move in priority order. Returns true if a move was made.
    private func performBestAutoMove() -> Bool {
        // Reset stock draw counter — a real move was attempted
        stockDrawsSinceMove = 0

        // 1. Waste to foundation
        if game.autoMoveWaste() { return true }

        // 2. Tableau to foundation
        for col in 0..<7 {
            if game.tableauToFoundation(col: col) { return true }
        }

        // 3. Tableau to tableau — skip king-to-empty moves that can't help
        let emptyColumns = (0..<7).filter { game.tableau[$0].isEmpty }
        for col in 0..<7 {
            let cards = game.tableau[col]
            guard let fromIdx = cards.indices.first(where: { cards[$0].isFaceUp }) else { continue }
            let movingCard = cards[fromIdx]
            for toCol in 0..<7 where toCol != col {
                // Skip: moving a king to an empty column when the source column
                // is ALSO all face-up with no hidden cards to uncover — pointless shuffle.
                if movingCard.rank == .king && game.tableau[toCol].isEmpty {
                    let hasHiddenCards = cards.prefix(fromIdx).contains(where: { !$0.isFaceUp })
                    // Only move king to empty if it uncovers hidden cards, or there's only 1 empty col
                    if !hasHiddenCards && emptyColumns.count > 1 { continue }
                    if !hasHiddenCards && emptyColumns.count == 1 && fromIdx == 0 { continue }
                }
                if game.tableauToTableau(fromCol: col, fromIdx: fromIdx, toCol: toCol) { return true }
            }
        }

        // 4. Draw from stock — stop if we've cycled through the whole stock without a real move
        let stockSize = game.stock.count + game.waste.count
        if stockSize > 0 {
            if stockDrawsSinceMove >= stockSize {
                // Full cycle with no progress — softlocked
                return false
            }
            game.drawFromStock()
            stockDrawsSinceMove += 1
            return true
        }

        return false
    }

    // MARK: - Selection Banner

    private var selectionBanner: some View {
        HStack {
            if let sel = selection {
                let label = sel.cards.count == 1
                    ? "\(sel.cards[0].rank.display)\(sel.cards[0].suit.rawValue) selected"
                    : "\(sel.cards.count) cards selected"
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Cancel") { selection = nil }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(accent)
        .cornerRadius(9)
        .padding(.horizontal, 10)
    }

    // MARK: - Top Row

    private func topRow(colW: CGFloat, cardH: CGFloat) -> some View {
        HStack(spacing: 4) {
            // Stock
            Button { game.drawFromStock(); selection = nil } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: cardCorner)
                        .fill(game.stock.isEmpty
                              ? Color(.secondarySystemGroupedBackground)
                              : accent.opacity(0.85))
                    if game.stock.isEmpty {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.secondary).font(.system(size: 16))
                    } else {
                        VStack(spacing: 2) {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundColor(.white).font(.system(size: 15))
                            Text("\(game.stock.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
            .frame(width: colW, height: cardH)

            // Waste
            wasteSlot(colW: colW, cardH: cardH)

            Spacer()

            // Foundations
            ForEach(0..<4, id: \.self) { fi in
                foundationSlot(fi: fi, colW: colW, cardH: cardH)
            }
        }
    }

    // MARK: Waste slot

    private func wasteSlot(colW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(Color(.secondarySystemGroupedBackground))

            if let top = game.waste.last {
                let isSel = selection?.source == .waste
                cardFace(top, w: colW, h: cardH, isSelected: isSel)
                    .onTapGesture { handleWasteTap(card: top) }
            } else {
                Text("—").foregroundColor(Color(.tertiaryLabel)).font(.system(size: 16))
            }
        }
        .frame(width: colW, height: cardH)
    }

    private func handleWasteTap(card: Card) {
        if tapMode == "auto" {
            game.autoMoveWaste()
            return
        }
        // tap-to-select mode
        if selection != nil { selection = nil; return }
        if !game.wasteToFoundation() {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selection = Selection(source: .waste, cards: [card])
            }
        }
    }

    // MARK: Foundation slot

    private func foundationSlot(fi: Int, colW: CGFloat, cardH: CGFloat) -> some View {
        let suit = Suit.allCases[fi]
        let pile = game.foundations[fi]
        let isSel: Bool = {
            if case .foundation(let s) = selection?.source { return s == fi }
            return false
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: cardCorner)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: cardCorner)
                    .fill(Color(.secondarySystemGroupedBackground)))
            if let top = pile.last {
                cardFace(top, w: colW, h: cardH, isSelected: isSel)
            } else {
                Text(suit.rawValue).font(.system(size: 16))
                    .foregroundColor(suit.isRed ? .red.opacity(0.3) : Color(.tertiaryLabel))
            }
        }
        .frame(width: colW, height: cardH)
        .onTapGesture { handleFoundationTap(fi: fi) }
    }

    private func handleFoundationTap(fi: Int) {
        // Auto mode: foundation cards aren't typically moved out, just ignore
        if tapMode == "auto" { return }
        // tap-to-select mode
        if let sel = selection {
            switch sel.source {
            case .waste:             game.wasteToFoundation()
            case .tableau(let c, _): game.tableauToFoundation(col: c)
            case .foundation:        break
            }
            selection = nil
        } else if let top = game.foundations[fi].last {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selection = Selection(source: .foundation(idx: fi), cards: [top])
            }
        }
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
        let fuOff: CGFloat = cardH * 0.25

        var totalH: CGFloat = cardH
        for i in 0..<cards.count {
            if i < cards.count - 1 {
                totalH += cards[i].isFaceUp ? fuOff : fdOff
            }
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
                    for i in 0..<idx {
                        y += cards[i].isFaceUp ? fuOff : fdOff
                    }
                    return y
                }()

                let isSelHighlight: Bool = {
                    if case .tableau(let c, let si) = selection?.source {
                        return c == col && idx >= si
                    }
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

    // MARK: Tableau tap handling

    private func handleTableauCardTap(col: Int, idx: Int) {
        let cards = game.tableau[col]
        guard idx < cards.count, cards[idx].isFaceUp else { return }

        if tapMode == "auto" {
            game.autoMoveTableau(col: col, fromIdx: idx)
            return
        }

        // tap-to-select mode
        if selection != nil {
            let moved = tryDropOnTableau(col: col)
            if moved { return }
        }
        let run = Array(cards[idx...])
        guard run.allSatisfy({ $0.isFaceUp }) else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            selection = Selection(source: .tableau(col: col, fromIdx: idx), cards: run)
        }
    }

    @discardableResult
    private func tryDropOnTableau(col: Int) -> Bool {
        guard let sel = selection else { return false }
        var moved = false
        switch sel.source {
        case .waste:                    moved = game.wasteToTableau(col: col)
        case .tableau(let fc, let fi):  moved = game.tableauToTableau(fromCol: fc, fromIdx: fi, toCol: col)
        case .foundation(let fi):       moved = game.foundationToTableau(fi: fi, toCol: col)
        }
        if moved { withAnimation { selection = nil } }
        return moved
    }

    // MARK: - Card Views

    private func cardFace(_ card: Card, w: CGFloat, h: CGFloat, isSelected: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(Color(red: 0.93, green: 0.93, blue: 0.95))
                .shadow(color: .black.opacity(0.14), radius: 2, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: cardCorner)
                        .strokeBorder(isSelected ? Color.yellow : Color.clear, lineWidth: 2.5)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(card.rank.display)
                    .font(.system(size: w * 0.24, weight: .bold, design: .rounded))
                    .foregroundColor(card.isRed ? .red : Color(red: 0.08, green: 0.08, blue: 0.10))
                    .lineLimit(1)
                Text(card.suit.rawValue)
                    .font(.system(size: w * 0.20))
                    .foregroundColor(card.isRed ? .red : Color(red: 0.08, green: 0.08, blue: 0.10))
            }
            .padding(.horizontal, 4)
            .padding(.top, 3)
        }
        .frame(width: w, height: h)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private func cardBack(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCorner)
                .fill(accent.opacity(0.85))
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            RoundedRectangle(cornerRadius: cardCorner - 2)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                .padding(3)
        }
        .frame(width: w, height: h)
    }

    // MARK: - Win Overlay

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("🏆").font(.system(size: 64))
                    .scaleEffect(winCelebration ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: winCelebration)
                Text("You Won!")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(game.moves) moves")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
                Button {
                    withAnimation { game.newGame(); selection = nil; winCelebration = false }
                } label: {
                    Label("New Game", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
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

#Preview {
    SolitaireView()
}
