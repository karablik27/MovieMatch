import SwiftUI

struct MovieGridCard: View {
    let movie: Movie
    let feedbackState: MovieFeedbackState
    var showFlame: Bool = false
    var recommendationScore: Double? = nil
    var onLike: (() -> Void)? = nil
    var onDislike: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: movie.posterURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(movie.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .topLeading)

            HStack(spacing: 8) {
                Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                    .lineLimit(1)

                if feedbackState == .liked {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.green)
                }

                if feedbackState == .disliked {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }

                if showFlame {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 18, alignment: .leading)

            Text(movie.runtimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 18, alignment: .leading)

            Text(recommendationText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)

            HStack(spacing: 8) {
                feedbackButton(
                    symbol: "hand.thumbsdown.fill",
                    tint: .red,
                    isActive: feedbackState == .disliked,
                    action: onDislike
                )

                feedbackButton(
                    symbol: "hand.thumbsup.fill",
                    tint: .green,
                    isActive: feedbackState == .liked,
                    action: onLike
                )
            }
            .frame(height: 34)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
            Image(systemName: "film")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var recommendationText: String {
        guard let recommendationScore else { return " " }
        return "Совпадение: \(Int(recommendationScore * 100))%"
    }

    @ViewBuilder
    private func feedbackButton(
        symbol: String,
        tint: Color,
        isActive: Bool,
        action: (() -> Void)?
    ) -> some View {
        if let action {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isActive ? tint.opacity(0.2) : Color.gray.opacity(0.15))
                    )
                    .foregroundStyle(isActive ? tint : .secondary)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
        }
    }
}
