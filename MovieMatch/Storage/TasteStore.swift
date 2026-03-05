import Foundation
import Combine

enum MovieFeedbackState {
    case unrated
    case liked
    case disliked
}

@MainActor
final class TasteStore: ObservableObject {
    static let requiredOnboardingDecisions = 10
    static let hotRecommendationThreshold = 0.72

    @Published private(set) var likedMovieIDs: Set<Int>
    @Published private(set) var dislikedMovieIDs: Set<Int>
    @Published private(set) var seenMovieIDs: Set<Int>
    @Published private(set) var genreLikeCounts: [Int: Int]
    @Published private(set) var likedRatingAverage: Double
    @Published private(set) var likedRuntimeAverage: Double
    @Published private(set) var onboardingDecisions: Int

    private var likedRatingSamples: Int
    private var likedRuntimeSamples: Int
    private let defaults: UserDefaults
    private let coreMLScorer: CoreMLScorer
    private let calibrator: OnlineCalibrator

    var hasCompletedOnboarding: Bool {
        onboardingDecisions >= Self.requiredOnboardingDecisions
    }

    var recommendationEngineName: String {
        let base = coreMLScorer.isAvailable ? "Core ML" : "Heuristic"
        return "\(base) + Online"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        coreMLScorer = CoreMLScorer()
        calibrator = OnlineCalibrator(defaults: defaults)

        let likedIDs = defaults.array(forKey: Keys.likedMovieIDs) as? [Int] ?? []
        let dislikedIDs = defaults.array(forKey: Keys.dislikedMovieIDs) as? [Int] ?? []
        let seenIDs = defaults.array(forKey: Keys.seenMovieIDs) as? [Int] ?? []

        likedMovieIDs = Set(likedIDs)
        dislikedMovieIDs = Set(dislikedIDs)
        seenMovieIDs = Set(seenIDs)

        let rawGenreCounts = defaults.dictionary(forKey: Keys.genreLikeCounts) as? [String: Int] ?? [:]
        genreLikeCounts = Dictionary(
            uniqueKeysWithValues: rawGenreCounts.compactMap { key, value in
                guard let genreID = Int(key) else { return nil }
                return (genreID, value)
            }
        )

        likedRatingAverage = defaults.double(forKey: Keys.likedRatingAverage)
        likedRuntimeAverage = defaults.double(forKey: Keys.likedRuntimeAverage)

        likedRatingSamples = defaults.integer(forKey: Keys.likedRatingSamples)
        likedRuntimeSamples = defaults.integer(forKey: Keys.likedRuntimeSamples)

        let storedDecisions = defaults.integer(forKey: Keys.onboardingDecisions)
        onboardingDecisions = storedDecisions == 0 ? likedIDs.count + dislikedIDs.count : storedDecisions
    }

    func feedbackState(for movieID: Int) -> MovieFeedbackState {
        if likedMovieIDs.contains(movieID) {
            return .liked
        }

        if dislikedMovieIDs.contains(movieID) {
            return .disliked
        }

        return .unrated
    }

    func recordFeedback(movie: Movie, liked: Bool) {
        setFeedback(movie: movie, liked: liked)
    }

    func setFeedback(movie: Movie, liked: Bool) {
        let desiredState: MovieFeedbackState = liked ? .liked : .disliked
        applyFeedback(movie: movie, desiredState: desiredState)
    }

    func clearFeedback(movie: Movie) {
        applyFeedback(movie: movie, desiredState: .unrated)
    }

    func toggleFeedback(movie: Movie, liked: Bool) {
        let desiredState: MovieFeedbackState = liked ? .liked : .disliked
        let current = feedbackState(for: movie.id)

        if current == desiredState {
            clearFeedback(movie: movie)
        } else {
            setFeedback(movie: movie, liked: liked)
        }
    }

    private func applyFeedback(movie: Movie, desiredState: MovieFeedbackState) {
        let movieID = movie.id
        let previousState = feedbackState(for: movieID)
        let calibrationLabel: Bool?
        switch desiredState {
        case .liked:
            calibrationLabel = true
        case .disliked:
            calibrationLabel = false
        case .unrated:
            calibrationLabel = nil
        }

        seenMovieIDs.insert(movieID)

        guard previousState != desiredState else {
            persist()
            return
        }

        let featuresBeforeUpdate = personalizerFeatures(for: movie)
        let isFirstRating = previousState == .unrated

        if previousState == .liked {
            removeLikeStats(movie: movie)
            likedMovieIDs.remove(movieID)
        } else if previousState == .disliked {
            dislikedMovieIDs.remove(movieID)
        }

        if desiredState == .liked {
            likedMovieIDs.insert(movieID)
            addLikeStats(movie: movie)
        } else if desiredState == .disliked {
            dislikedMovieIDs.insert(movieID)
        }

        if isFirstRating {
            onboardingDecisions += 1
        }

        if let calibrationLabel {
            calibrator.observe(features: featuresBeforeUpdate, liked: calibrationLabel)
        }
        persist()
    }

