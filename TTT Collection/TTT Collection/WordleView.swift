//
//  WordleView.swift
//  TTT Collection
//
//  Created by Philipp on 09.05.26.
//

import SwiftUI
import Network
internal import Combine

// MARK: - Word Service

/// Fetches today's NYT Wordle answer when online, falls back to the bundled
/// word list when offline. The fetched word is cached in UserDefaults so it
/// survives between sessions on the same calendar day.
private final class WordleWordService {

    static let shared = WordleWordService()

    // ── NYT Wordle API ──────────────────────────────────────────────────────
    // The NYT publishes each day's puzzle data at a stable URL keyed by date.
    private func todayURL() -> URL? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: Date())
        return URL(string: "https://www.nytimes.com/svc/wordle/v2/\(dateStr).json")
    }

    private var cacheKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return "wordle_cached_word_\(fmt.string(from: Date()))"
    }

    /// Returns the cached word for today if we already fetched it this session.
    var cachedTodayWord: String? {
        UserDefaults.standard.string(forKey: cacheKey)
    }

    func fetchTodayWord(completion: @escaping (String?) -> Void) {
        // Return from cache immediately if available
        if let cached = cachedTodayWord {
            completion(cached)
            return
        }
        guard let url = todayURL() else { completion(nil); return }

        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let solution = json["solution"] as? String,
                solution.count == 5
            else {
                completion(nil)
                return
            }
            let word = solution.uppercased()
            UserDefaults.standard.set(word, forKey: self.cacheKey)
            DispatchQueue.main.async { completion(word) }
        }.resume()
    }

    /// Pick a random word from the bundled fallback list.
    func randomFallbackWord() -> String {
        WordleWordList.answers.randomElement()?.uppercased() ?? "SWIFT"
    }
}

// MARK: - Tile State

private enum TileState {
    case empty, filled, correct, present, absent

    var bgColor: Color {
        switch self {
        case .empty:   return Color(.systemGray6)
        case .filled:  return Color(.systemGray5)
        case .correct: return Color(red: 0.40, green: 0.72, blue: 0.45)
        case .present: return Color(red: 0.83, green: 0.69, blue: 0.27)
        case .absent:  return Color(.systemGray2)
        }
    }

    var fgColor: Color {
        switch self {
        case .empty, .filled: return .primary
        default:              return .white
        }
    }
}

// MARK: - Keyboard Key State

private enum KeyState { case unused, correct, present, absent }

// MARK: - ViewModel

private final class WordleViewModel: ObservableObject {
    @Published var grid: [[Character]] = Array(repeating: Array(repeating: " ", count: 5), count: 6)
    @Published var tileStates: [[TileState]] = Array(repeating: Array(repeating: .empty, count: 5), count: 6)
    @Published var currentRow = 0
    @Published var currentCol = 0
    @Published var gameOver = false
    @Published var won = false
    @Published var message: String = ""
    @Published var keyStates: [Character: KeyState] = [:]
    @Published var isLoadingWord = false
    @Published var wordSource: String = ""   // "Today's NYT Wordle" | "Offline — random word"
    @Published var shakeRow: Int? = nil

    private(set) var targetWord: [Character] = Array("SWIFT")

