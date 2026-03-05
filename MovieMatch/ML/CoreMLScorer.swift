import Foundation
import CoreML

final class CoreMLScorer {
    enum Schema {
        static let preferredModelNames = ["MovieClass", "MovieTasteClassifier"]

        // Input features expected by the model.
        static let genreMatch = "genre_match"
        static let ratingFit = "rating_fit"
        static let runtimeFit = "runtime_fit"
        static let movieRating = "movie_rating"
        static let movieRuntime = "movie_runtime"
        static let userAvgRating = "user_avg_rating"
        static let userAvgRuntime = "user_avg_runtime"
        static let likedCount = "liked_count"
        static let dislikedCount = "disliked_count"

        // Common output names produced by classifiers.
        static let predictedTarget = "target"
        static let likeProbability = "likeProbability"
        static let classProbability = "classProbability"
        static let targetProbability = "targetProbability"
    }

    private let model: MLModel?

    init(bundle: Bundle = .main) {
        var resolvedModel: MLModel?

        for name in Schema.preferredModelNames {
            if let compiledURL = bundle.url(forResource: name, withExtension: "mlmodelc"),
               let loadedModel = try? MLModel(contentsOf: compiledURL) {
                resolvedModel = loadedModel
                break
            }
        }

        model = resolvedModel
    }

    var isAvailable: Bool {
        model != nil
    }

    func score(features: [String: Double]) -> Double? {
        guard let model else { return nil }

        let dictionary: [String: Any] = features.reduce(into: [:]) { partialResult, item in
            partialResult[item.key] = item.value
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: dictionary) else {
            return nil
        }

        guard let output = try? model.prediction(from: provider) else {
            return nil
        }

        return probability(from: output)
    }

    private func probability(from output: MLFeatureProvider) -> Double? {
        if let value = output.featureValue(for: Schema.likeProbability)?.doubleValue {
            return clamp(value)
        }

        if let value = output.featureValue(for: Schema.targetProbability)?.doubleValue {
            return clamp(value)
        }

        if let dictionary = output.featureValue(for: Schema.classProbability)?.dictionaryValue {
            return probability(from: dictionary)
        }

        if let dictionary = output.featureValue(for: Schema.targetProbability)?.dictionaryValue {
            return probability(from: dictionary)
        }

        if let predicted = output.featureValue(for: Schema.predictedTarget)?.stringValue {
            return predicted.lowercased() == "like" ? 1.0 : 0.0
        }

        if let predicted = output.featureValue(for: Schema.predictedTarget)?.int64Value {
            return predicted == 1 ? 1.0 : 0.0
        }

        return nil
    }

    private func probability(from dictionary: [AnyHashable: Any]) -> Double? {
        if let like = dictionaryDouble(dictionary, key: "like") {
            return clamp(like)
        }
        if let like = dictionaryDouble(dictionary, key: "1") {
            return clamp(like)
        }
        if let dislike = dictionaryDouble(dictionary, key: "dislike") {
            return clamp(1.0 - dislike)
        }
        if let dislike = dictionaryDouble(dictionary, key: "0") {
            return clamp(1.0 - dislike)
        }
        return nil
    }

    private func dictionaryDouble(_ dictionary: [AnyHashable: Any], key: String) -> Double? {
        let direct = dictionary[key]
        let lowercased = dictionary.first { element in
            (element.key as? String)?.lowercased() == key.lowercased()
        }?.value

        if let value = direct as? Double {
            return value
        }
        if let number = direct as? NSNumber {
            return number.doubleValue
        }
        if let value = lowercased as? Double {
            return value
        }
        if let number = lowercased as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private func clamp(_ value: Double) -> Double {
        max(0.0, min(value, 1.0))
    }
}
