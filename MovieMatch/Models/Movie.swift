import Foundation

struct Movie: Identifiable, Hashable {
    let id: Int
    let title: String
    let genres: [Genre]
    let voteAverage: Double
    let runtime: Int?
    let posterPath: String?

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var runtimeText: String {
        guard let runtime else { return "-- мин" }
        return "\(runtime) мин"
    }

    var genreLine: String {
        let names = genres.map(\.name)
        guard !names.isEmpty else { return "Жанр не указан" }
        return names.joined(separator: ", ")
    }
}

struct Genre: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
}
