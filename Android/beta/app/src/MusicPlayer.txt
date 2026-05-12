import AVFoundation
import SwiftUI
internal import Combine

// MARK: - MusicPlayer
// Singleton that streams bg_music.mp3 from the asset catalog on a loop.
// Call MusicPlayer.shared.start() once at launch; toggle with .isMuted.

final class MusicPlayer: ObservableObject {

    static let shared = MusicPlayer()

    @Published var isMuted: Bool = false {
        didSet {
            player?.volume = isMuted ? 0 : 1
            UserDefaults.standard.set(isMuted, forKey: "bgMusicMuted")
        }
    }

    private var player: AVAudioPlayer?

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: "bgMusicMuted")
        preparePlayer()
    }

    // MARK: - Setup

    private func preparePlayer() {
        // Load from asset catalog (NSDataAsset) — add bg_music to .xcassets as a Data asset
        guard let asset = NSDataAsset(name: "bg_music") else {
            print("MusicPlayer: 'bg_music' not found in asset catalog.")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: asset.data, fileTypeHint: AVFileType.mp3.rawValue)
            player?.numberOfLoops = -1          // loop forever
            player?.volume = isMuted ? 0 : 1
            player?.prepareToPlay()
        } catch {
            print("MusicPlayer: failed to create player — \(error)")
        }
    }

    // MARK: - Controls

    func start() {
        guard player?.isPlaying == false else { return }
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func toggleMute() {
        isMuted.toggle()
    }
}
