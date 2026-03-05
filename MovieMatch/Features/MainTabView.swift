import SwiftUI

struct MainTabView: View {
    let tmdbClient: TMDBClient
    @ObservedObject var tasteStore: TasteStore

    var body: some View {
        TabView {
            CatalogView(tmdbClient: tmdbClient, tasteStore: tasteStore)
                .tabItem {
                    Label("Все", systemImage: "film.stack")
                }

            RecommendationsView(tmdbClient: tmdbClient, tasteStore: tasteStore)
                .tabItem {
                    Label("Рекомендации", systemImage: "flame.fill")
                }

            LikedMoviesView(tmdbClient: tmdbClient, tasteStore: tasteStore)
                .tabItem {
                    Label("Понравились", systemImage: "heart.fill")
                }

            DislikedMoviesView(tmdbClient: tmdbClient, tasteStore: tasteStore)
                .tabItem {
                    Label("Дизлайки", systemImage: "hand.thumbsdown.fill")
                }
        }
    }
}
