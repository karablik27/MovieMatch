import SwiftUI

struct RecommendationsView: View {
    let tmdbClient: TMDBClient
    @ObservedObject var tasteStore: TasteStore

    @State private var movies: [Movie] = []
    @State private var isLoadingInitial = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var nextPage = 1
    @State private var hasMorePages = true

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingInitial && movies.isEmpty {
                    ProgressView("Подбираю рекомендации...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, movies.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button("Повторить") {
                            Task {
                                await reloadRecommendations()
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
                                    showFlame: tasteStore.isHotRecommendation(for: movie),
                                    recommendationScore: tasteStore.recommendationScore(for: movie),
                                    onLike: {
                                        tasteStore.toggleFeedback(movie: movie, liked: true)
                                    },
                                    onDislike: {
                                        tasteStore.toggleFeedback(movie: movie, liked: false)
                                    }
                                )
                                .onAppear {
                                    Task {
                                        await loadMoreIfNeeded(currentMovie: movie)
                                    }
                                }
                            }

                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else if !hasMorePages {
                                Text("Больше рекомендаций нет")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .navigationTitle("Рекомендации")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await reloadRecommendations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await loadInitialRecommendationsIfNeeded()
        }
    }

    private func loadInitialRecommendationsIfNeeded() async {
        guard movies.isEmpty else { return }
        await reloadRecommendations()
    }

    private func reloadRecommendations() async {
        guard !isLoadingInitial && !isLoadingMore else { return }

        nextPage = 1
        hasMorePages = true
        movies = []
        errorMessage = nil

        await loadNextPage(showInitialLoader: true)
    }

    private func loadMoreIfNeeded(currentMovie movie: Movie) async {
        guard movie.id == movies.last?.id else { return }
        await loadNextPage(showInitialLoader: false)
    }

    private func loadNextPage(showInitialLoader: Bool) async {
        guard hasMorePages else { return }
        guard !isLoadingInitial && !isLoadingMore else { return }

        if showInitialLoader {
            isLoadingInitial = true
        } else {
            isLoadingMore = true
        }

        defer {
            isLoadingInitial = false
            isLoadingMore = false
        }

        do {
            let existingIDs = Set(movies.map(\.id))
            let baseExcluded = tasteStore.dislikedMovieIDs
                .union(tasteStore.likedMovieIDs)
                .union(existingIDs)

            var pageToLoad = nextPage
            var rankedMovies: [Movie] = []
            var lastPageHasMore = false
            var attempts = 0
            let maxSkips = 20

            while attempts < maxSkips {
                let page = try await tmdbClient.fetchPopularMoviesPage(
                    page: pageToLoad,
                    excluding: baseExcluded
                )
                lastPageHasMore = page.hasMore
                attempts += 1

                let ranked = page.movies
                    .map { movie in
                        (movie, tasteStore.recommendationScore(for: movie))
                    }
                    .sorted { lhs, rhs in
                        lhs.1 > rhs.1
                    }
                    .map(\.0)

                if !ranked.isEmpty || !page.hasMore {
                    rankedMovies = ranked
                    break
                }

                pageToLoad += 1
            }

            movies.append(contentsOf: rankedMovies)
            tasteStore.markMoviesSeen(rankedMovies.map(\.id))

            if rankedMovies.isEmpty, lastPageHasMore, attempts >= maxSkips {
                hasMorePages = false
            } else {
                hasMorePages = lastPageHasMore
            }

            nextPage = pageToLoad + 1

            if movies.isEmpty && !hasMorePages {
                errorMessage = "Пока не нашлось подходящих рекомендаций"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
