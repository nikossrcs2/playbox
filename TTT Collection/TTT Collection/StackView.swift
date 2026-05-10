//
//  StackBlock.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI
internal import Combine

// MARK: - Model

private struct StackBlock: Identifiable {
    let id = UUID()
    var x: CGFloat        // center x offset from canvas center
    var width: CGFloat
    let y: CGFloat        // vertical position (from bottom)
    let color: Color
}

private enum StackGameState {
    case playing, perfect, missed, gameOver
}

// MARK: - ViewModel

private final class StackViewModel: ObservableObject {
    // Canvas dimensions – set from view
    var canvasWidth: CGFloat = 300
    var blockHeight: CGFloat = 40

    @Published var blocks: [StackBlock] = []
    @Published var score: Int = 0
    @Published var bestScore: Int = UserDefaults.standard.integer(forKey: "stack_best")
    @Published var state: StackGameState = .playing
    @Published var movingX: CGFloat = 0
    @Published var movingWidth: CGFloat = 200
    @Published var showPerfect: Bool = false

    private var direction: CGFloat = 1
    private var speed: CGFloat = 2.5
    private var displayLink: Timer?
    private var blockColors: [Color] = [
        .cyan, .teal, .blue, .indigo, .purple,
        .pink, .red, .orange, .yellow, .green, .mint
    ]

    var movingY: CGFloat {
        CGFloat(blocks.count) * blockHeight
    }

    func start(canvasWidth: CGFloat, blockHeight: CGFloat) {
        self.canvasWidth = canvasWidth
        self.blockHeight = blockHeight
        blocks = []
        score = 0
        state = .playing
        // Base block
        let baseW = canvasWidth * 0.65
        blocks.append(StackBlock(x: 0, width: baseW, y: 0, color: blockColors[0]))
        movingWidth = baseW
        movingX = -canvasWidth / 2 + movingWidth / 2
        direction = 1
        speed = 2.8
        startLoop()
    }

    func restart(canvasWidth: CGFloat, blockHeight: CGFloat) {
        stopLoop()
        start(canvasWidth: canvasWidth, blockHeight: blockHeight)
    }

    private func startLoop() {
        stopLoop()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tick() {
        guard state == .playing else { return }
        let halfCanvas = canvasWidth / 2
        let halfBlock = movingWidth / 2

        movingX += direction * speed

        // Bounce
        if movingX + halfBlock >= halfCanvas {
            movingX = halfCanvas - halfBlock
            direction = -1
        } else if movingX - halfBlock <= -halfCanvas {
            movingX = -halfCanvas + halfBlock
            direction = 1
        }
    }

    func drop() {
        guard state == .playing else { return }
        stopLoop()

        let topBlock = blocks.last!
        let prevCenter = topBlock.x
        let prevWidth = topBlock.width

        // Overlap calculation
        let leftEdgePrev = prevCenter - prevWidth / 2
        let rightEdgePrev = prevCenter + prevWidth / 2
        let leftEdgeNew = movingX - movingWidth / 2
        let rightEdgeNew = movingX + movingWidth / 2

        let overlapLeft = max(leftEdgePrev, leftEdgeNew)
        let overlapRight = min(rightEdgePrev, rightEdgeNew)
        let overlapWidth = overlapRight - overlapLeft

        if overlapWidth <= 0 {
            // Missed completely
            state = .missed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.state = .gameOver
            }
            return
        }

        let perfectThreshold: CGFloat = 6
        let isPerfect = abs(overlapWidth - prevWidth) < perfectThreshold

        let newCenter = (overlapLeft + overlapRight) / 2
        let actualWidth = isPerfect ? prevWidth : overlapWidth
        let actualCenter = isPerfect ? prevCenter : newCenter

        score += isPerfect ? 2 : 1
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "stack_best")
        }

        if isPerfect {
            showPerfect = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPerfect = false
            }
        }

        let colorIdx = blocks.count % blockColors.count
        let newBlock = StackBlock(
            x: actualCenter,
            width: actualWidth,
            y: CGFloat(blocks.count) * blockHeight,
            color: blockColors[colorIdx]
        )
        blocks.append(newBlock)

        // Prepare next moving block
        movingWidth = actualWidth
        // Speed increases slightly
        speed = min(speed + 0.08, 6.5)

        // Start from alternating side
        let halfCanvas = canvasWidth / 2
        if direction > 0 {
            movingX = -halfCanvas + movingWidth / 2
            direction = 1
        } else {
            movingX = halfCanvas - movingWidth / 2
            direction = -1
        }

        startLoop()
    }

    deinit { stopLoop() }
}

