//
//  AimMode.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


import SwiftUI
internal import Combine

// MARK: - Model

private enum AimMode: String, CaseIterable {
    case click   = "Click Speed"
    case aim     = "Aim Training"
    case reflex  = "Reflex Test"
}

private struct AimTarget: Identifiable {
    let id = UUID()
    let position: CGPoint
    let size: CGFloat
    var spawnedAt: Date = Date()
}

private struct AimResult {
    var reactionMs: Int
    var hit: Bool
}

// MARK: - ViewModel

private final class AimTrainerViewModel: ObservableObject {
    @Published var mode: AimMode = .aim
    @Published var targets: [AimTarget] = []
    @Published var score: Int = 0
    @Published var misses: Int = 0
    @Published var reactionTimes: [Int] = []
    @Published var sessionActive: Bool = false
    @Published var countdown: Int = 3
    @Published var timeLeft: Int = 30
    @Published var showResults: Bool = false
    @Published var reflexState: ReflexState = .waiting

    // Reflex mode
    enum ReflexState { case waiting, ready, go, tooEarly, done }
    @Published var reflexReactionMs: Int? = nil
    @Published var reflexHistory: [Int] = []

    private var sessionTimer: Timer?
    private var countdownTimer: Timer?
    private var reflexTimer: Timer?
    private var reflexStartTime: Date?
    private var canvasSize: CGSize = .zero

    var avgReaction: Int {
        guard !reactionTimes.isEmpty else { return 0 }
        return reactionTimes.reduce(0, +) / reactionTimes.count
    }
    var bestReaction: Int { reactionTimes.min() ?? 0 }
    var accuracy: Int {
        let total = score + misses
        guard total > 0 else { return 100 }
        return Int(Double(score) / Double(total) * 100)
    }
    var reflexAvg: Int {
        guard !reflexHistory.isEmpty else { return 0 }
        return reflexHistory.reduce(0, +) / reflexHistory.count
    }

    func setCanvas(_ size: CGSize) { canvasSize = size }

    func startSession() {
        score = 0; misses = 0; reactionTimes = []; targets = []
        timeLeft = 30; showResults = false
        countdown = 3; sessionActive = false

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.countdown > 1 {
                self.countdown -= 1
            } else {
                t.invalidate()
                self.sessionActive = true
                self.spawnTarget()
                self.startSessionTimer()
            }
        }
    }

    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.timeLeft > 1 {
                self.timeLeft -= 1
            } else {
                t.invalidate()
                self.sessionActive = false
                self.targets = []
                self.showResults = true
            }
        }
    }

    func hitTarget(_ target: AimTarget) {
        guard sessionActive else { return }
        let ms = Int(Date().timeIntervalSince(target.spawnedAt) * 1000)
        reactionTimes.append(ms)
        score += 1
        targets.removeAll { $0.id == target.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.spawnTarget()
        }
    }

    func missedTap() {
        guard sessionActive, mode == .aim else { return }
        misses += 1
    }

    private func spawnTarget() {
        guard sessionActive, canvasSize != .zero else { return }
        let size: CGFloat = mode == .aim ? CGFloat.random(in: 36...70) : 56
        let padding = size / 2 + 10
        let x = CGFloat.random(in: padding...(canvasSize.width - padding))
        let y = CGFloat.random(in: padding...(canvasSize.height - padding))
        let target = AimTarget(position: CGPoint(x: x, y: y), size: size)
        targets = [target]
    }

    // MARK: Reflex mode

    func startReflexRound() {
        reflexState = .ready
        reflexReactionMs = nil
        let delay = Double.random(in: 1.5...4.5)
        reflexTimer?.invalidate()
        reflexTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.reflexState = .go
            self?.reflexStartTime = Date()
        }
    }

    func reflexTap() {
        switch reflexState {
        case .waiting:
            startReflexRound()
        case .ready:
            reflexState = .tooEarly
            reflexTimer?.invalidate()
            reflexTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.startReflexRound()
            }
        case .go:
            if let start = reflexStartTime {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                reflexReactionMs = ms
                reflexHistory.append(ms)
                reflexState = .done
            }
        case .tooEarly, .done:
            startReflexRound()
        }
    }

    func resetReflex() {
        reflexHistory = []
        reflexState = .waiting
        reflexTimer?.invalidate()
    }

    deinit {
        sessionTimer?.invalidate()
        countdownTimer?.invalidate()
        reflexTimer?.invalidate()
    }
}

// MARK: - Main View

struct AimTrainerView: View {
    @StateObject private var vm = AimTrainerViewModel()
    @Environment(\.dismiss) private var dismiss

