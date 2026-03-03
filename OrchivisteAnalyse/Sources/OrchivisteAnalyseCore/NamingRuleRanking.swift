import Foundation
import OrchivisteSharedKit

#if canImport(CoreML)
import CoreML
#endif

public struct NamingPredictionRequest: Sendable {
    public let text: String
    public let metadata: NamingSourceMetadata?
    public let sample_count: Int
    public let sample_file_names: [String]

    public init(
        text: String,
        metadata: NamingSourceMetadata? = nil,
        sample_count: Int = 1,
        sample_file_names: [String] = []
    ) {
        self.text = text
        self.metadata = metadata
        self.sample_count = sample_count
        self.sample_file_names = sample_file_names
    }
}

public struct NamingRulePrediction: Codable, Sendable {
    public let rule_id: String
    public let score: Double
    public let source: String
    public let reasons: [String]

    public init(rule_id: String, score: Double, source: String, reasons: [String]) {
        self.rule_id = rule_id
        self.score = score
        self.source = source
        self.reasons = reasons
    }
}

public struct RankedNamingRule: Sendable {
    public let rule: LoadedNamingRule
    public let score: Double
    public let reasons: [String]
    public let sources: [String]

    public init(rule: LoadedNamingRule, score: Double, reasons: [String], sources: [String]) {
        self.rule = rule
        self.score = score
        self.reasons = reasons
        self.sources = sources
    }
}

public protocol NamingPredictionProvider {
    var provider_id: String { get }
    func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction]
}

public struct DeterministicNamingPredictionProvider: NamingPredictionProvider {
    public let provider_id = "deterministic"

    public init() {}

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        let haystack = normalizedSearchText(
            ([request.text, request.metadata?.fileName, request.metadata?.originalName]
                .compactMap { $0 }
                + request.sample_file_names)
                .joined(separator: "\n")
        )

        return candidates.compactMap { record in
            let rule = record.definition
            var score = 0.0
            var reasons: [String] = []

            let signalHits = (rule.conditions.signals_any ?? []).filter { signal in
                haystack.contains(normalizedSearchText(signal))
            }
            if !signalHits.isEmpty {
                score += min(0.45, Double(signalHits.count) * 0.12)
                reasons.append("signaux: \(signalHits.prefix(3).joined(separator: ", "))")
            }

            let regexHits = (rule.conditions.regex_any ?? []).filter { pattern in
                request.text.range(of: pattern, options: .regularExpression) != nil
            }
            if !regexHits.isEmpty {
                score += min(0.40, Double(regexHits.count) * 0.20)
                reasons.append("regex: \(regexHits.count)")
            }

            let familyHits = (rule.conditions.source_document_families ?? []).filter { family in
                haystack.contains(normalizedSearchText(family))
            }
            if !familyHits.isEmpty {
                score += min(0.15, Double(familyHits.count) * 0.08)
                reasons.append("familles: \(familyHits.joined(separator: ", "))")
            }

            let sampleBonus = min(0.10, Double(max(0, request.sample_count - 1)) * 0.02)
            score = min(1.0, score + sampleBonus)

            guard score > 0 else {
                return nil
            }
            return NamingRulePrediction(
                rule_id: record.rule_id,
                score: score,
                source: provider_id,
                reasons: reasons
            )
        }
    }
}

public struct NamingMLScorer {
    private let providers: [NamingPredictionProvider]

    public init(providers: [NamingPredictionProvider] = [CoreMLNamingPredictionProvider()]) {
        self.providers = providers
    }

    public func score(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        providers.flatMap { $0.predict(request: request, candidates: candidates) }
    }
}

public struct NamingRuleRanker {
    private let deterministic: NamingPredictionProvider
    private let mlScorer: NamingMLScorer

    public init(
        deterministic: NamingPredictionProvider = DeterministicNamingPredictionProvider(),
        mlScorer: NamingMLScorer = NamingMLScorer()
    ) {
        self.deterministic = deterministic
        self.mlScorer = mlScorer
    }

