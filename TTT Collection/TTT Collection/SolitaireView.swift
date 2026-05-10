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

// MARK: - Selection / Drag source

private enum CardSource: Equatable {
    case waste
    case tableau(col: Int, fromIdx: Int)
    case foundation(idx: Int)
}

private struct Selection: Equatable {
    var source: CardSource
    var cards: [Card]
}

// MARK: - Column-frame preference key
// Used so the drag layer can hit-test which column the finger is over.

private struct ColFrame: Equatable {
    let col: Int          // 0-6 for tableau, 10-13 for foundations
    let frame: CGRect
}

private struct ColFramesKey: PreferenceKey {
    static var defaultValue: [ColFrame] = []
    static func reduce(value: inout [ColFrame], nextValue: () -> [ColFrame]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Game Logic

private class SolitaireGame: ObservableObject {
    @Published var stock: [Card] = []
    @Published var waste: [Card] = []
    @Published var foundations: [[Card]] = Array(repeating: [], count: 4)
    @Published var tableau: [[Card]] = Array(repeating: [], count: 7)
    @Published var moves: Int = 0
    @Published var isWon: Bool = false

    init() { newGame() }

    func newGame() {
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
        moves = 0
        isWon = false
    }

    func drawFromStock() {
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            foundations[fi].append(waste.removeLast()); moves += 1; checkWin()
        }
        return true
    }

    @discardableResult func wasteToTableau(col: Int) -> Bool {
        guard let card = waste.last, canPlaceOnTableau(card, col: col) else { return false }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            tableau[col].append(waste.removeLast()); moves += 1
        }
        return true
    }

    @discardableResult func tableauToFoundation(col: Int) -> Bool {
        guard let card = tableau[col].last, card.isFaceUp else { return false }
        let fi = foundationIdx(for: card.suit)
        guard canPlaceOnFoundation(card, idx: fi) else { return false }
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            tableau[toCol].append(foundations[fi].removeLast()); moves += 1
        }
        return true
    }

    @discardableResult func wasteToFoundationSlot(_ fi: Int) -> Bool {
        guard let card = waste.last,
              canPlaceOnFoundation(card, idx: fi) else { return false }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            foundations[fi].append(waste.removeLast()); moves += 1; checkWin()
        }
        return true
    }

    @discardableResult func tableauToFoundationSlot(col: Int, fi: Int) -> Bool {
        guard let card = tableau[col].last, card.isFaceUp,
              canPlaceOnFoundation(card, idx: fi) else { return false }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            foundations[fi].append(tableau[col].removeLast())
            flipTopCard(col: col); moves += 1; checkWin()
        }
        return true
    }

    private func checkWin() { isWon = foundations.allSatisfy { $0.count == 13 } }
}

// MARK: - View

struct SolitaireView: View {
    @StateObject private var game = SolitaireGame()

    // Tap selection
    @State private var selection: Selection? = nil

    // Drag state
    @State private var dragSelection: Selection? = nil   // cards being dragged
    @State private var dragLocation: CGPoint = .zero     // current finger position (global)
    @State private var dragStarted = false
    @State private var colFrames: [ColFrame] = []        // column frames in global space

    @State private var winCelebration = false

    private let accent      = Color.indigo
    private let cardCorner: CGFloat = 7

    // Derived: are we mid-drag?
    private var isDragging: Bool { dragSelection != nil && dragStarted }

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
                    // Collect column frames reported by children (in global coords)
                    .onPreferenceChange(ColFramesKey.self) { colFrames = $0 }

                    // ── Drag ghost ──────────────────────────────────────────
                    if isDragging, let ds = dragSelection {
                        let ghostCards = ds.cards
                        let fuOff: CGFloat = cardH * 0.30
                        ZStack(alignment: .top) {
                            ForEach(Array(ghostCards.enumerated()), id: \.element.id) { i, card in
                                cardFace(card, w: colW, h: cardH, isSelected: false)
                                    .offset(y: CGFloat(i) * fuOff)
                                    .opacity(0.88)
                            }
                        }
                        // Centre ghost on finger, offset upward so finger is near top of card
                        .position(x: dragLocation.x,
                                  y: dragLocation.y - cardH * 0.1)
                        .allowsHitTesting(false)
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                        .zIndex(999)
                    }