    private let monitor = NWPathMonitor()
    private var isOnline = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
        }
        monitor.start(queue: DispatchQueue(label: "net.monitor"))
        loadWord()
    }

    // ── Word loading ────────────────────────────────────────────────────────

    func loadWord() {
        isLoadingWord = true
        message = ""

        // Try cached first (instant)
        if let cached = WordleWordService.shared.cachedTodayWord {
            applyWord(cached, source: "Today's NYT Wordle")
            return
        }

        if isOnline {
            WordleWordService.shared.fetchTodayWord { [weak self] word in
                guard let self else { return }
                if let w = word {
                    self.applyWord(w, source: "Today's NYT Wordle")
                } else {
                    self.applyWord(WordleWordService.shared.randomFallbackWord(), source: "Offline — random word")
                }
            }
        } else {
            applyWord(WordleWordService.shared.randomFallbackWord(), source: "Offline — random word")
        }
    }

    private func applyWord(_ word: String, source: String) {
        targetWord = Array(word.uppercased())
        wordSource = source
        isLoadingWord = false
        resetGrid()
    }

    func resetGrid() {
        grid        = Array(repeating: Array(repeating: " ", count: 5), count: 6)
        tileStates  = Array(repeating: Array(repeating: .empty,  count: 5), count: 6)
        currentRow  = 0
        currentCol  = 0
        gameOver    = false
        won         = false
        message     = ""
        keyStates   = [:]
        shakeRow    = nil
    }

    // ── Input ───────────────────────────────────────────────────────────────

    func letterPressed(_ ch: Character) {
        guard !gameOver, currentCol < 5 else { return }
        grid[currentRow][currentCol] = ch
        tileStates[currentRow][currentCol] = .filled
        currentCol += 1
    }

    func deletePressed() {
        guard !gameOver, currentCol > 0 else { return }
        currentCol -= 1
        grid[currentRow][currentCol] = " "
        tileStates[currentRow][currentCol] = .empty
    }

    func enterPressed() {
        guard !gameOver, currentCol == 5 else {
            triggerShake()
            return
        }

        let guess = Array(0..<5).map { grid[currentRow][$0] }

        // Basic word check — accept anything 5 letters (no hard rejection)
        evaluateGuess(guess)
    }

    private func triggerShake() {
        shakeRow = currentRow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.shakeRow = nil
        }
    }

    private func evaluateGuess(_ guess: [Character]) {
        var result = Array(repeating: TileState.absent, count: 5)
        var remaining = targetWord

        // Pass 1: correct positions
        for i in 0..<5 {
            if guess[i] == targetWord[i] {
                result[i] = .correct
                remaining[i] = "_"
            }
        }
        // Pass 2: present but wrong position
        for i in 0..<5 {
            guard result[i] != .correct else { continue }
            if let j = remaining.firstIndex(of: guess[i]) {
                result[i] = .present
                remaining[j] = "_"
            }
        }

        // Animate tiles with stagger
        for i in 0..<5 {
            let delay = Double(i) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.tileStates[self.currentRow][i] = result[i]
            }
        }

        // Update keyboard after tile reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            for i in 0..<5 {
                let ch = guess[i]
                let state = result[i]
                let existing = self.keyStates[ch]
                switch state {
                case .correct:
                    self.keyStates[ch] = .correct
                case .present:
                    if existing != .correct { self.keyStates[ch] = .present }
                case .absent:
                    if existing == nil { self.keyStates[ch] = .absent }
                default: break
                }
            }

            let guessedWord = String(guess)
            if guessedWord == String(self.targetWord) {
                self.won = true
                self.gameOver = true
                self.message = ["Brilliant! 🎉", "Excellent! 🌟", "Great! 👏", "Nice! 😊", "Phew! 😅", "Lucky! 🍀"][min(self.currentRow, 5)]
            } else {
                self.currentRow += 1
                self.currentCol = 0
                if self.currentRow == 6 {
                    self.gameOver = true
                    self.message = String(self.targetWord)
                }
            }
        }
    }
}

// MARK: - Views

struct WordleView: View {
    @StateObject private var vm = WordleViewModel()
    @Environment(\.dismiss) private var dismiss
    private let accentColor = Color.green

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if vm.isLoadingWord {
                    Spacer()
                    ProgressView("Fetching today's word…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    wordSourceBadge
                    Spacer(minLength: 8)
                    gridView
                    Spacer(minLength: 8)
                    if !vm.message.isEmpty { messageLabel }
                    Spacer(minLength: 4)
                    keyboard
                        .padding(.bottom, 12)
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: Header
    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            Spacer()
            Text("Wordle")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Spacer()
            Button {
                vm.loadWord()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Word Source Badge
    private var wordSourceBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: vm.wordSource.contains("NYT") ? "network" : "wifi.slash")
                .font(.system(size: 10))
            Text(vm.wordSource)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .padding(.bottom, 4)
    }

    // MARK: Grid
    private var gridView: some View {
        GeometryReader { geo in
            let cellSize = min((geo.size.width - 40 - 5 * 4) / 5, 62.0)
            VStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { col in
                            tileView(row: row, col: col, size: cellSize)
                        }
                    }
                    .modifier(ShakeModifier(active: vm.shakeRow == row))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 62 * 6 + 4 * 5)
        .padding(.horizontal, 20)
    }

