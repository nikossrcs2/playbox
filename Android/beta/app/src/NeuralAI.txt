//
//  NeuralNet.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//


// NeuralAI.swift
// TTT Collection — Trainable Neural-Network AI
//
// Architecture: 2-layer feedforward net with ReLU + sigmoid output.
// Learning:     Temporal-difference Q-learning (self-play episodes).
// Persistence:  Weights saved to UserDefaults as JSON; one model per GameType.
//
// Each game encodes its state as a [Float] input vector and exposes a list of
// legal action indices; the net outputs a Q-value per action.

import Foundation
import SwiftUI
internal import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Matrix helpers (pure Swift, no Accelerate dependency)
// ─────────────────────────────────────────────────────────────────────────────

private func matMul(_ A: [[Float]], _ B: [[Float]]) -> [[Float]] {
    let r = A.count, m = B.count, c = B[0].count
    var C = Array(repeating: Array(repeating: Float(0), count: c), count: r)
    for i in 0..<r { for k in 0..<m { for j in 0..<c { C[i][j] += A[i][k] * B[k][j] } } }
    return C
}

private func relu(_ v: [Float]) -> [Float] { v.map { max(0, $0) } }
private func sigmoid(_ v: [Float]) -> [Float] { v.map { 1 / (1 + exp(-$0)) } }
private func tanh_act(_ v: [Float]) -> [Float] { v.map { tanh($0) } }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NeuralNet
// ─────────────────────────────────────────────────────────────────────────────

class NeuralNet: Codable {
    var W1: [[Float]]   // hidden layer weights  [hiddenSize × inputSize]
    var b1: [Float]     // hidden biases
    var W2: [[Float]]   // output layer weights  [outputSize × hiddenSize]
    var b2: [Float]     // output biases

    init(inputSize: Int, hiddenSize: Int, outputSize: Int) {
        let scale1 = Float(sqrt(2.0 / Double(inputSize)))
        let scale2 = Float(sqrt(2.0 / Double(hiddenSize)))
        W1 = (0..<hiddenSize).map { _ in (0..<inputSize).map { _ in Float.random(in: -scale1...scale1) } }
        b1 = Array(repeating: 0, count: hiddenSize)
        W2 = (0..<outputSize).map { _ in (0..<hiddenSize).map { _ in Float.random(in: -scale2...scale2) } }
        b2 = Array(repeating: 0, count: outputSize)
    }

