import Foundation

final class OnlineCalibrator {
    private enum Keys {
        static let weights = "personalizer_weights"
        static let bias = "personalizer_bias"
        static let updates = "personalizer_updates"
    }

    private let featureCount = 9
    private let defaults: UserDefaults

    private var weights: [Double]
    private var bias: Double
    private(set) var updateCount: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedWeights = defaults.array(forKey: Keys.weights) as? [Double] ?? []
        if storedWeights.count == featureCount {
            weights = storedWeights
        } else {
            weights = Array(repeating: 0.0, count: featureCount)
        }

        bias = defaults.double(forKey: Keys.bias)
        updateCount = defaults.integer(forKey: Keys.updates)
    }

    func predict(features: [Double], fallback: Double) -> Double {
        guard features.count == featureCount else {
            return clamp(fallback)
        }

        if updateCount == 0 {
            return clamp(fallback)
        }

        let z = dot(features: features)
        return sigmoid(z)
    }

    func observe(features: [Double], liked: Bool) {
        guard features.count == featureCount else { return }

        let target = liked ? 1.0 : 0.0
        let prediction = sigmoid(dot(features: features))
        let error = prediction - target
        let learningRate = adaptiveLearningRate(for: updateCount)

        for index in 0..<featureCount {
            weights[index] -= learningRate * error * features[index]
            weights[index] = clamp(weights[index], min: -6.0, max: 6.0)
        }

        bias -= learningRate * error
        bias = clamp(bias, min: -6.0, max: 6.0)

        updateCount += 1
        persist()
    }

    private func dot(features: [Double]) -> Double {
        var total = bias
        for index in 0..<featureCount {
            total += weights[index] * features[index]
        }
        return total
    }

    private func adaptiveLearningRate(for updates: Int) -> Double {
        let progress = Double(updates) / 30.0
        return max(0.015, 0.08 / sqrt(1.0 + progress))
    }

    private func sigmoid(_ value: Double) -> Double {
        1.0 / (1.0 + exp(-value))
    }

    private func persist() {
        defaults.set(weights, forKey: Keys.weights)
        defaults.set(bias, forKey: Keys.bias)
        defaults.set(updateCount, forKey: Keys.updates)
    }

    private func clamp(_ value: Double, min: Double = 0.0, max: Double = 1.0) -> Double {
        Swift.max(min, Swift.min(value, max))
    }
}