    private let accentColor = Color.orange

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    // Mode selector
                    if !vm.sessionActive && !vm.showResults {
                        modePicker
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    switch vm.mode {
                    case .reflex:
                        reflexView
                    default:
                        aimView
                    }
                }
            }
            // Always keep canvasSize current so spawnTarget() has valid bounds
            // even before liveAimCanvas appears.
            .onAppear { vm.setCanvas(geo.size) }
            .onChange(of: geo.size.width)  { _ in vm.setCanvas(geo.size) }
            .onChange(of: geo.size.height) { _ in vm.setCanvas(geo.size) }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            Spacer()
            Text("Aim Trainer")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
            // Placeholder for symmetry
            Image(systemName: "chevron.left").opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(AimMode.allCases, id: \.self) { m in
                Button {
                    vm.mode = m
                    vm.showResults = false
                    vm.sessionActive = false
                    vm.reflexState = .waiting
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(vm.mode == m ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(vm.mode == m ? accentColor : Color.clear)
                        .cornerRadius(10)
                }
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Aim / Click View

    private var aimView: some View {
        ZStack {
            if vm.showResults {
                resultsView
            } else if vm.sessionActive {
                liveAimCanvas
            } else if !vm.sessionActive && vm.countdown < 3 {
                // Counting down — show the number over a dim background
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                        .cornerRadius(20)
                    Text("\(vm.countdown)")
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .foregroundColor(accentColor)
                        .transition(.scale.combined(with: .opacity))
                        .id(vm.countdown)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                startPrompt
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var startPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundColor(accentColor)
            Text(vm.mode == .click ? "Click Speed Test" : "Aim Training")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(vm.mode == .click
                 ? "Tap targets as fast as possible.\n30 seconds. Ready?"
                 : "Hit the targets. Accuracy matters.\n30 seconds. Ready?")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { vm.startSession() } label: {
                Text("Start")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 160)
                    .padding(.vertical, 14)
                    .background(accentColor)
                    .cornerRadius(14)
            }
        }
        .padding()
    }

    private var liveAimCanvas: some View {
        ZStack {
            // Canvas
            GeometryReader { geo in
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                        .cornerRadius(20)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.missedTap() }

                    // Targets
                    ForEach(vm.targets) { target in
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.15))
                                .frame(width: target.size, height: target.size)
                            Circle()
                                .stroke(accentColor, lineWidth: 3)
                                .frame(width: target.size, height: target.size)
                            Circle()
                                .fill(accentColor)
                                .frame(width: 10, height: 10)
                        }
                        .position(target.position)
                        .onTapGesture { vm.hitTarget(target) }
                        .transition(.scale(scale: 0.1).combined(with: .opacity))
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: target.id)
                    }

                    // HUD
                    VStack {
                        HStack {
                            statBadge("Hits", value: "\(vm.score)", color: .green)
                            Spacer()
                            statBadge("Time", value: "\(vm.timeLeft)s", color: accentColor)
                            Spacer()
                            statBadge("Miss", value: "\(vm.misses)", color: .red)
                        }
                        .padding(12)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func statBadge(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Session Results")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .padding(.top, 20)

                // Big stat
                VStack(spacing: 4) {
                    Text("\(vm.score)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundColor(accentColor)
                    Text("Targets Hit")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Grid stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    resultCard("Accuracy", value: "\(vm.accuracy)%", icon: "scope", color: .green)
                    resultCard("Avg Reaction", value: vm.avgReaction > 0 ? "\(vm.avgReaction)ms" : "—", icon: "clock.fill", color: .blue)
                    resultCard("Best Reaction", value: vm.bestReaction > 0 ? "\(vm.bestReaction)ms" : "—", icon: "bolt.fill", color: .yellow)
                    resultCard("Misses", value: "\(vm.misses)", icon: "xmark.circle.fill", color: .red)
                }
                .padding(.horizontal, 20)

                Button { vm.startSession() } label: {
                    Text("Play Again")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 200)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .cornerRadius(14)
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func resultCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(color)
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.primary)
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    // MARK: - Reflex View

    private var reflexView: some View {
        VStack(spacing: 0) {
            // History
            if !vm.reflexHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.reflexHistory.indices, id: \.self) { i in
                            VStack(spacing: 2) {
                                Text("\(vm.reflexHistory[i])")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(reflexColor(vm.reflexHistory[i]))
                                Text("ms").font(.system(size: 9)).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(10)
                        }
                        if vm.reflexHistory.count >= 3 {
                            VStack(spacing: 2) {
                                Text("Avg")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                                Text("\(vm.reflexAvg)ms")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(accentColor)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(accentColor.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
            }

            // Big tap area
            GeometryReader { _ in
                Button(action: vm.reflexTap) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(reflexBgColor)
                            .animation(.easeInOut(duration: 0.2), value: vm.reflexState)

                        VStack(spacing: 16) {
                            Image(systemName: reflexIcon)
                                .font(.system(size: 56, weight: .medium))
                                .foregroundColor(.white)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: vm.reflexState)

                            Text(reflexLabel)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            if let ms = vm.reflexReactionMs {
                                Text("\(ms) ms")
                                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                    .transition(.scale.combined(with: .opacity))
                                Text(reflexRating(ms))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(32)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private var reflexBgColor: Color {
        switch vm.reflexState {
        case .waiting:  return Color(.systemGray3)
        case .ready:    return Color.red.opacity(0.8)
        case .go:       return Color.green
        case .tooEarly: return Color.purple.opacity(0.8)
        case .done:     return Color.blue.opacity(0.7)
        }
    }

    private var reflexIcon: String {
        switch vm.reflexState {
        case .waiting:  return "hand.tap.fill"
        case .ready:    return "hourglass"
        case .go:       return "bolt.fill"
        case .tooEarly: return "exclamationmark.triangle.fill"
        case .done:     return "checkmark.circle.fill"
        }
    }

    private var reflexLabel: String {
        switch vm.reflexState {
        case .waiting:  return "Tap to Start"
        case .ready:    return "Wait for green…"
        case .go:       return "TAP NOW!"
        case .tooEarly: return "Too early! Wait…"
        case .done:     return "Tap for next round"
        }
    }

    private func reflexColor(_ ms: Int) -> Color {
        if ms < 200 { return .green }
        if ms < 300 { return .yellow }
        return .orange
    }

    private func reflexRating(_ ms: Int) -> String {
        switch ms {
        case ..<150: return "⚡ Superhuman!"
        case ..<200: return "🔥 Elite"
        case ..<250: return "✅ Great"
        case ..<300: return "👍 Good"
        case ..<400: return "😐 Average"
        default:     return "🐢 Keep practicing"
        }
    }
}

#Preview {
    AimTrainerView()
}
