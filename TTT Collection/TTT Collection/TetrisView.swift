import SwiftUI
internal import Combine

// MARK: - Tetromino Definitions

enum TetrominoType: Int, CaseIterable {
    case I, O, T, S, Z, J, L

    var color: Color {
        switch self {
        case .I: return Color(red: 0.0, green: 0.84, blue: 0.93)   // Cyan
        case .O: return Color(red: 1.0,  green: 0.84, blue: 0.0)   // Yellow
        case .T: return Color(red: 0.6,  green: 0.2,  blue: 0.8)   // Purple
        case .S: return Color(red: 0.2,  green: 0.8,  blue: 0.3)   // Green
        case .Z: return Color(red: 0.93, green: 0.2,  blue: 0.2)   // Red
        case .J: return Color(red: 0.2,  green: 0.3,  blue: 0.9)   // Blue
        case .L: return Color(red: 1.0,  green: 0.55, blue: 0.0)   // Orange
        }
    }

    /// All 4 rotation states as arrays of (col, row) offsets from pivot
    var rotations: [[(Int, Int)]] {
        switch self {
        case .I:
            return [
                [(0,1),(1,1),(2,1),(3,1)],
                [(2,0),(2,1),(2,2),(2,3)],
                [(0,2),(1,2),(2,2),(3,2)],
                [(1,0),(1,1),(1,2),(1,3)]
            ]
        case .O:
            return [
                [(1,0),(2,0),(1,1),(2,1)],
                [(1,0),(2,0),(1,1),(2,1)],
                [(1,0),(2,0),(1,1),(2,1)],
                [(1,0),(2,0),(1,1),(2,1)]
            ]
        case .T:
            return [
                [(1,0),(0,1),(1,1),(2,1)],
                [(1,0),(1,1),(2,1),(1,2)],
                [(0,1),(1,1),(2,1),(1,2)],
                [(1,0),(0,1),(1,1),(1,2)]
            ]
        case .S:
            return [
                [(1,0),(2,0),(0,1),(1,1)],
                [(1,0),(1,1),(2,1),(2,2)],
                [(1,1),(2,1),(0,2),(1,2)],
                [(0,0),(0,1),(1,1),(1,2)]
            ]
        case .Z:
            return [
                [(0,0),(1,0),(1,1),(2,1)],
                [(2,0),(1,1),(2,1),(1,2)],
                [(0,1),(1,1),(1,2),(2,2)],
                [(1,0),(0,1),(1,1),(0,2)]
            ]
        case .J:
            return [
                [(0,0),(0,1),(1,1),(2,1)],
                [(1,0),(2,0),(1,1),(1,2)],
                [(0,1),(1,1),(2,1),(2,2)],
                [(1,0),(1,1),(0,2),(1,2)]
            ]
        case .L:
            return [
                [(2,0),(0,1),(1,1),(2,1)],
                [(1,0),(1,1),(1,2),(2,2)],
                [(0,1),(1,1),(2,1),(0,2)],
                [(0,0),(1,0),(1,1),(1,2)]
            ]
        }
    }
}

// MARK: - Piece

struct TetrisPiece {
    var type: TetrominoType
    var rotation: Int = 0
    var col: Int       // left anchor column
    var row: Int       // top anchor row

    var cells: [(Int, Int)] {
        type.rotations[rotation].map { (col + $0.0, row + $0.1) }
    }

    func rotated(by delta: Int) -> TetrisPiece {
        var p = self
        p.rotation = (rotation + delta + 4) % 4
        return p
    }
    func moved(dc: Int = 0, dr: Int = 0) -> TetrisPiece {
        var p = self; p.col += dc; p.row += dr; return p
    }
}

// MARK: - Game Engine

class TetrisGame: ObservableObject {
    static let cols = 10
    static let rows = 20

    @Published var board: [[Color?]] = Array(
        repeating: Array(repeating: nil, count: TetrisGame.cols),
        count: TetrisGame.rows
    )
    @Published var current: TetrisPiece?
    @Published var next: TetrominoType = TetrominoType.allCases.randomElement()!
    @Published var score: Int = 0
    @Published var level: Int = 1
    @Published var linesCleared: Int = 0
    @Published var isGameOver = false
    @Published var isPaused = false