// MARK: - View

struct StackView: View {
    @StateObject private var vm = StackViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var canvasSize: CGSize = .zero

    private let blockH: CGFloat = 44
    private let accentColor = Color.cyan

    var body: some View {
        ZStack {
            // Dark background
            LinearGradient(
                colors: [Color(white: 0.06), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(vm.score)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("BEST: \(vm.bestScore)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                            .kerning(1.5)
                    }
                    Spacer()
                    Button {
                        vm.restart(canvasWidth: canvasSize.width, blockHeight: blockH)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Perfect label
                Text("PERFECT +2")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.yellow)
                    .kerning(2)
                    .opacity(vm.showPerfect ? 1 : 0)
                    .scaleEffect(vm.showPerfect ? 1 : 0.7)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: vm.showPerfect)
                    .frame(height: 22)

                // Canvas
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    // Camera follows the top: shift so top block is always visible
                    let visibleBlocks = Int(h / blockH) + 2
                    let cameraOffset = max(0, CGFloat(vm.blocks.count + 1) - CGFloat(visibleBlocks))
                    let yShift = cameraOffset * blockH

                    ZStack(alignment: .bottom) {
                        // Placed blocks
                        ForEach(vm.blocks) { block in
                            let drawY = h - (block.y + blockH - yShift)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(block.color)
                                .frame(width: block.width, height: blockH - 3)
                                .offset(x: block.x, y: drawY - h / 2)
                                .shadow(color: block.color.opacity(0.5), radius: 4, y: 2)
                        }

                        // Moving block
                        if vm.state == .playing || vm.state == .missed {
                            let drawY = h - (vm.movingY + blockH - yShift)
                            let colorIdx = vm.blocks.count % 11
                            RoundedRectangle(cornerRadius: 6)
                                .fill(stackColor(index: colorIdx))
                                .frame(width: vm.movingWidth, height: blockH - 3)
                                .offset(x: vm.movingX, y: drawY - h / 2)
                                .shadow(color: stackColor(index: colorIdx).opacity(0.6), radius: 8, y: 3)
                                .opacity(vm.state == .missed ? 0 : 1)
                                .animation(vm.state == .missed ? .easeIn(duration: 0.4) : nil,
                                           value: vm.state)
                        }

                        // Missed flash
                        if vm.state == .missed {
                            Color.red.opacity(0.3)
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: w, height: h)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.drop() }
                    .onAppear {
                        canvasSize = CGSize(width: w, height: h)
                        vm.start(canvasWidth: w, blockHeight: blockH)
                    }
                    .onChange(of: geo.size.width) { _ in
                        canvasSize = geo.size
                    }
                    .onChange(of: geo.size.height) { _ in
                        canvasSize = geo.size
                    }
                }
            }

            // Game over overlay
            if vm.state == .gameOver {
                gameOverOverlay
            }
        }
        .navigationBarHidden(true)
    }

    private func stackColor(index: Int) -> Color {
        let colors: [Color] = [
            .cyan, .teal, .blue, .indigo, .purple,
            .pink, .red, .orange, .yellow, .green, .mint
        ]
        return colors[index % colors.count]
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("💥")
                    .font(.system(size: 52))
                Text("Game Over")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                VStack(spacing: 6) {
                    Text("Score: \(vm.score)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(accentColor)
                    if vm.score >= vm.bestScore {
                        Text("🎉 New Best!")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.yellow)
                    } else {
                        Text("Best: \(vm.bestScore)")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                Button {
                    vm.restart(canvasWidth: canvasSize.width, blockHeight: blockH)
                } label: {
                    Text("Try Again")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .cornerRadius(14)
                }
            }
            .padding(36)
            .background(.ultraThinMaterial)
            .cornerRadius(28)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.state)
        }
    }
}

#Preview {
    StackView()
}