    func markMoviesSeen(_ ids: [Int]) {
        guard !ids.isEmpty else { return }

        var changed = false
        for id in ids where seenMovieIDs.insert(id).inserted {
            changed = true
        }

        if changed {
            persist()
        }
    }

    func recommendationScore(for movie: Movie) -> Double {
        let genreScore = genreMatchScore(for: movie)
        let ratingScore = ratingScore(for: movie)
        let runtimeScore = runtimeScore(for: movie)
        let heuristicScore = 0.5 * genreScore + 0.3 * ratingScore + 0.2 * runtimeScore

        let userAvgRatingForML = likedRatingSamples > 0 ? likedRatingAverage : 7.0
        let userAvgRuntimeForML = likedRuntimeSamples > 0 ? likedRuntimeAverage : 110.0
        let movieRuntimeForML = Double(movie.runtime ?? Int(userAvgRuntimeForML.rounded()))

        // Model was trained with binary fit features and raw movie/user stats.
        let features: [String: Double] = [
            CoreMLScorer.Schema.genreMatch: genreScore >= 0.2 ? 1.0 : 0.0,
            CoreMLScorer.Schema.ratingFit: ratingScore >= 0.8 ? 1.0 : 0.0,
            CoreMLScorer.Schema.runtimeFit: runtimeScore >= 0.8 ? 1.0 : 0.0,
            CoreMLScorer.Schema.movieRating: movie.voteAverage,
            CoreMLScorer.Schema.movieRuntime: movieRuntimeForML,
            CoreMLScorer.Schema.userAvgRating: userAvgRatingForML,
            CoreMLScorer.Schema.userAvgRuntime: userAvgRuntimeForML,
            CoreMLScorer.Schema.likedCount: Double(likedMovieIDs.count),
            CoreMLScorer.Schema.dislikedCount: Double(dislikedMovieIDs.count)
        ]

        let modelScore = coreMLScorer.score(features: features)
        let baseScore = modelScore.map { score in
            clamp(0.6 * score + 0.4 * heuristicScore)
        } ?? heuristicScore
        let personalizerScore = calibrator.predict(
            features: personalizerFeatures(
                movie: movie,
                genreScore: genreScore,
                ratingScore: ratingScore,
                runtimeScore: runtimeScore,
                userAvgRating: userAvgRatingForML,
                userAvgRuntime: userAvgRuntimeForML
            ),
            fallback: baseScore
        )

        return clamp(0.7 * baseScore + 0.3 * personalizerScore)
    }

    func isHotRecommendation(for movie: Movie) -> Bool {
        recommendationScore(for: movie) >= Self.hotRecommendationThreshold
    }

    private func genreMatchScore(for movie: Movie) -> Double {
        guard !movie.genres.isEmpty else { return 0.0 }

        let totalLikes = genreLikeCounts.values.reduce(0, +)
        guard totalLikes > 0 else { return 0.0 }

        let matchedLikes = movie.genres.reduce(0) { partialResult, genre in
            partialResult + genreLikeCounts[genre.id, default: 0]
        }

        return min(Double(matchedLikes) / Double(totalLikes), 1.0)
    }

    private func ratingScore(for movie: Movie) -> Double {
        if likedRatingSamples == 0 {
            return max(0.0, min(movie.voteAverage / 10.0, 1.0))
        }

        let diff = abs(movie.voteAverage - likedRatingAverage)
        return max(0.0, 1.0 - (diff / 10.0))
    }

    private func runtimeScore(for movie: Movie) -> Double {
        guard likedRuntimeSamples > 0 else { return 0.5 }
        guard let runtime = movie.runtime else { return 0.5 }

        let diff = abs(Double(runtime) - likedRuntimeAverage)
        return max(0.0, 1.0 - diff / 120.0)
    }

    private func rollingAverage(currentAverage: Double, sampleCount: Int, newValue: Double) -> Double {
        let total = currentAverage * Double(sampleCount) + newValue
        return total / Double(sampleCount + 1)
    }

