import SwiftUI

struct ContentView: View {
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @AppStorage("hasSeenBetaPrompt") private var hasSeenBetaPrompt = false
    @State private var showBetaOptIn = false
    
    var body: some View {
        HomeView()
            .onAppear {
                MusicPlayer.shared.start()
                
                // Check for updates on launch
                updateChecker.checkForUpdates()
                
                // Show beta opt-in on first launch
                if !hasSeenBetaPrompt {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showBetaOptIn = true
                    }
                } else {
                    // If opted in, check for beta updates
                    if updateChecker.isOptedIntoBeta() {
                        updateChecker.checkForBetaUpdates()
                    }
                }
            }
            .sheet(isPresented: $showBetaOptIn) {
                BetaOptInView()
            }
            .sheet(isPresented: $updateChecker.showUpdatePrompt) {
                if let updateInfo = updateChecker.updateAvailable {
                    UpdatePromptView(updateInfo: updateInfo)
                }
            }
            .sheet(isPresented: $updateChecker.showBetaPrompt) {
                if let betaInfo = updateChecker.betaUpdateAvailable {
                    BetaUpdatePromptView(betaInfo: betaInfo)
                }
            }
    }
}

#Preview {
    ContentView()
}
