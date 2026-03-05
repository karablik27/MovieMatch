import SwiftUI

struct OnboardingSwipeView: View {
    let tmdbClient: TMDBClient
    @ObservedObject var tasteStore: TasteStore

    @State private var movies: [Movie] = []
    @State private var currentIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isLoading = false
    @State private var isSwipeLocked = false
    @State private var errorMessage: String?

    private var currentMovie: Movie? {
        guard currentIndex < movies.count else { return nil }
        return movies[currentIndex]
    }

    private var nextMovie: Movie? {
        let nextIndex = currentIndex + 1
        guard nextIndex < movies.count else { return nil }
        return movies[nextIndex]
    }

    private var swipeBadge: SwipeBadge? {
        if dragOffset.width > 24 {
            return .like
        }
        if dragOffset.width < -24 {
            return .dislike
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("MovieMatch")
                .font(.title.bold())

            Text("Оцените 10 фильмов свайпами")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(
                value: Double(tasteStore.onboardingDecisions),
                total: Double(TasteStore.requiredOnboardingDecisions)
            )
            .tint(.mint)

            Text("\(tasteStore.onboardingDecisions)/\(TasteStore.requiredOnboardingDecisions)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Group {
                if isLoading && currentMovie == nil {
                    ProgressView("Загружаю фильмы...")
                        .frame(maxHeight: .infinity)
                } else if let currentMovie {
                    cardStack(currentMovie: currentMovie)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button("Повторить") {
                            Task {
                                await loadMoviesIfNeeded(force: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Text("Недостаточно фильмов для онбординга")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                }
            }

            HStack(spacing: 18) {
                feedbackButton(
                    symbol: "xmark",
                    tint: .red,
                    title: "Мимо"
                ) {
                    guard let movie = currentMovie else { return }
                    commitSwipe(movie: movie, liked: false)
                }

                feedbackButton(
                    symbol: "heart.fill",
                    tint: .green,
                    title: "Нравится"
                ) {
                    guard let movie = currentMovie else { return }
                    commitSwipe(movie: movie, liked: true)
                }
            }
        }
        .padding(16)
        .task {
            await loadMoviesIfNeeded(force: false)
        }
    }

    private func cardStack(currentMovie: Movie) -> some View {
        ZStack {
            if let nextMovie {
                MovieSwipeCard(movie: nextMovie, badge: nil)
                    .scaleEffect(0.96)
                    .offset(y: 12)
                    .allowsHitTesting(false)
            }

            MovieSwipeCard(movie: currentMovie, badge: swipeBadge)
                .offset(x: dragOffset.width, y: dragOffset.height * 0.2)
                .rotationEffect(.degrees(Double(dragOffset.width / 24)))
                .gesture(dragGesture(for: currentMovie))
                .animation(.spring(response: 0.26, dampingFraction: 0.82), value: dragOffset)
        }
        .frame(maxHeight: .infinity)
    }

    private func dragGesture(for movie: Movie) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isSwipeLocked else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isSwipeLocked else { return }

                let threshold: CGFloat = 120

                if value.translation.width > threshold {
                    commitSwipe(movie: movie, liked: true)
                } else if value.translation.width < -threshold {
                    commitSwipe(movie: movie, liked: false)
                } else {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func feedbackButton(symbol: String, tint: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(currentMovie == nil || isSwipeLocked)
    }

    private func commitSwipe(movie: Movie, liked: Bool) {
        guard !isSwipeLocked else { return }

        isSwipeLocked = true

        let destinationX: CGFloat = liked ? 900 : -900
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = CGSize(width: destinationX, height: 40)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            finalizeSwipe(movie: movie, liked: liked)
        }
    }

    private func finalizeSwipe(movie: Movie, liked: Bool) {
        tasteStore.recordFeedback(movie: movie, liked: liked)
        currentIndex += 1
        dragOffset = .zero
        isSwipeLocked = false

        if currentIndex >= movies.count && !tasteStore.hasCompletedOnboarding {
            Task {
                await loadMoviesIfNeeded(force: true)
            }
        }
    }

    private func loadMoviesIfNeeded(force: Bool) async {
        guard !tasteStore.hasCompletedOnboarding else {
            return
        }

        if !force, currentMovie != nil {
            return
        }

        if isLoading {
            return
        }

        let remaining = max(TasteStore.requiredOnboardingDecisions - tasteStore.onboardingDecisions, 0)
        guard remaining > 0 else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let excludedIDs = tasteStore.likedMovieIDs.union(tasteStore.dislikedMovieIDs)
            let loadCount = max(remaining, 10)
            movies = try await tmdbClient.fetchPopularMovies(limit: loadCount, excluding: excludedIDs)
            currentIndex = 0

            if movies.isEmpty {
                errorMessage = "TMDB не вернул фильмы для онбординга"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct MovieSwipeCard: View {
    let movie: Movie
    let badge: SwipeBadge?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    posterPlaceholder
                case .empty:
                    posterPlaceholder
                @unknown default:
                    posterPlaceholder
                }
            }
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.title3.bold())
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                    Text(movie.runtimeText)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(movie.genreLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let badge {
                Text(badge.title)
                    .font(.headline.weight(.heavy))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(badge.color.opacity(0.16))
                    .foregroundStyle(badge.color)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(14)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 8)
    }

    private var posterPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
            Image(systemName: "film")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private enum SwipeBadge {
    case like
    case dislike

    var title: String {
        switch self {
        case .like:
            return "LIKE"
        case .dislike:
            return "NOPE"
        }
    }

    var color: Color {
        switch self {
        case .like:
            return .green
        case .dislike:
            return .red
        }
    }
}