    /// Forward pass → Q-values for each action
    func forward(input: [Float]) -> [Float] {
        // Hidden
        let h = (0..<W1.count).map { i in
            b1[i] + zip(W1[i], input).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let h2 = relu(h)
        // Output (tanh → range -1..1 works well for game values)
        return (0..<W2.count).map { i in
            tanh(b2[i] + zip(W2[i], h2).reduce(0) { $0 + $1.0 * $1.1 })
        }
    }

    /// Gradient-based update (simple TD with MSE).
    func update(input: [Float], actionIndex: Int, target: Float, lr: Float) {
        // Forward
        let h_pre = (0..<W1.count).map { i in
            b1[i] + zip(W1[i], input).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let h = relu(h_pre)
        let o_pre = (0..<W2.count).map { i in
            b2[i] + zip(W2[i], h).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let q = tanh(o_pre[actionIndex])

        // Output error
        let delta_out = (target - q) * (1 - q * q)   // chain through tanh'

        // Update W2, b2 for actionIndex only
        for j in 0..<W2[actionIndex].count {
            W2[actionIndex][j] += lr * delta_out * h[j]
        }
        b2[actionIndex] += lr * delta_out

        // Backprop to hidden
        let delta_h = (0..<W1.count).map { j -> Float in
            (h_pre[j] > 0 ? 1 : Float(0)) * W2[actionIndex][j] * delta_out
        }
        for i in 0..<W1.count {
            for k in 0..<W1[i].count {
                W1[i][k] += lr * delta_h[i] * input[k]
            }
            b1[i] += lr * delta_h[i]
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NeuralAIModel  (one per GameType, persisted)
// ─────────────────────────────────────────────────────────────────────────────

class NeuralAIModel: ObservableObject {
    let gameType: GameType
    @Published var trainedEpisodes: Int = 0
    @Published var isTraining: Bool = false
    @Published var lastWinRate: Double = 0.0

    private(set) var net: NeuralNet
    private let hiddenSize = 64
    private let lr: Float = 0.005
    private let gamma: Float = 0.95
    private let epsilon0: Float = 0.9    // exploration start
    private let epsilonMin: Float = 0.05
    private var epsilon: Float

    init(gameType: GameType) {
        self.gameType = gameType
        let sizes = NeuralAIModel.archForGame(gameType)
        self.net = NeuralNet(inputSize: sizes.0, hiddenSize: 64, outputSize: sizes.1)
        self.epsilon = epsilon0
        load()
    }

    // ── Persistence ──────────────────────────────

    private var defaultsKey: String { "neural_ai_\(gameType.rawValue)" }
    private var episodesKey: String { "neural_eps_\(gameType.rawValue)" }
    private var winrateKey:  String { "neural_wr_\(gameType.rawValue)" }

    func save() {
        if let data = try? JSONEncoder().encode(net) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        UserDefaults.standard.set(trainedEpisodes, forKey: episodesKey)
        UserDefaults.standard.set(lastWinRate, forKey: winrateKey)
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let loaded = try? JSONDecoder().decode(NeuralNet.self, from: data) {
            net = loaded
        }
        trainedEpisodes = UserDefaults.standard.integer(forKey: episodesKey)
        lastWinRate = UserDefaults.standard.double(forKey: winrateKey)
        epsilon = max(epsilonMin, epsilon0 - Float(trainedEpisodes) / 5000.0)
    }

    func reset() {
        let sizes = NeuralAIModel.archForGame(gameType)
        net = NeuralNet(inputSize: sizes.0, hiddenSize: hiddenSize, outputSize: sizes.1)
        trainedEpisodes = 0
        lastWinRate = 0
        epsilon = epsilon0
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: episodesKey)
        UserDefaults.standard.removeObject(forKey: winrateKey)
    }

    // ── Network dimensions per game ──────────────
    // (inputSize, actionCount)
    static func archForGame(_ g: GameType) -> (Int, Int) {
        switch g {
        case .classic:    return (9, 9)       // 9 cells (0=empty,1=X,-1=O)
        case .wild:       return (9, 18)      // same board; actions = cell×piece (9×2)
        case .connect4:   return (42, 7)      // 6×7 board; actions = columns
        case .notakto:    return (27, 27)     // 3 boards × 9 cells
        case .superTTT:   return (81, 81)     // 9 boards × 9 cells
        case .checkers:   return (64, 64)     // simplified flat board
        default:          return (9, 9)
        }
    }

    // ── Inference ────────────────────────────────

    /// Pick the best legal action given a state vector and list of legal actions.
    func pickAction(state: [Float], legalActions: [Int], explore: Bool = false) -> Int {
        if explore && Float.random(in: 0...1) < epsilon {
            return legalActions.randomElement() ?? legalActions[0]
        }
        let q = net.forward(input: state)
        return legalActions.max(by: { q[$0] < q[$1] }) ?? legalActions[0]
    }

    // ── Training (self-play) ──────────────────────

    func trainAsync(episodes: Int, completion: @escaping (Double) -> Void) {
        guard !isTraining else { return }
        isTraining = true

        // Capture epsilon as a local value so the background thread never
        // touches the instance property directly (fixes data race).
        let startEpsilon = epsilon

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var eps = startEpsilon
            var wins = 0
            let trainer = SelfPlayTrainer(gameType: self.gameType, net: self.net,
                                          gamma: self.gamma, lr: self.lr)
            for _ in 0..<episodes {
                let result = trainer.runEpisode(epsilon: eps)
                if result > 0 { wins += 1 }
                eps = max(self.epsilonMin, eps - 0.0002)
            }

            let wr = Double(wins) / Double(episodes)
            let finalEpsilon = eps
            DispatchQueue.main.async {
                self.epsilon = finalEpsilon   // write back on main thread
                self.trainedEpisodes += episodes
                self.lastWinRate = wr
                self.isTraining = false
                self.save()
                completion(wr)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SelfPlayTrainer
// ─────────────────────────────────────────────────────────────────────────────

private class SelfPlayTrainer {
    let gameType: GameType
    let net: NeuralNet
    let gamma: Float
    let lr: Float

    init(gameType: GameType, net: NeuralNet, gamma: Float, lr: Float) {
        self.gameType = gameType; self.net = net; self.gamma = gamma; self.lr = lr
    }

    /// Returns +1 if X won, -1 if O won, 0 if draw.
    func runEpisode(epsilon: Float) -> Int {
        switch gameType {
        case .classic, .notakto, .wild:
            return runTTTEpisode(epsilon: epsilon)
        case .connect4:
            return runC4Episode(epsilon: epsilon)
        case .superTTT:
            return runSuperTTTEpisode(epsilon: epsilon)
        default:
            return runTTTEpisode(epsilon: epsilon)
        }
    }

    // ── Classic / Notakto / Wild episode ─────────

    private func runTTTEpisode(epsilon: Float) -> Int {
        var board = [Player?](repeating: nil, count: 9)
        var turn = Player.x
        var transitions: [(state: [Float], action: Int, player: Player)] = []

        while true {
            let state = encode(board: board, player: turn)
            let legal = (0..<9).filter { board[$0] == nil }
            guard !legal.isEmpty else {
                // Draw
                for t in transitions { net.update(input: t.state, actionIndex: t.action, target: 0, lr: lr) }
                return 0
            }

            let action: Int
            if Float.random(in: 0...1) < epsilon {
                action = legal.randomElement()!
            } else {
                let q = net.forward(input: state)
                action = legal.max(by: { q[$0] < q[$1] })!
            }

            transitions.append((state, action, turn))
            board[action] = turn

            if let (winner, _) = WinChecker.checkWinner(board: board) {
                // Winner gets +1, loser -1
                for t in transitions {
                    let reward: Float = t.player == winner ? 1.0 : -1.0
                    net.update(input: t.state, actionIndex: t.action, target: reward, lr: lr)
                }
                return winner == Player.x ? 1 : -1
            }
            turn = turn.opposite
        }
    }

    // ── Connect 4 episode ────────────────────────

    private func runC4Episode(epsilon: Float) -> Int {
        var board = [[Player?]](repeating: [Player?](repeating: nil, count: 7), count: 6)
        var turn = Player.x
        var transitions: [(state: [Float], action: Int, player: Player)] = []

        while true {
            let state = encodeC4(board: board, player: turn)
            let legal = (0..<7).filter { MinimaxAI.c4DropRow(board: board, col: $0) != nil }
            guard !legal.isEmpty else {
                for t in transitions { net.update(input: t.state, actionIndex: t.action, target: 0, lr: lr) }
                return 0
            }

            let action: Int
            if Float.random(in: 0...1) < epsilon {
                action = legal.randomElement()!
            } else {
                let q = net.forward(input: state)
                action = legal.max(by: { q[$0] < q[$1] })!
            }

            transitions.append((state, action, turn))
            if let row = MinimaxAI.c4DropRow(board: board, col: action) {
                board[row][action] = turn
            }

            if let winner = WinChecker.c4CheckWinner(board: board) {
                for t in transitions {
                    net.update(input: t.state, actionIndex: t.action, target: t.player == winner ? 1.0 : -1.0, lr: lr)
                }
                return winner == .x ? 1 : -1
            }
            turn = turn.opposite
        }
    }

    // ── Super TTT episode ────────────────────────

    private func runSuperTTTEpisode(epsilon: Float) -> Int {
        // Initialize Super TTT state
        var boards = [[Player?]](repeating: [Player?](repeating: nil, count: 9), count: 9)
        var boardResults = [GameResult](repeating: .ongoing, count: 9)
        var activeBoard: Int? = nil
        var currentPlayer = Player.x
        var transitions: [(state: [Float], action: Int, player: Player)] = []
        
        while true {
            // Encode current state
            let state = encodeSuperTTTState(boards: boards, boardResults: boardResults, activeBoard: activeBoard, player: currentPlayer)
            
            // Get valid actions (board * 9 + cell)
            let validBoards = activeBoard.map { [$0] } ?? (0..<9).filter { boardResults[$0] == .ongoing }
            var legalActions: [Int] = []
            for bIdx in validBoards {
                for cIdx in 0..<9 where boards[bIdx][cIdx] == nil {
                    legalActions.append(bIdx * 9 + cIdx)
                }
            }
            
            guard !legalActions.isEmpty else {
                // Draw - update all transitions with 0 reward
                for t in transitions {
                    net.update(input: t.state, actionIndex: t.action, target: 0, lr: lr)
                }
                return 0
            }
            
            // Choose action
            let action: Int
            if Float.random(in: 0...1) < epsilon {
                action = legalActions.randomElement()!
            } else {
                let q = net.forward(input: state)
                action = legalActions.max(by: { q[$0] < q[$1] })!
            }
            
            transitions.append((state, action, currentPlayer))
            
            // Apply action
            let bIdx = action / 9
            let cIdx = action % 9
            boards[bIdx][cIdx] = currentPlayer
            
            // Check mini-board win
            let miniResult = WinChecker.result(board: boards[bIdx])
            if miniResult != .ongoing {
                boardResults[bIdx] = miniResult
            }
            
            // Check global win - convert boardResults to [Player?]
            var globalBoardState: [Player?] = []
            for result in boardResults {
                switch result {
                case .win(let winner, _):
                    globalBoardState.append(winner)
                default:
                    globalBoardState.append(nil)
                }
            }
            
            if let (winner, _) = WinChecker.checkWinner(board: globalBoardState) {
                for t in transitions {
                    let reward: Float = t.player == winner ? 1.0 : -1.0
                    net.update(input: t.state, actionIndex: t.action, target: reward, lr: lr)
                }
                return winner == Player.x ? 1 : -1
            }
            
            // Check for draw (all boards dead)
            let allDead = boardResults.allSatisfy { $0 != .ongoing }
            if allDead {
                for t in transitions {
                    net.update(input: t.state, actionIndex: t.action, target: 0, lr: lr)
                }
                return 0
            }
            
            // Update for next turn
            let nextBoard = (cIdx < 9 && boardResults[cIdx] == .ongoing) ? cIdx : nil
            activeBoard = nextBoard
            currentPlayer = currentPlayer.opposite
        }
    }

    // ── Encoders ─────────────────────────────────

    private func encode(board: [Player?], player: Player) -> [Float] {
        board.map { cell -> Float in
            guard let c = cell else { return 0 }
            return c == player ? 1 : -1
        }
    }

    private func encodeC4(board: [[Player?]], player: Player) -> [Float] {
        board.flatMap { row in
            row.map { cell -> Float in
                guard let c = cell else { return 0 }
                return c == player ? 1 : -1
            }
        }
    }
    
    private func encodeSuperTTTState(boards: [[Player?]], boardResults: [GameResult], activeBoard: Int?, player: Player) -> [Float] {
        // Encode all mini-boards (9x9 = 81 cells)
        var encoded = [Float]()
        for bIdx in 0..<9 {
            for cIdx in 0..<9 {
                if let p = boards[bIdx][cIdx] {
                    encoded.append(p == player ? 1 : -1)
                } else {
                    encoded.append(0)
                }
            }
        }
        return encoded
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NeuralAIStore (app-wide singleton)
// ─────────────────────────────────────────────────────────────────────────────

class NeuralAIStore: ObservableObject {
    static let shared = NeuralAIStore()
    private var models: [GameType: NeuralAIModel] = [:]

    func model(for game: GameType) -> NeuralAIModel {
        if let m = models[game] { return m }
        let m = NeuralAIModel(gameType: game)
        models[game] = m
        return m
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NeuralAITrainingView  (embed in any game's sheet or tab)
// ─────────────────────────────────────────────────────────────────────────────

struct NeuralAITrainingView: View {
    let gameType: GameType
    @ObservedObject var model: NeuralAIModel
    @State private var batchSize = 200
    @State private var showResetConfirm = false
    @State private var lastWinRateDisplay: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Stats card ──────────────────
                    VStack(spacing: 16) {
                        HStack {
                            statBox(title: "Episodes Trained", value: "\(model.trainedEpisodes)", color: gameType.accentColor)
                            statBox(title: "Win Rate (last batch)", value: winRateStr, color: .green)
                        }

                        // Progress bar (episodes toward "mastery" ~5000)
                        let progress = min(1.0, Double(model.trainedEpisodes) / 5000.0)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Training Progress")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(gameType.accentColor)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(height: 10)
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(gameType.accentColor)
                                        .frame(width: g.size.width * CGFloat(progress), height: 10)
                                }
                            }.frame(height: 10)
                        }
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)

                    // ── Batch size picker ───────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Training Batch Size")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            ForEach([50, 200, 500, 1000], id: \.self) { n in
                                Button {
                                    batchSize = n
                                } label: {
                                    Text("\(n)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(batchSize == n ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(batchSize == n ? gameType.accentColor : Color(.systemGray5))
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)

                    // ── Train button ────────────────
                    Button {
                        model.trainAsync(episodes: batchSize) { wr in
                            lastWinRateDisplay = String(format: "%.0f%%", wr * 100)
                        }
                    } label: {
                        Group {
                            if model.isTraining {
                                HStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Training \(batchSize) episodes…")
                                }
                            } else {
                                Label("Train \(batchSize) Episodes", systemImage: "brain.head.profile")
                            }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(model.isTraining ? Color.gray : gameType.accentColor)
                        .cornerRadius(14)
                    }
                    .disabled(model.isTraining)

                    // ── How-to ──────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Label("How Training Works", systemImage: "info.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(gameType.accentColor)

                        Text("The AI plays thousands of games against itself using Q-learning. It gets rewarded for winning and penalised for losing. After enough training it learns good strategies — then you can challenge it in-game by selecting **Neural AI** as the difficulty.\n\nWeights are saved on your device and persist across sessions. More episodes = smarter AI (aim for 3000+).")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)

                    // ── Reset ───────────────────────
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset Trained Weights", systemImage: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .confirmationDialog("Reset AI?", isPresented: $showResetConfirm) {
                        Button("Reset", role: .destructive) { model.reset() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will erase all trained weights for \(gameType.title).")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Train Neural AI — \(gameType.title)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private var winRateStr: String {
        model.trainedEpisodes == 0 ? "—" : String(format: "%.0f%%", model.lastWinRate * 100)
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - NeuralAI action helpers  (called from game views)
// ─────────────────────────────────────────────────────────────────────────────
// These are pure-Swift helpers so game views don't need to know about net internals.

extension NeuralAIModel {
    // ── Classic TTT ──────────────────────────────
    func pickTTTMove(board: [Player?], player: Player) -> Int {
        let state = board.map { cell -> Float in
            guard let c = cell else { return 0 }
            return c == player ? 1 : -1
        }
        let legal = (0..<9).filter { board[$0] == nil }
        return pickAction(state: state, legalActions: legal, explore: false)
    }

    // ── Connect 4 ────────────────────────────────
    func pickC4Move(board: [[Player?]], player: Player) -> Int {
        let state = board.flatMap { row in
            row.map { cell -> Float in
                guard let c = cell else { return 0 }
                return c == player ? 1 : -1
            }
        }
        let legal = (0..<7).filter { MinimaxAI.c4DropRow(board: board, col: $0) != nil }
        return pickAction(state: state, legalActions: legal, explore: false)
    }

    // ── Wild TTT ────────────────────────────────
    // Actions encoded as: 0-8 = place X in cell 0-8, 9-17 = place O in cell 0-8
    func pickWildMove(board: [Player?], player: Player) -> (Int, Player) {
        let state = board.map { cell -> Float in
            guard let c = cell else { return 0 }
            return c == player ? 1 : -1
        }
        let legalX = (0..<9).filter { board[$0] == nil }
        let legalO = legalX.map { $0 + 9 }
        let legal = legalX + legalO
        let action = pickAction(state: state, legalActions: legal, explore: false)
        if action < 9 { return (action, .x) } else { return (action - 9, .o) }
    }
    
    // ── Super TTT ────────────────────────────────
    func pickSuperTTTMove(boards: [[Player?]], boardResults: [GameResult], activeBoard: Int?, player: Player) -> (Int, Int)? {
        let state = encodeSuperTTTState(boards: boards, boardResults: boardResults, activeBoard: activeBoard, player: player)
        
        // Get valid actions
        let validBoards = activeBoard.map { [$0] } ?? (0..<9).filter { boardResults[$0] == .ongoing }
        var legalActions: [Int] = []
        for bIdx in validBoards {
            for cIdx in 0..<9 where boards[bIdx][cIdx] == nil {
                legalActions.append(bIdx * 9 + cIdx)
            }
        }
        
        guard !legalActions.isEmpty else { return nil }
        let action = pickAction(state: state, legalActions: legalActions, explore: false)
        return (action / 9, action % 9)
    }
    
    private func encodeSuperTTTState(boards: [[Player?]], boardResults: [GameResult], activeBoard: Int?, player: Player) -> [Float] {
        var encoded = [Float]()
        for bIdx in 0..<9 {
            for cIdx in 0..<9 {
                if let p = boards[bIdx][cIdx] {
                    encoded.append(p == player ? 1 : -1)
                } else {
                    encoded.append(0)
                }
            }
        }
        return encoded
    }
}

#Preview {
    NeuralAITrainingView(
        gameType: .classic,
        model: NeuralAIStore.shared.model(for: .classic)
    )
}
