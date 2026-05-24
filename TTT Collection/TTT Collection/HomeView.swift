import SwiftUI

struct HomeView: View {
    @State private var selectedGame: GameType?
    @ObservedObject private var music = MusicPlayer.shared
    @State private var showingSettings = false

    // Easter egg
    @State private var titleTapCount = 0
    @State private var showEasterEgg = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    ForEach(GameCategory.allCases) { category in
                        categorySection(category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .background(
                NavigationLink(
                    destination: destinationForSelectedGame,
                    isActive: Binding(
                        get: { selectedGame != nil },
                        set: { if !$0 { selectedGame = nil } }
                    ),
                    label: { EmptyView() }
                )
            )
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showEasterEgg) {
            EasterEggView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Game Collection")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .onTapGesture {
                        titleTapCount += 1
                        if titleTapCount >= 5 {
                            titleTapCount = 0
                            showEasterEgg = true
                        }
                    }
                Text("Classic games & variants")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                muteButton
                settingsButton
            }
        }
        .padding(.top, 16)
    }
    
    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .buttonStyle(CardButtonStyle())
    }

    private var muteButton: some View {
        Button {
            music.toggleMute()
        } label: {
            Image(systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .buttonStyle(CardButtonStyle())
    }

    // MARK: - Category Section

    private func categorySection(_ category: GameCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(category.rawValue.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(1.2)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(category.games) { game in
                    GameCardView(game: game) {
                        selectedGame = game
                    }
                }
            }
        }
    }

    // MARK: - Direct Game Router

    @ViewBuilder
    private func directGameView(_ game: GameType) -> some View {
        switch game {
        case .snake:        SnakeView()
        case .solitaire:    SolitaireView()
        case .chaosSolitaire: ChaosSolitaireView()
        case .brickBreaker: BrickBreakerView()
        case .minesweeper:  MinesweeperView()
        case .twenty48:     Twenty48View()
        case .wordle:       WordleView()
        case .memoryMatch:  MemoryMatchView()
        case .stack:        StackView()
        case .aimTrainer:   AimTrainerView()
        case .flappyBird:   FlappyBirdView()
        case .tetris:       TetrisView()
        case .blackjack:    BlackjackView()
        default:            EmptyView()
        }
    }

    // MARK: - Destination for Selected Game

    @ViewBuilder
    private var destinationForSelectedGame: some View {
        if let game = selectedGame {
            if game.needsSetup {
                GameSetupView(gameType: game)
            } else {
                directGameView(game)
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Easter Egg Sheet

struct EasterEggView: View {
    @Environment(\.dismiss) private var dismiss

    private struct CreditRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let link: URL?

        init(_ label: String, _ value: String, link: URL? = nil) {
            self.label = label
            self.value = value
            self.link = link
        }
    }

    private let credits: [CreditRow] = [
        .init(String(localized: "Quality Assurance"),     String(localized: "BigMannn")),
        .init(String(localized:"Translations (German)"), String(localized:"Niko")),
        .init(String(localized:"Translations (EN/RU/ES/IT)"),  String(localized:"Claude")),
        .init(String(localized:"Translations (Other)"),  String(localized:"None yet!\nContribute at github.com/nikos-projects/playbox"),
              link: URL(string: "https://github.com/nikos-projects/playbox")),
        .init(String(localized:"Coding"),                String(localized:"Suprisingly a few lines by Niko, Gemini, Claude & DeepSeek\n(Prompts by Niko — \"Do i look like i know swift?\" – Niko, python dev, 2026)")),
        .init(String(localized:"Art"),                   String(localized:"App icon: Glow added by Gemini,\ninitially made by ChatGPT")),
        .init(String(localized:"Music"),                 String(localized:"Google Lyria 3")),
        .init(String(localized:"SFX"),                   String(localized:"Find a way to add them and you get credits here :D")),
        .init(String(localized:"Contact"),               "steve.jobless.lololol@gmail.com",
              link: URL(string: "mailto:steve.jobless.lololol@gmail.com")),
        .init(String(localized:"Discord"),               "Nikos Projects (silly)",
              link: URL(string: "https://discord.gg/kXKRaZbVyr")),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // Easter egg image from asset catalog
                    if let uiImg = UIImage(named: "ee_img") {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                            .padding(.top, 8)
                    }

                    Text("✨ You found it ✨")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Here's everyone who made this possible:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    // Credits list
                    VStack(spacing: 0) {
                        ForEach(Array(credits.enumerated()), id: \.element.id) { idx, row in
                            creditRow(row)
                            if idx < credits.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 4)

                    Text("🕹️ Thanks for playing!")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func creditRow(_ row: CreditRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.8)

            if let link = row.link {
                Link(destination: link) {
                    Text(row.value)
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(row.value)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Game Card

struct GameCardView: View {
    let game: GameType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(game.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: game.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(game.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(game.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(game.accentColor)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(game.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    HomeView()
}
