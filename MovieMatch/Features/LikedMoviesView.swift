import SwiftUI

struct LikedMoviesView: View {
    let tmdbClient: TMDBClient
    @ObservedObject var tasteStore: TasteStore

    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var likedIDs: [Int] {
        Array(tasteStore.likedMovieIDs).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Group {
                if likedIDs.isEmpty {
                    Text("Пока нет понравившихся фильмов")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading && movies.isEmpty {
                    ProgressView("Загружаю понравившиеся...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, movies.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button("Повторить") {
                            Task {
                                await loadLikedMovies()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(movies) { movie in
                                MovieGridCard(
                                    movie: movie,
                                    feedbackState: tasteStore.feedbackState(for: movie.id),
                                    onLike: {
                                        tasteStore.toggleFeedback(movie: movie, liked: true)
                                    },
                                    onDislike: {
                                        tasteStore.toggleFeedback(movie: movie, liked: false)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("Понравившиеся")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadLikedMovies()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(likedIDs.isEmpty)
                }
            }
        }
        .task(id: likedIDs) {
            await loadLikedMovies()
        }
    }

    private func loadLikedMovies() async {
        guard !isLoading else { return }

        if likedIDs.isEmpty {
            movies = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
        }

        do {
            movies = try await tmdbClient.fetchMovies(ids: likedIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