    public func rank(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [RankedNamingRule] {
        guard !candidates.isEmpty else { return [] }

        let deterministicPredictions = deterministic.predict(request: request, candidates: candidates)
        let mlPredictions = mlScorer.score(request: request, candidates: candidates)
        let mlByRule = Dictionary(grouping: mlPredictions, by: \.rule_id)
        let deterministicByRule = Dictionary(grouping: deterministicPredictions, by: \.rule_id)

        return candidates.compactMap { candidate in
            let deterministicScore = deterministicByRule[candidate.rule_id]?.map(\.score).max() ?? 0
            let mlScore = mlByRule[candidate.rule_id]?.map(\.score).max() ?? 0
            let finalScore: Double
            if mlScore > 0 {
                finalScore = min(1.0, (deterministicScore * 0.35) + (mlScore * 0.65))
            } else {
                finalScore = deterministicScore
            }
            guard finalScore > 0 else {
                return nil
            }

            let reasons = (deterministicByRule[candidate.rule_id] ?? [])
                .flatMap(\.reasons)
                + (mlByRule[candidate.rule_id] ?? []).flatMap(\.reasons)
            let sources = Array(Set(
                (deterministicByRule[candidate.rule_id] ?? []).map(\.source)
                    + (mlByRule[candidate.rule_id] ?? []).map(\.source)
            )).sorted()
            return RankedNamingRule(rule: candidate, score: finalScore, reasons: reasons, sources: sources)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.rule.rule_id < $1.rule.rule_id
            }
            return $0.score > $1.score
        }
    }
}

#if canImport(CoreML)
public final class CoreMLNamingPredictionProvider: NamingPredictionProvider {
    public let provider_id = "coreml"
    private let modelURL: URL?
    private let ruleLabelMap: [String: String]
    private lazy var model: MLModel? = loadModel()

    public init(modelURL: URL? = nil, ruleLabelMap: [String: String] = [:]) {
        self.modelURL = modelURL ?? CoreMLNamingPredictionProvider.defaultModelURL()
        self.ruleLabelMap = ruleLabelMap
    }

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        guard let model,
              let inputName = model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .string })?.key else {
            return []
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(string: request.text)]),
              let output = try? model.prediction(from: provider) else {
            return []
        }

        let candidateIDs = Set(candidates.map(\.rule_id))
        if let probabilities = firstProbabilityDictionary(from: output) {
            return probabilities.compactMap { rawLabel, score in
                let label = mappedRuleID(for: String(describing: rawLabel))
                guard candidateIDs.contains(label) else { return nil }
                return NamingRulePrediction(
                    rule_id: label,
                    score: max(0, min(1, score)),
                    source: provider_id,
                    reasons: ["scoring Core ML"]
                )
            }
        }

        if let label = firstLabel(from: output) {
            let ruleID = mappedRuleID(for: label)
            guard candidateIDs.contains(ruleID) else { return [] }
            return [
                NamingRulePrediction(
                    rule_id: ruleID,
                    score: 0.9,
                    source: provider_id,
                    reasons: ["classification Core ML"]
                )
            ]
        }
        return []
    }

    private func mappedRuleID(for rawLabel: String) -> String {
        if let mapped = ruleLabelMap[rawLabel] {
            return mapped
        }
        return rawLabel
    }

    private func loadModel() -> MLModel? {
        guard let modelURL else { return nil }
        return try? MLModel(contentsOf: modelURL)
    }

    private func firstProbabilityDictionary(from output: MLFeatureProvider) -> [String: Double]? {
        for name in output.featureNames {
            guard let value = output.featureValue(for: name)?.dictionaryValue else { continue }
            var normalized: [String: Double] = [:]
            for (key, item) in value {
                if let score = item as? Double {
                    normalized[String(describing: key)] = score
                } else {
                    let number = item as NSNumber
                    normalized[String(describing: key)] = number.doubleValue
                }
            }
            if !normalized.isEmpty {
                return normalized
            }
        }
        return nil
    }

    private func firstLabel(from output: MLFeatureProvider) -> String? {
        for name in output.featureNames {
            if let stringValue = output.featureValue(for: name)?.stringValue, !stringValue.isEmpty {
                return stringValue
            }
        }
        return nil
    }

    private static func defaultModelURL() -> URL? {
        guard let raw = ProcessInfo.processInfo.environment["ORCHIVISTE_NAMING_COREML_MODEL"],
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: raw)
    }
}
#else
public final class CoreMLNamingPredictionProvider: NamingPredictionProvider {
    public let provider_id = "coreml"

    public init(modelURL: URL? = nil, ruleLabelMap: [String: String] = [:]) {}

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        []
    }
}
#endif
