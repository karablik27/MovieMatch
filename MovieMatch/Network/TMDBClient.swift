import Foundation

@MainActor
final class TMDBClient {
    struct PagedMovies {
        let movies: [Movie]
        let hasMore: Bool
    }

    enum TMDBError: LocalizedError {
        case missingCredentials
        case invalidURL
        case invalidResponse
        case httpError(code: Int)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Добавьте TMDB API Key или Bearer Token в TMDBConfiguration.swift"
            case .invalidURL:
                return "Некорректный URL TMDB"
            case .invalidResponse:
                return "Некорректный ответ сервера"
            case let .httpError(code):
                return "TMDB вернул ошибку HTTP \(code)"
            }
        }
    }

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let baseURL = URL(string: "https://api.themoviedb.org/3")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchMovies(ids: [Int]) async throws -> [Movie] {
        var seen = Set<Int>()
        let uniqueIDs = ids.filter { seen.insert($0).inserted }
        return try await fetchMoviesDetails(ids: uniqueIDs)
    }

    func fetchPopularMovies(limit: Int, excluding excludedIDs: Set<Int> = []) async throws -> [Movie] {
        guard limit > 0 else { return [] }

        var collectedMovies: [Movie] = []
        var usedIDs = excludedIDs
        var page = 1
        var hasMorePages = true

        while collectedMovies.count < limit && hasMorePages {
            let pageResult = try await fetchPopularMoviesPage(page: page, excluding: usedIDs)
            hasMorePages = pageResult.hasMore

            for movie in pageResult.movies where !usedIDs.contains(movie.id) {
                collectedMovies.append(movie)
                usedIDs.insert(movie.id)

                if collectedMovies.count >= limit {
                    break
                }
            }

            page += 1
        }

        return Array(collectedMovies.prefix(limit))
    }

    func fetchPopularMoviesPage(page: Int, excluding excludedIDs: Set<Int> = []) async throws -> PagedMovies {
        guard page > 0 else {
            return PagedMovies(movies: [], hasMore: false)
        }

        let response: PopularResponse = try await request(
            path: "movie/popular",
            queryItems: [
                URLQueryItem(name: "language", value: TMDBConfiguration.defaultLanguage),
                URLQueryItem(name: "page", value: String(page))
            ]
        )

        var usedIDs = Set<Int>()
        var idsToLoad: [Int] = []
        idsToLoad.reserveCapacity(response.results.count)

        for result in response.results {
            guard !excludedIDs.contains(result.id) else { continue }
            guard usedIDs.insert(result.id).inserted else { continue }
            idsToLoad.append(result.id)
        }

        let movies = try await fetchMoviesDetails(ids: idsToLoad)
        let hasMore = response.page < response.totalPages

        return PagedMovies(movies: movies, hasMore: hasMore)
    }

    private func fetchMoviesDetails(ids: [Int]) async throws -> [Movie] {
        guard !ids.isEmpty else { return [] }

        var movies: [Movie] = []
        movies.reserveCapacity(ids.count)

        for movieID in ids {
            let movie = try await fetchMovieDetails(id: movieID)
            movies.append(movie)
        }

        return movies
    }

    private func fetchMovieDetails(id: Int) async throws -> Movie {
        let details: MovieDetailsResponse = try await request(
            path: "movie/\(id)",
            queryItems: [URLQueryItem(name: "language", value: TMDBConfiguration.defaultLanguage)]
        )

        return Movie(
            id: details.id,
            title: details.title,
            genres: details.genres.map { Genre(id: $0.id, name: $0.name) },
            voteAverage: details.voteAverage,
            runtime: details.runtime,
            posterPath: details.posterPath
        )
    }

    private func request<Response: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> Response {
        let token = TMDBConfiguration.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = TMDBConfiguration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty || !apiKey.isEmpty else {
            throw TMDBError.missingCredentials
        }

        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        var allQueryItems = queryItems

        if !apiKey.isEmpty {
            allQueryItems.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        components?.queryItems = allQueryItems

        guard let url = components?.url else {
            throw TMDBError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "accept")

        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TMDBError.httpError(code: httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

private struct PopularResponse: Decodable {
    let page: Int
    let totalPages: Int
    let results: [PopularMovieResult]

    enum CodingKeys: String, CodingKey {
        case page
        case totalPages = "total_pages"
        case results
    }
}

private struct PopularMovieResult: Decodable {
    let id: Int
}

private struct MovieDetailsResponse: Decodable {
    let id: Int
    let title: String
    let genres: [MovieGenreResponse]
    let voteAverage: Double
    let runtime: Int?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case genres
        case voteAverage = "vote_average"
        case runtime
        case posterPath = "poster_path"
    }
}

private struct MovieGenreResponse: Decodable {
    let id: Int
    let name: String
}
