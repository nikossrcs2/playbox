import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
            .onAppear {
                MusicPlayer.shared.start()
            }
    }
}

#Preview {
    ContentView()
}