    private func addLikeStats(movie: Movie) {
        for genre in movie.genres {
            genreLikeCounts[genre.id, default: 0] += 1
        }

        likedRatingAverage = rollingAverage(
            currentAverage: likedRatingAverage,
            sampleCount: likedRatingSamples,
            newValue: movie.voteAverage
        )
        likedRatingSamples += 1

        if let runtime = movie.runtime {
            likedRuntimeAverage = rollingAverage(
                currentAverage: likedRuntimeAverage,
                sampleCount: likedRuntimeSamples,
                newValue: Double(runtime)
            )
            likedRuntimeSamples += 1
        }
    }

    private func removeLikeStats(movie: Movie) {
        for genre in movie.genres {
            guard let current = genreLikeCounts[genre.id] else { continue }

            if current <= 1 {
                genreLikeCounts.removeValue(forKey: genre.id)
            } else {
                genreLikeCounts[genre.id] = current - 1
            }
        }

        if likedRatingSamples > 0 {
            if likedRatingSamples == 1 {
                likedRatingAverage = 0
                likedRatingSamples = 0
            } else {
                let total = likedRatingAverage * Double(likedRatingSamples) - movie.voteAverage
                likedRatingSamples -= 1
                likedRatingAverage = total / Double(likedRatingSamples)
            }
        }

        if let runtime = movie.runtime, likedRuntimeSamples > 0 {
            if likedRuntimeSamples == 1 {
                likedRuntimeAverage = 0
                likedRuntimeSamples = 0
            } else {
                let total = likedRuntimeAverage * Double(likedRuntimeSamples) - Double(runtime)
                likedRuntimeSamples -= 1
                likedRuntimeAverage = total / Double(likedRuntimeSamples)
            }
        }
    }

    private func personalizerFeatures(for movie: Movie) -> [Double] {
        personalizerFeatures(
            movie: movie,
            genreScore: genreMatchScore(for: movie),
            ratingScore: ratingScore(for: movie),
            runtimeScore: runtimeScore(for: movie),
            userAvgRating: likedRatingSamples > 0 ? likedRatingAverage : 7.0,
            userAvgRuntime: likedRuntimeSamples > 0 ? likedRuntimeAverage : 110.0
        )
    }

    private func personalizerFeatures(
        movie: Movie,
        genreScore: Double,
        ratingScore: Double,
        runtimeScore: Double,
        userAvgRating: Double,
        userAvgRuntime: Double
    ) -> [Double] {
        let movieRuntime = Double(movie.runtime ?? Int(userAvgRuntime.rounded()))

        return [
            clamp(genreScore),
            clamp(ratingScore),
            clamp(runtimeScore),
            clamp(movie.voteAverage / 10.0),
            clamp(movieRuntime / 240.0),
            clamp(userAvgRating / 10.0),
            clamp(userAvgRuntime / 240.0),
            clamp(Double(likedMovieIDs.count) / 60.0),
            clamp(Double(dislikedMovieIDs.count) / 60.0)
        ]
    }

    private func clamp(_ value: Double) -> Double {
        max(0.0, min(value, 1.0))
    }

    private func persist() {
        defaults.set(Array(likedMovieIDs), forKey: Keys.likedMovieIDs)
        defaults.set(Array(dislikedMovieIDs), forKey: Keys.dislikedMovieIDs)
        defaults.set(Array(seenMovieIDs), forKey: Keys.seenMovieIDs)

        let rawGenreCounts = Dictionary(
            uniqueKeysWithValues: genreLikeCounts.map { key, value in
                (String(key), value)
            }
        )
        defaults.set(rawGenreCounts, forKey: Keys.genreLikeCounts)

        defaults.set(likedRatingAverage, forKey: Keys.likedRatingAverage)
        defaults.set(likedRuntimeAverage, forKey: Keys.likedRuntimeAverage)
        defaults.set(likedRatingSamples, forKey: Keys.likedRatingSamples)
        defaults.set(likedRuntimeSamples, forKey: Keys.likedRuntimeSamples)
        defaults.set(onboardingDecisions, forKey: Keys.onboardingDecisions)
    }
}

private enum Keys {
    static let likedMovieIDs = "taste_liked_movie_ids"
    static let dislikedMovieIDs = "taste_disliked_movie_ids"
    static let seenMovieIDs = "taste_seen_movie_ids"
    static let genreLikeCounts = "taste_genre_like_counts"
    static let likedRatingAverage = "taste_liked_rating_average"
    static let likedRuntimeAverage = "taste_liked_runtime_average"
    static let likedRatingSamples = "taste_liked_rating_samples"
    static let likedRuntimeSamples = "taste_liked_runtime_samples"
    static let onboardingDecisions = "taste_onboarding_decisions"
}