    private func tileView(row: Int, col: Int, size: CGFloat) -> some View {
        let ch = vm.grid[row][col]
        let state = vm.tileStates[row][col]
        let isActive = row == vm.currentRow && !vm.gameOver
        let delay = Double(col) * 0.08

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(state.bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isActive && ch != " " ? accentColor.opacity(0.5) : Color(.separator),
                            lineWidth: isActive && ch != " " ? 2 : 1
                        )
                )
            Text(ch == " " ? "" : String(ch))
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundColor(state.fgColor)
        }
        .frame(width: size, height: size)
        .scaleEffect(ch != " " && state == .filled ? 1.08 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: ch)
        .rotation3DEffect(
            stateIsRevealed(state) ? .degrees(0) : .degrees(0),
            axis: (x: 1, y: 0, z: 0)
        )
        // Flip reveal animation
        .modifier(FlipRevealModifier(state: state, delay: delay))
    }

    private func stateIsRevealed(_ s: TileState) -> Bool {
        s == .correct || s == .present || s == .absent
    }

    // MARK: Message
    private var messageLabel: some View {
        Text(vm.gameOver && !vm.won ? "Answer: \(vm.message)" : vm.message)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(vm.won ? accentColor : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.message)
    }

    // MARK: Keyboard
    private var keyboard: some View {
        let rows: [[Character]] = [
            ["Q","W","E","R","T","Y","U","I","O","P"],
            ["A","S","D","F","G","H","J","K","L"],
            ["↵","Z","X","C","V","B","N","M","⌫"]
        ]
        return VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { ri in
                HStack(spacing: 4) {
                    ForEach(rows[ri].indices, id: \.self) { ci in
                        keyButton(rows[ri][ci])
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func keyButton(_ ch: Character) -> some View {
        let isWide = ch == "↵" || ch == "⌫"
        let ks = vm.keyStates[ch]
        let bg: Color = {
            switch ks {
            case .correct: return TileState.correct.bgColor
            case .present: return TileState.present.bgColor
            case .absent:  return Color(.systemGray3)
            default:       return Color(.secondarySystemGroupedBackground)
            }
        }()
        let fg: Color = ks != nil && ks != .unused ? .white : .primary

        return Button {
            if ch == "⌫" { vm.deletePressed() }
            else if ch == "↵" { vm.enterPressed() }
            else { vm.letterPressed(ch) }
        } label: {
            Text(ch == "↵" ? "ENTER" : ch == "⌫" ? "⌫" : String(ch))
                .font(.system(size: isWide ? 11 : 15, weight: .semibold))
                .foregroundColor(fg)
                .frame(width: isWide ? 50 : 32, height: 46)
                .background(bg)
                .cornerRadius(6)
        }
        .buttonStyle(CardButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: ks)
    }
}

// MARK: - Shake Modifier

private struct ShakeModifier: ViewModifier {
    let active: Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: active) { isActive in
                guard isActive else { offset = 0; return }
                withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) {
                    offset = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { offset = 0 }
            }
    }
}

// MARK: - Flip Reveal Modifier

private struct FlipRevealModifier: ViewModifier {
    let state: TileState
    let delay: Double
    @State private var flipped = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(flipped ? 0 : 0), axis: (x: 1, y: 0, z: 0))
            .onChange(of: state) { newState in
                guard newState == .correct || newState == .present || newState == .absent else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeInOut(duration: 0.3)) { flipped = true }
                }
            }
    }
}

// MARK: - Bundled Fallback Word List

