import SwiftUI

struct CatalogView: View {
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
                    ProgressView("Загружаю фильмы...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, movies.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button("Обновить") {
                            Task {
                                await reloadCatalog()
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
                                Text("Новые фильмы закончились")
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
            .navigationTitle("Все фильмы")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await reloadCatalog()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await loadInitialCatalogIfNeeded()
        }
    }

    private func loadInitialCatalogIfNeeded() async {
        guard movies.isEmpty else { return }
        await reloadCatalog()
    }

    private func reloadCatalog() async {
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
            let strictExcluded = tasteStore.dislikedMovieIDs
                .union(tasteStore.seenMovieIDs)
                .union(existingIDs)
            let relaxedExcluded = tasteStore.dislikedMovieIDs
                .union(existingIDs)

            var pageToLoad = nextPage
            var result: TMDBClient.PagedMovies?
            var attempts = 0
            let maxSkips = 20

            while attempts < maxSkips {
                let page = try await tmdbClient.fetchPopularMoviesPage(
                    page: pageToLoad,
                    excluding: strictExcluded
                )
                result = page
                attempts += 1

                if !page.movies.isEmpty || !page.hasMore {
                    break
                }

                pageToLoad += 1
            }

            // If all nearby pages contain only already seen movies,
            // fall back to allowing repeats to keep the feed non-empty.
            if let strictResult = result, strictResult.movies.isEmpty, strictResult.hasMore {
                attempts = 0
                while attempts < maxSkips {
                    let page = try await tmdbClient.fetchPopularMoviesPage(
                        page: pageToLoad,
                        excluding: relaxedExcluded
                    )
                    result = page
                    attempts += 1

                    if !page.movies.isEmpty || !page.hasMore {
                        break
                    }

                    pageToLoad += 1
                }
            }

            guard let pageResult = result else {
                errorMessage = "Не удалось загрузить каталог"
                return
            }

            if pageResult.movies.isEmpty, pageResult.hasMore, attempts >= maxSkips {
                hasMorePages = false
            } else {
                hasMorePages = pageResult.hasMore
            }

            nextPage = pageToLoad + 1
            movies.append(contentsOf: pageResult.movies)
            tasteStore.markMoviesSeen(pageResult.movies.map(\.id))

            if movies.isEmpty && !hasMorePages {
                errorMessage = "Новых фильмов пока нет"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
