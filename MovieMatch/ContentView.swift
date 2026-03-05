import SwiftUI

struct ContentView: View {
    @StateObject private var tasteStore = TasteStore()
    private let tmdbClient = TMDBClient()

    var body: some View {
        Group {
            if tasteStore.hasCompletedOnboarding {
                MainTabView(tmdbClient: tmdbClient, tasteStore: tasteStore)
            } else {
                OnboardingSwipeView(tmdbClient: tmdbClient, tasteStore: tasteStore)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