private enum WordleWordList {
    /// ~300 common 5-letter words as a reliable offline fallback.
    static let answers: [String] = [
        "ABOUT","ABOVE","ABUSE","ACTOR","ACUTE","ADMIT","ADOPT","ADULT","AFTER","AGAIN",
        "AGENT","AGREE","AHEAD","ALARM","ALBUM","ALERT","ALIKE","ALIGN","ALIVE","ALLEY",
        "ALLOW","ALONE","ALONG","ALTER","ANGEL","ANGER","ANGLE","ANGRY","ANIME","ANKLE",
        "ANNEX","APART","APPLE","APPLY","ARENA","ARGUE","ARISE","ARMOR","ARRAY","ARROW",
        "ASIDE","ASKED","ATLAS","ATTIC","AUDIO","AUDIT","AVAIL","AVOID","AWARD","AWARE",
        "BADLY","BAKER","BASIC","BASIS","BATCH","BEACH","BEARD","BEAST","BEGIN","BEING",
        "BELOW","BENCH","BIBLE","BIRTH","BISON","BLADE","BLAME","BLAND","BLANK","BLAST",
        "BLAZE","BLEND","BLESS","BLIND","BLOCK","BLOOD","BLOOM","BLOWN","BOARD","BONUS",
        "BOOST","BOOTH","BOUND","BOXER","BRAIN","BRAND","BRAVE","BREAK","BREED","BRICK",
        "BRIDE","BRIEF","BRING","BRISK","BROKE","BROOK","BRUSH","BUILD","BUILT","BUNCH",
        "BURNT","BURST","BUYER","CABIN","CABLE","CAMEL","CANDY","CARGO","CARRY","CATCH",
        "CAUSE","CEDAR","CHAIN","CHAIR","CHALK","CHAOS","CHASE","CHEAP","CHECK","CHEEK",
        "CHESS","CHEST","CHIEF","CHILD","CHINA","CHOIR","CIVIL","CLAIM","CLASH","CLASS",
        "CLEAN","CLEAR","CLIMB","CLING","CLOCK","CLOSE","CLOUD","COACH","COAST","COLOR",
        "COMBO","COMIC","COMMA","CORAL","COULD","COUNT","COURT","COVER","CRACK","CRANE",
        "CRASH","CRAZY","CREAM","CREEK","CRISP","CROSS","CROWD","CROWN","CRUSH","CURVE",
        "CYCLE","DAILY","DANCE","DATUM","DEATH","DEBUT","DECAY","DELAY","DENSE","DEPOT",
        "DEPTH","DERBY","DEVIL","DIGIT","DISCO","DITCH","DITZY","DIVOT","DIZZY","DODGE",
        "DOING","DOUBT","DOUGH","DOWRY","DRAFT","DRAIN","DRAMA","DRANK","DRAWL","DRAWN",
        "DREAM","DROVE","DRUGS","DINER","DUNCE","DWARF","EAGER","EAGLE","EARLY","EARTH",
        "EIGHT","ELITE","EMAIL","EMPTY","ENEMY","ENJOY","ENTER","ENTRY","EQUAL","ERROR",
        "ESSAY","EVADE","EVENT","EVERY","EXACT","EXIST","EXTRA","FABLE","FACET","FAITH",
        "FALSE","FANCY","FATAL","FAULT","FEAST","FENCE","FERRY","FEVER","FIELD","FIFTH",
        "FIFTY","FIGHT","FINAL","FIRST","FIXED","FLAME","FLANK","FLASH","FLEET","FLESH",
        "FLINT","FLOAT","FLOOD","FLOOR","FLOUR","FLOWN","FLUTE","FOCUS","FORCE","FORGE",
        "FORTH","FORUM","FOUND","FRAME","FRAUD","FRESH","FRONT","FROST","FROZE","FRUIT",
        "FULLY","FUNNY","GHOST","GIANT","GIVEN","GLAND","GLASS","GLAZE","GLEAM","GLIDE",
        "GLOBE","GLOOM","GLOSS","GLOVE","GOING","GRACE","GRADE","GRAIN","GRAND","GRANT",
        "GRAPE","GRASP","GRASS","GRAVE","GREAT","GREET","GRIEF","GRIND","GROAN","GROIN",
        "GROPE","GROSS","GROUP","GROVE","GROWL","GUARD","GUEST","GUIDE","GUILD","GUILE",
        "GUILT","GUISE","GUSTO","HAPPY","HARDY","HARSH","HASTE","HAUNT","HAVEN","HEART",
        "HEAVY","HENCE","HERBS","HINGE","HONOR","HORSE","HOTEL","HOVER","HUMAN","HUMOR",
        "HURRY","IDEAL","IMAGE","IMPLY","INEPT","INFER","INNER","INPUT","ISSUE","IVORY",
        "JEWEL","JOINT","JOKER","JONES","JUICE","JUICY","JUICE","JUMBO","KARMA","KNIFE",
        "KNOCK","KNOWN","LABEL","LANCE","LARGE","LASER","LATER","LATCH","LAYER","LEARN",
        "LEASE","LEGAL","LEMON","LEVEL","LIGHT","LIMIT","LINEN","LIVER","LOCAL","LODGE",
        "LOFTY","LOGIC","LOOSE","LOVER","LOWER","LOYAL","LUCKY","LUNAR","LUSTY","MAGIC",
        "MAPLE","MARCH","MATCH","MAYOR","MEDIA","MERCY","MERIT","METAL","MIGHT","MINOR",
        "MINUS","MIXED","MODEL","MONEY","MONTH","MORAL","MOTOR","MOTTO","MOUSE","MOUTH",
        "MOVED","MOVIE","MUSIC","NAIVE","NERVE","NEVER","NIGHT","NOBLE","NOISE","NORTH",
        "NOTED","NOVEL","NURSE","NYMPH","OCCUR","OCEAN","OFFER","ONSET","OPERA","ORDER",
        "OTHER","OUGHT","OUTER","OUNCE","OWNED","OWNER","OXIDE","OZONE","PAINT","PANEL",
        "PANIC","PAPER","PARTY","PASTA","PATCH","PAUSE","PEACE","PEARL","PEDAL","PENNY",
        "PHASE","PHONE","PHOTO","PIANO","PILOT","PIXEL","PIZZA","PLACE","PLAIN","PLANE",
        "PLANT","PLATE","PLAZA","PLEAD","PLUCK","POINT","POKER","POLAR","POLKA","POPPY",
        "POWER","PRESS","PRICE","PRIDE","PRIME","PRINT","PRIOR","PRIZE","PROBE","PRONE",
        "PROOF","PROSE","PROUD","PROVE","PSALM","PULSE","PUPIL","PURSE","QUEST","QUEUE",
        "QUICK","QUIET","QUOTA","QUOTE","RABBI","RADAR","RADIO","RAISE","RALLY","RANGE",
        "RAPID","RATIO","REACH","REACT","READY","REALM","REBEL","REFER","REIGN","RELAX",
        "REMIT","REPAY","RIDER","RIDGE","RIFLE","RIGID","RISKY","RIVAL","RIVER","ROBOT",
        "ROCKY","ROMAN","ROUGE","ROUGH","ROUND","ROUTE","ROYAL","RUGBY","RULER","RURAL",
        "SAINT","SALAD","SAUCE","SCALE","SCARE","SCENE","SCORE","SCOUT","SEIZE","SENSE",
        "SERVE","SEVEN","SHADE","SHAFT","SHAKE","SHAME","SHAPE","SHARE","SHARP","SHELL",
        "SHIFT","SHINE","SHIRT","SHOCK","SHORE","SHORT","SHOUT","SIGHT","SILLY","SINCE",
        "SIXTH","SIXTY","SIZED","SKILL","SLICE","SLIDE","SLOPE","SMART","SMELL","SMILE",
        "SMOKE","SNACK","SNARE","SOLAR","SOLID","SOLVE","SORRY","SPACE","SPARE","SPARK",
        "SPEAK","SPEND","SPICE","SPINE","SPITE","SPLIT","SPOKE","SPOON","SPORT","SPRAY",
        "SQUAD","STACK","STAFF","STAGE","STAIN","STAKE","STARE","START","STATE","STAYS",
        "STEAM","STEEL","STEEP","STEER","STERN","STICK","STONE","STOOD","STORE","STORM",
        "STORY","STOVE","STRAP","STRAW","STRAY","STRIP","STUCK","STUDY","STUFF","STYLE",
        "SUGAR","SUITE","SUNNY","SUPER","SURGE","SUSHI","SWEAR","SWEET","SWEPT","SWIFT",
        "SWORD","TABLE","TASTE","TEACH","TEETH","THANK","THEME","THERE","THESE","THINK",
        "THIRD","THREE","THREW","THROW","THUMB","TIGER","TIGHT","TIMER","TIRED","TITLE",
        "TODAY","TOKEN","TORCH","TOTAL","TOUCH","TOUGH","TOWER","TOXIC","TRACK","TRADE",
        "TRAIL","TRAIN","TRAIT","TRASH","TREAT","TREND","TRIAL","TRIBE","TRICK","TROOP",
        "TRUCK","TRULY","TRUMP","TRUST","TRUTH","TWICE","TWINE","TWIST","TYPED","ULTRA",
        "UNDER","UNIFY","UNION","UNITY","UNTIL","UPPER","UPSET","URBAN","USAGE","USING",
        "USUAL","UTTER","VALID","VALUE","VALVE","VIDEO","VIGOR","VIRAL","VIRUS","VISIT",
        "VISOR","VITAL","VIVID","VOCAL","VOICE","VOTER","WASTE","WATCH","WATER","WEARY",
        "WEAVE","WEDGE","WEIRD","WHALE","WHEAT","WHEEL","WHERE","WHICH","WHILE","WHITE",
        "WHOLE","WHOSE","WITCH","WOMAN","WORLD","WORRY","WORSE","WORST","WORTH","WOULD",
        "WOUND","WRATH","WRIST","WRITE","WRONG","YACHT","YOUNG","YOURS","YOUTH","ZEBRA"
    ]
}

#Preview {
    WordleView()
}