    private var bag: [TetrominoType] = []
    private var timer: AnyCancellable?

    init() { spawnPiece() }

    // MARK: Bag randomiser (7-bag)
    private func nextFromBag() -> TetrominoType {
        if bag.isEmpty { bag = TetrominoType.allCases.shuffled() }
        return bag.removeFirst()
    }

    private func drawFromBag() -> TetrominoType {
        if bag.isEmpty { bag = TetrominoType.allCases.shuffled() }
        let t = bag.first!
        bag.removeFirst()
        return t
    }

    func startTimer() {
        stopTimer() // Always stop existing timer first
        let interval = max(0.1, 0.8 - Double(level - 1) * 0.07)
        timer = Timer.publish(every: interval, on: .main, in: .common) // Changed to .common mode
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stopTimer() { timer?.cancel() }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            stopTimer()
        } else {
            startTimer()
        }
    }

    func restart() {
        board = Array(repeating: Array(repeating: nil, count: TetrisGame.cols), count: TetrisGame.rows)
        score = 0; level = 1; linesCleared = 0; isGameOver = false; isPaused = false
        bag = []
        next = drawFromBag()
        spawnPiece()
        startTimer()
    }

    // MARK: Spawn

    private func spawnPiece() {
        let type = next
        next = drawFromBag()
        let startCol = TetrisGame.cols / 2 - 2
        let piece = TetrisPiece(type: type, rotation: 0, col: startCol, row: 0)
        if !isValid(piece) {
            isGameOver = true
            stopTimer()
        } else {
            current = piece
        }
    }

    // MARK: Validation

    private func isValid(_ piece: TetrisPiece) -> Bool {
        for (c, r) in piece.cells {
            if c < 0 || c >= TetrisGame.cols { return false }
            if r >= TetrisGame.rows { return false }
            if r >= 0 && board[r][c] != nil { return false }
        }
        return true
    }

    // MARK: Actions

    func moveLeft()  { move(dc: -1) }
    func moveRight() { move(dc:  1) }
    func softDrop()  { move(dr:  1) }

    private func move(dc: Int = 0, dr: Int = 0) {
        guard !isPaused, !isGameOver, let p = current else { return }
        let moved = p.moved(dc: dc, dr: dr)
        if isValid(moved) { current = moved }
        else if dr == 1   { lock() }
    }

    func rotate(clockwise: Bool = true) {
        guard !isPaused, !isGameOver, let p = current else { return }
        let rotated = p.rotated(by: clockwise ? 1 : -1)
        // Wall-kick attempts: 0, ±1, ±2
        for kick in [0, -1, 1, -2, 2] {
            let kicked = rotated.moved(dc: kick)
            if isValid(kicked) { current = kicked; return }
        }
    }

    func hardDrop() {
        guard !isPaused, !isGameOver, var p = current else { return }
        var dropped = 0
        while isValid(p.moved(dr: 1)) { p = p.moved(dr: 1); dropped += 1 }
        current = p
        score += dropped * 2
        lock()
    }

    func ghostRow() -> [(Int, Int)] {
        guard let p = current else { return [] }
        var ghost = p
        while isValid(ghost.moved(dr: 1)) { ghost = ghost.moved(dr: 1) }
        return ghost.cells
    }

    // MARK: Locking

    private func lock() {
        guard let p = current else { return }
        for (c, r) in p.cells where r >= 0 {
            board[r][c] = p.type.color
        }
        clearLines()
        spawnPiece()
    }

    private func clearLines() {
        var cleared = 0
        var newBoard: [[Color?]] = []
        for row in board {
            if row.allSatisfy({ $0 != nil }) { cleared += 1 }
            else { newBoard.append(row) }
        }
        let empty = Array(repeating: Array(repeating: nil as Color?, count: TetrisGame.cols), count: cleared)
        board = empty + newBoard
        linesCleared += cleared
        score += [0, 100, 300, 500, 800][min(cleared, 4)] * level
        level = linesCleared / 10 + 1
        if cleared > 0 { startTimer() } // reset speed for new level
    }

    // MARK: Tick

    private func tick() {
        guard !isPaused, !isGameOver, let p = current else { return }
        let moved = p.moved(dr: 1)
        if isValid(moved) { current = moved }
        else { lock() }
    }
}

