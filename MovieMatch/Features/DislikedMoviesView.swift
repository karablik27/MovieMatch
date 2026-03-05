import SwiftUI

struct DislikedMoviesView: View {
    let tmdbClient: TMDBClient
    @ObservedObject var tasteStore: TasteStore

    @State private var movies: [Movie] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var dislikedIDs: [Int] {
        Array(tasteStore.dislikedMovieIDs).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Group {
                if dislikedIDs.isEmpty {
                    Text("Пока нет дизлайков")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading && movies.isEmpty {
                    ProgressView("Загружаю дизлайки...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, movies.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button("Повторить") {
                            Task {
                                await loadDislikedMovies()
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
            .navigationTitle("Дизлайки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await loadDislikedMovies()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(dislikedIDs.isEmpty)
                }
            }
        }
        .task(id: dislikedIDs) {
            await loadDislikedMovies()
        }
    }

    private func loadDislikedMovies() async {
        guard !isLoading else { return }

        if dislikedIDs.isEmpty {
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
            movies = try await tmdbClient.fetchMovies(ids: dislikedIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