                    // ── Selection banner ────────────────────────────────────
                    if selection != nil && !isDragging {
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
                            withAnimation { game.newGame(); selection = nil }
                        } label: {
                            Image(systemName: "arrow.counterclockwise").foregroundColor(accent)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
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

            // Foundations (ids 10-13)
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
                let isSel = selection?.source == .waste && !isDragging
                cardFace(top, w: colW, h: cardH, isSelected: isSel)
                    // Make card invisible while being dragged
                    .opacity(dragSelection?.source == .waste && isDragging ? 0.25 : 1.0)
                    .onTapGesture { handleWasteTap(card: top) }
                    .gesture(cardDragGesture(
                        source: .waste,
                        cards: [top],
                        colW: colW, cardH: cardH
                    ))
            } else {
                Text("—").foregroundColor(Color(.tertiaryLabel)).font(.system(size: 16))
            }
        }
        .frame(width: colW, height: cardH)
    }

    private func handleWasteTap(card: Card) {
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
        // Report frame for drag hit-testing (id = 10 + fi)
        .background(GeometryReader { g in
            Color.clear.preference(
                key: ColFramesKey.self,
                value: [ColFrame(col: 10 + fi, frame: g.frame(in: .global))]
            )
        })
        .onTapGesture { handleFoundationTap(fi: fi) }
    }

    private func handleFoundationTap(fi: Int) {
        if let sel = selection {
            switch sel.source {
            case .waste:            game.wasteToFoundation()
            case .tableau(let c, _): game.tableauToFoundation(col: c)
            case .foundation:       break
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
        let cards  = game.tableau[col]
        let fdOff: CGFloat = cardH * 0.13
        let fuOff: CGFloat = cardH * 0.30

        // Total height so all cards are visible
        var totalH: CGFloat = cardH
        for i in 0..<max(0, cards.count - 1) {
            totalH += cards[i].isFaceUp ? fuOff : fdOff
        }

        // Index of the first dragged card in this column (if any)
        let dragFromIdx: Int? = {
            if case .tableau(let c, let idx) = dragSelection?.source, c == col { return idx }
            return nil
        }()

        return ZStack(alignment: .top) {
            // Empty-column drop zone
            RoundedRectangle(cornerRadius: cardCorner)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 1)
                .frame(width: colW, height: cardH)
                .contentShape(Rectangle())
                .onTapGesture { tryDropOnTableau(col: col) }

            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                let yOff: CGFloat = {
                    var y: CGFloat = 0
                    for i in 0..<idx { y += cards[i].isFaceUp ? fuOff : fdOff }
                    return y
                }()
                let isSelHighlight: Bool = {
                    if case .tableau(let c, let si) = selection?.source {
                        return c == col && idx >= si && !isDragging
                    }
                    return false
                }()
                // Ghost-out cards that are being dragged from this column
                let isDraggedAway = dragFromIdx.map { idx >= $0 } ?? false

                Group {
                    if card.isFaceUp {
                        cardFace(card, w: colW, h: cardH, isSelected: isSelHighlight)
                            .opacity(isDraggedAway && isDragging ? 0.25 : 1.0)
                            .onTapGesture { handleTableauCardTap(col: col, idx: idx) }
                            .gesture(cardDragGesture(
                                source: .tableau(col: col, fromIdx: idx),
                                cards: Array(cards[idx...]),
                                colW: colW, cardH: cardH
                            ))
                    } else {
                        cardBack(w: colW, h: cardH)
                    }
                }
                .offset(y: yOff)
            }
        }
        .frame(width: colW, height: max(totalH, cardH))
        .contentShape(Rectangle())
        .onTapGesture { tryDropOnTableau(col: col) }
        // Report this column's frame for drag hit-testing
        .background(GeometryReader { g in
            Color.clear.preference(
                key: ColFramesKey.self,
                value: [ColFrame(col: col, frame: g.frame(in: .global))]
            )
        })
    }

    // MARK: Tableau tap handling

    private func handleTableauCardTap(col: Int, idx: Int) {
        let cards = game.tableau[col]
        guard idx < cards.count, cards[idx].isFaceUp else { return }
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
        case .waste:                        moved = game.wasteToTableau(col: col)
        case .tableau(let fc, let fi):      moved = game.tableauToTableau(fromCol: fc, fromIdx: fi, toCol: col)
        case .foundation(let fi):           moved = game.foundationToTableau(fi: fi, toCol: col)
        }
        if moved { withAnimation { selection = nil } }
        return moved
    }

    // MARK: - Drag Gesture

    /// Builds a DragGesture for any draggable card.
    private func cardDragGesture(
        source: CardSource,
        cards: [Card],
        colW: CGFloat,
        cardH: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if !dragStarted {
                    dragStarted = true
                    dragSelection = Selection(source: source, cards: cards)
                    // Clear tap selection when drag starts
                    selection = nil
                }
                dragLocation = value.location
            }
            .onEnded { value in
                defer {
                    dragStarted = false
                    dragSelection = nil
                }
                guard let ds = dragSelection else { return }
                let dropPoint = value.location

                // Hit-test: find which registered frame the finger landed in
                if let hit = colFrames.first(where: { $0.frame.contains(dropPoint) }) {
                    let moved: Bool
                    if hit.col >= 10 {
                        // Foundation slot (col id = 10 + fi)
                        let fi = hit.col - 10
                        switch ds.source {
                        case .waste:
                            moved = game.wasteToFoundationSlot(fi)
                        case .tableau(let c, _):
                            moved = game.tableauToFoundationSlot(col: c, fi: fi)
                        case .foundation:
                            moved = false
                        }
                    } else {
                        // Tableau column
                        let toCol = hit.col
                        switch ds.source {
                        case .waste:
                            moved = game.wasteToTableau(col: toCol)
                        case .tableau(let fc, let fi):
                            moved = game.tableauToTableau(fromCol: fc, fromIdx: fi, toCol: toCol)
                        case .foundation(let fi):
                            moved = game.foundationToTableau(fi: fi, toCol: toCol)
                        }
                    }
                    _ = moved
                }
                // If no valid drop, the ghost just disappears — cards stay put
            }
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