// MARK: - TetrisView

struct TetrisView: View {
    @StateObject private var game = TetrisGame()
    @State private var dragStart: CGFloat? = nil
    
    // Fixed chrome heights so cell size can be derived from what remains
    private let topBarHeight: CGFloat = 44
    private let controlsHeight: CGFloat = 72
    private let sidePanelWidth: CGFloat = 80
    private let hPadding: CGFloat = 16   // each side
    
    var body: some View {
        GeometryReader { geo in
            // Available height after safe areas, top bar, controls, and small gaps
            let safeH = geo.size.height
            let safeW = geo.size.width
            let boardAreaH = safeH - topBarHeight - controlsHeight - 8
            let boardAreaW = safeW - hPadding * 2 - sidePanelWidth - 12  // 12 = HStack gap
            
            // Cell size = min of width-fit and height-fit, clamped to reasonable range
            let cellFromW = floor(boardAreaW / CGFloat(TetrisGame.cols))
            let cellFromH = floor(boardAreaH / CGFloat(TetrisGame.rows))
            let cellSize = min(cellFromW, cellFromH)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    topBar
                        .frame(height: topBarHeight)
                    
                    HStack(alignment: .top, spacing: 12) {
                        boardView(cellSize: cellSize)
                        sidePanel(cellSize: cellSize)
                    }
                    .padding(.horizontal, hPadding)
                    
                    Spacer(minLength: 0)
                    
                    controls(cellSize: cellSize)
                        .frame(height: controlsHeight)
                }
            }
            .overlay {
                if game.isGameOver { gameOverOverlay }
                if game.isPaused && !game.isGameOver { pauseOverlay }
            }
        }
        .onAppear { game.startTimer() }
        .onDisappear { game.stopTimer() }
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack {
            Text("TETRIS")
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Button { game.togglePause() } label: {
                Image(systemName: game.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, hPadding)
        .padding(.top, 4)
    }

    // MARK: Board

    private func boardView(cellSize: CGFloat) -> some View {
        let ghostCells = Set(game.ghostRow().map { "\($0.0),\($0.1)" })
        let activeCells = Dictionary(uniqueKeysWithValues: (game.current?.cells ?? []).map {
            ("\($0.0),\($0.1)", game.current!.type.color)
        })

        return Canvas { ctx, size in
            let cw = size.width / CGFloat(TetrisGame.cols)
            let ch = size.height / CGFloat(TetrisGame.rows)
            let gap: CGFloat = 1

            for r in 0..<TetrisGame.rows {
                for c in 0..<TetrisGame.cols {
                    let rect = CGRect(x: CGFloat(c)*cw+gap, y: CGFloat(r)*ch+gap,
                                      width: cw-gap*2, height: ch-gap*2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(Color.white.opacity(0.04)))
                }
            }

            for r in 0..<TetrisGame.rows {
                for c in 0..<TetrisGame.cols {
                    guard let color = game.board[r][c] else { continue }
                    let rect = CGRect(x: CGFloat(c)*cw+gap, y: CGFloat(r)*ch+gap,
                                      width: cw-gap*2, height: ch-gap*2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
                    let highlight = CGRect(x: CGFloat(c)*cw+gap, y: CGFloat(r)*ch+gap,
                                           width: cw-gap*2, height: (ch-gap*2)*0.3)
                    ctx.fill(Path(roundedRect: highlight, cornerRadius: 2),
                             with: .color(Color.white.opacity(0.25)))
                }
            }

            for key in ghostCells where activeCells[key] == nil {
                let parts = key.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                let (gc, gr) = (parts[0], parts[1])
                if gr < 0 { continue }
                let rect = CGRect(x: CGFloat(gc)*cw+gap, y: CGFloat(gr)*ch+gap,
                                  width: cw-gap*2, height: ch-gap*2)
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                           with: .color(Color.white.opacity(0.18)), lineWidth: 1.5)
            }

            for (key, color) in activeCells {
                let parts = key.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                let (pc, pr) = (parts[0], parts[1])
                if pr < 0 { continue }
                let rect = CGRect(x: CGFloat(pc)*cw+gap, y: CGFloat(pr)*ch+gap,
                                  width: cw-gap*2, height: ch-gap*2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
                let hl = CGRect(x: CGFloat(pc)*cw+gap, y: CGFloat(pr)*ch+gap,
                                width: cw-gap*2, height: (ch-gap*2)*0.3)
                ctx.fill(Path(roundedRect: hl, cornerRadius: 2),
                         with: .color(Color.white.opacity(0.3)))
            }
        }
        .frame(width: cellSize * CGFloat(TetrisGame.cols),
               height: cellSize * CGFloat(TetrisGame.rows))
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if dragStart == nil { dragStart = value.location.x }
                    let dx = value.translation.width
                    if abs(dx) > cellSize {
                        if dx > 0 { game.moveRight() } else { game.moveLeft() }
                        dragStart = value.location.x
                    }
                    if value.translation.height > cellSize * 2 {
                        game.softDrop()
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .onTapGesture { game.rotate() }
    }

    // MARK: Side Panel

    private func sidePanel(cellSize: CGFloat) -> some View {
        VStack(spacing: 10) {
            statCard(title: "SCORE", value: "\(game.score)")
            statCard(title: "LEVEL", value: "\(game.level)")
            statCard(title: "LINES", value: "\(game.linesCleared)")
            nextPieceCard
            Spacer(minLength: 0)
        }
        .frame(width: sidePanelWidth,
               height: cellSize * CGFloat(TetrisGame.rows))
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.5))
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var nextPieceCard: some View {
        VStack(spacing: 6) {
            Text("NEXT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.5))
            NextPieceView(type: game.next)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Controls

    private func controls(cellSize: CGFloat) -> some View {
        let btnSize: CGFloat = min(cellSize * 1.6, 48)
        return HStack(spacing: 0) {
            controlButton(icon: "arrow.left",        size: btnSize, action: game.moveLeft)
            Spacer()
            controlButton(icon: "rotate.left",       size: btnSize, action: { game.rotate(clockwise: false) })
            Spacer()
            controlButton(icon: "arrow.down.to.line",size: btnSize, action: game.hardDrop)
            Spacer()
            controlButton(icon: "rotate.right",      size: btnSize, action: { game.rotate(clockwise: true) })
            Spacer()
            controlButton(icon: "arrow.right",       size: btnSize, action: game.moveRight)
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, 8)
    }

    private func controlButton(icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
    }

    // MARK: Overlays

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("GAME OVER")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                Text("Score: \(game.score)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.yellow)
                Button { game.restart() } label: {
                    Text("PLAY AGAIN")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("PAUSED")
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                
                Button {
                    game.togglePause()
                } label: {
                    Text("Resume")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(10)
                }
            }
        }
        .onTapGesture {
            game.togglePause()
        }
    }

}

// MARK: - Next Piece Preview

struct NextPieceView: View {
    let type: TetrominoType

    var body: some View {
        let cells = type.rotations[0]
        let minC = cells.map { $0.0 }.min() ?? 0
        let minR = cells.map { $0.1 }.min() ?? 0
        let maxC = cells.map { $0.0 }.max() ?? 0
        let maxR = cells.map { $0.1 }.max() ?? 0
        let gridW = maxC - minC + 1
        let gridH = maxR - minR + 1
        let cellSize: CGFloat = 14
        let gap: CGFloat = 1

        return Canvas { ctx, size in
            let offsetX = (size.width - CGFloat(gridW) * (cellSize + gap)) / 2
            let offsetY = (size.height - CGFloat(gridH) * (cellSize + gap)) / 2
            for (c, r) in cells {
                let x = offsetX + CGFloat(c - minC) * (cellSize + gap)
                let y = offsetY + CGFloat(r - minR) * (cellSize + gap)
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(type.color))
                let hl = CGRect(x: x, y: y, width: cellSize, height: cellSize * 0.3)
                ctx.fill(Path(roundedRect: hl, cornerRadius: 1), with: .color(Color.white.opacity(0.3)))
            }
        }
        .frame(width: 64, height: 48)
    }
}

#Preview {
    TetrisView()
}
