//
//  MemoryCard.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI
internal import Combine

// MARK: - Model

private struct MemoryCard: Identifiable {
    let id = UUID()
    let symbol: String
    var isFaceUp: Bool = false
    var isMatched: Bool = false
}

// MARK: - ViewModel

private final class MemoryMatchViewModel: ObservableObject {
    // Grid sizes per level: (cols, rows)
    private static let levels: [(cols: Int, rows: Int)] = [
        (4, 3), (4, 4), (4, 5), (5, 5), (5, 6), (6, 6), (6, 7), (7, 7), (7, 8), (8, 8)
    ]

    private static let allSymbols = [
        "star.fill","heart.fill","bolt.fill","moon.fill","sun.max.fill",
        "leaf.fill","flame.fill","drop.fill","snowflake","cloud.fill",
        "tornado","wind","sparkles","waveform","antenna.radiowaves.left.and.right",
        "pawprint.fill","tree.fill","music.note","bell.fill","gift.fill",
        "camera.fill","headphones","gamecontroller.fill","car.fill","airplane",
        "bicycle","leaf.arrow.triangle.circlepath","flag.fill","crown.fill","diamond.fill"
    ]

    @Published var cards: [MemoryCard] = []
    @Published var moves: Int = 0
    @Published var matches: Int = 0
    @Published var isGameOver: Bool = false
    @Published var level: Int = 1
    @Published var elapsedSeconds: Int = 0
    @Published var showLevelUp: Bool = false

    private var faceUpIndices: [Int] = []
    private var isChecking: Bool = false
    private var timer: Timer?
    private var cols: Int = 4
    private var rows: Int = 3

    var totalPairs: Int { cards.count / 2 }
    var gridCols: Int { cols }
    var gridRows: Int { rows }

    init() { startLevel(1) }

    func startLevel(_ lvl: Int) {
        level = lvl
        let config = Self.levels[min(lvl - 1, Self.levels.count - 1)]
        cols = config.cols
        rows = config.rows
        let pairCount = (cols * rows) / 2
        let symbols = Array(Self.allSymbols.shuffled().prefix(pairCount))
        cards = (symbols + symbols).shuffled().map { MemoryCard(symbol: $0) }
        moves = 0
        matches = 0
        isGameOver = false
        faceUpIndices = []
        isChecking = false
        elapsedSeconds = 0
        showLevelUp = false
        startTimer()
    }

    func restart() { startLevel(level) }

    func nextLevel() {
        let next = min(level + 1, Self.levels.count)
        startLevel(next)
    }

    func flip(index: Int) {
        guard !isChecking,
              !cards[index].isFaceUp,
              !cards[index].isMatched else { return }

        cards[index].isFaceUp = true
        faceUpIndices.append(index)

        if faceUpIndices.count == 2 {
            moves += 1
            isChecking = true
            let a = faceUpIndices[0], b = faceUpIndices[1]

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                guard let self else { return }
                if self.cards[a].symbol == self.cards[b].symbol {
                    self.cards[a].isMatched = true
                    self.cards[b].isMatched = true
                    self.matches += 1
                    if self.matches == self.totalPairs {
                        self.stopTimer()
                        if self.level < Self.levels.count {
                            self.showLevelUp = true
                        } else {
                            self.isGameOver = true
                        }
                    }
                } else {
                    self.cards[a].isFaceUp = false
                    self.cards[b].isFaceUp = false
                }
                self.faceUpIndices = []
                self.isChecking = false
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stopTimer() }

    var timeString: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Card View

private struct MemoryCardView: View {
    let card: MemoryCard
    let color: Color

    var body: some View {
        ZStack {
            // Back face
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.7), color],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(card.isFaceUp ? 0 : 1)

            // Front face
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(card.isMatched ? color : Color(.separator), lineWidth: card.isMatched ? 2 : 1)
                )
                .opacity(card.isFaceUp ? 1 : 0)

            Image(systemName: card.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(card.isMatched ? color : .primary)
                .opacity(card.isFaceUp ? 1 : 0)
                .scaleEffect(card.isMatched ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: card.isMatched)
        }
        .rotation3DEffect(
            .degrees(card.isFaceUp ? 0 : 180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: card.isFaceUp)
    }
}

// MARK: - Main View

struct MemoryMatchView: View {
    @StateObject private var vm = MemoryMatchViewModel()
    @Environment(\.dismiss) private var dismiss

    private let accentColor = Color.pink

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    Spacer()
                    Text("Memory Match")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer()
                    Button { vm.restart() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // Stats bar
                HStack(spacing: 0) {
                    statPill(icon: "crown.fill", value: "Level \(vm.level)", color: accentColor)
                    Spacer()
                    statPill(icon: "hand.tap.fill", value: "\(vm.moves) moves", color: .secondary)
                    Spacer()
                    statPill(icon: "clock.fill", value: vm.timeString, color: .secondary)
                    Spacer()
                    statPill(icon: "checkmark.circle.fill",
                             value: "\(vm.matches)/\(vm.totalPairs)", color: .green)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Grid
                GeometryReader { geo in
                    let hPad: CGFloat = 16
                    let spacing: CGFloat = 8
                    let cols = vm.gridCols
                    let cellW = (geo.size.width - hPad * 2 - spacing * CGFloat(cols - 1)) / CGFloat(cols)
                    let cellH = cellW * 1.2

                    VStack(spacing: spacing) {
                        ForEach(0..<vm.gridRows, id: \.self) { row in
                            HStack(spacing: spacing) {
                                ForEach(0..<cols, id: \.self) { col in
                                    let idx = row * cols + col
                                    if idx < vm.cards.count {
                                        MemoryCardView(card: vm.cards[idx], color: accentColor)
                                            .frame(width: cellW, height: cellH)
                                            .onTapGesture { vm.flip(index: idx) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, hPad)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }

            // Level-up overlay
            if vm.showLevelUp {
                levelUpOverlay
            }

            // Game over overlay
            if vm.isGameOver {
                gameOverOverlay
            }
        }
        .navigationBarHidden(true)
    }

    private func statPill(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
    }

    private var levelUpOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "star.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.yellow)
                Text("Level \(vm.level) Complete!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(vm.moves) moves · \(vm.timeString)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Button { vm.nextLevel() } label: {
                    Text("Next Level →")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .cornerRadius(14)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.yellow)
                Text("You Finished!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("All \(Self.levelsCount) levels complete\n\(vm.moves) moves · \(vm.timeString)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button { vm.startLevel(1) } label: {
                    Text("Play Again")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .cornerRadius(14)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        }
    }

    private static let levelsCount = 10
}

#Preview {
    MemoryMatchView()
}
