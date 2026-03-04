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
    private let configuredInputName: String?
    private let configuredOutputName: String?
    private let configuredVectorSize: Int?
    private lazy var model: MLModel? = loadModel()

    public init(
        modelURL: URL? = nil,
        ruleLabelMap: [String: String] = [:],
        inputName: String? = nil,
        outputName: String? = nil,
        vectorSize: Int? = nil
    ) {
        self.modelURL = modelURL ?? CoreMLNamingPredictionProvider.defaultModelURL()
        self.ruleLabelMap = ruleLabelMap
        self.configuredInputName = inputName ?? ProcessInfo.processInfo.environment["ORCHIVISTE_NAMING_COREML_INPUT_NAME"]
        self.configuredOutputName = outputName ?? ProcessInfo.processInfo.environment["ORCHIVISTE_NAMING_COREML_OUTPUT_NAME"]
        if let vectorSize {
            self.configuredVectorSize = max(1, vectorSize)
        } else if let raw = ProcessInfo.processInfo.environment["ORCHIVISTE_NAMING_COREML_VECTOR_SIZE"],
                  let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
                  parsed > 0 {
            self.configuredVectorSize = parsed
        } else {
            self.configuredVectorSize = nil
        }
    }

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        guard let model else {
            return []
        }

        if let predictions = predictWithStringInput(model: model, request: request, candidates: candidates),
           !predictions.isEmpty {
            return predictions
        }

        if let predictions = predictWithVectorInput(model: model, request: request, candidates: candidates),
           !predictions.isEmpty {
            return predictions
        }

        return []
    }

    private func predictWithStringInput(
        model: MLModel,
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction]? {
        let inputName = configuredInputName ?? model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .string })?.key
        guard let inputName else {
            return nil
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(string: request.text)]),
              let output = try? model.prediction(from: provider) else {
            return nil
        }

        let candidateIDs = Set(candidates.map(\.rule_id))
        if let probabilities = firstProbabilityDictionary(from: output) {
            let predictions = probabilities.compactMap { entry -> NamingRulePrediction? in
                let (rawLabel, score) = entry
                let label = mappedRuleID(for: String(describing: rawLabel))
                guard candidateIDs.contains(label) else { return nil }
                return NamingRulePrediction(
                    rule_id: label,
                    score: max(0, min(1, score)),
                    source: provider_id,
                    reasons: ["scoring Core ML texte"]
                )
            }
            return predictions.isEmpty ? nil : predictions
        }

        if let label = firstLabel(from: output) {
            let ruleID = mappedRuleID(for: label)
            guard candidateIDs.contains(ruleID) else { return nil }
            return [
                NamingRulePrediction(
                    rule_id: ruleID,
                    score: 0.9,
                    source: provider_id,
                    reasons: ["classification Core ML texte"]
                )
            ]
        }
        return nil
    }

    private func predictWithVectorInput(
        model: MLModel,
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction]? {
        let inputName = configuredInputName
            ?? model.modelDescription.inputDescriptionsByName.first(where: { $0.value.type == .multiArray })?.key
        guard let inputName else {
            return nil
        }

        let inputDescription = model.modelDescription.inputDescriptionsByName[inputName]
        let vectorSize = configuredVectorSize
            ?? inferredVectorSize(from: inputDescription)
            ?? 16
        let featureVector = Self.defaultFeatureVector(
            request: request,
            candidates: candidates,
            targetLength: vectorSize
        )

        guard let featureProvider = try? vectorFeatureProvider(
            featureVector: featureVector,
            inputName: inputName
        ),
        let output = try? model.prediction(from: featureProvider),
        let scores = scoreArray(from: output, preferredName: configuredOutputName) else {
            return nil
        }

        let count = min(scores.count, candidates.count)
        guard count > 0 else {
            return []
        }

        return (0..<count).map { index in
            NamingRulePrediction(
                rule_id: candidates[index].rule_id,
                score: normalizedVectorScore(scores[index]),
                source: provider_id,
                reasons: ["scoring Core ML vectoriel"]
            )
        }
    }

    private func vectorFeatureProvider(
        featureVector: [Double],
        inputName: String
    ) throws -> MLDictionaryFeatureProvider {
        let array = try MLMultiArray(
            shape: [NSNumber(value: 1), NSNumber(value: featureVector.count)],
            dataType: .double
        )
        for (index, value) in featureVector.enumerated() {
            array[index] = NSNumber(value: value)
        }
        return try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: array)
        ])
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

    private func inferredVectorSize(from description: MLFeatureDescription?) -> Int? {
        guard let shape = description?.multiArrayConstraint?.shape else {
            return nil
        }
        let values = shape.map(\.intValue)
        if let last = values.last, last > 0 {
            return last
        }
        return nil
    }

    private func scoreArray(
        from output: MLFeatureProvider,
        preferredName: String?
    ) -> [Double]? {
        if let preferredName,
           let feature = output.featureValue(for: preferredName)?.multiArrayValue {
            return (0..<feature.count).map { feature[$0].doubleValue }
        }
        for name in output.featureNames {
            guard let feature = output.featureValue(for: name)?.multiArrayValue else { continue }
            return (0..<feature.count).map { feature[$0].doubleValue }
        }
        return nil
    }

    private func normalizedVectorScore(_ raw: Double) -> Double {
        if raw.isNaN || raw.isInfinite {
            return 0
        }
        if raw >= 0, raw <= 1 {
            return raw
        }
        return 1.0 / (1.0 + exp(-raw))
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

    static func defaultFeatureVector(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule],
        targetLength: Int = 16
    ) -> [Double] {
        let text = request.text
        let lowered = text.lowercased()
        let characters = Array(text)
        let wordCount = max(1, text.split { $0.isWhitespace || $0.isNewline }.count)
        let uppercaseCount = characters.filter(\.isUppercase).count
        let digitCount = characters.filter(\.isNumber).count
        let dashCount = characters.filter { "-–—".contains($0) }.count
        let lines = max(1, text.split(separator: "\n").count)
        let uniqueWords = Set(
            lowered.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !$0.isEmpty }
        ).count

        let keywordGroups = [
            ["résolution", "resolution", "procès-verbal", "proces-verbal", "conseil municipal"],
            ["entente", "contrat", "convention", "bail", "protocole", "avenant"],
            ["avis de motion", "règlement", "reglement"],
            ["dépôt", "declaration", "rapport financier"]
        ]

        var features: [Double] = [
            min(1.0, Double(text.count) / 4000.0),
            min(1.0, Double(wordCount) / 800.0),
            min(1.0, Double(lines) / 120.0),
            Double(uppercaseCount) / Double(max(1, characters.count)),
            Double(digitCount) / Double(max(1, characters.count)),
            Double(dashCount) / Double(max(1, characters.count)),
            min(1.0, Double(uniqueWords) / Double(wordCount)),
            min(1.0, Double(request.sample_count) / 25.0),
            min(1.0, Double(candidates.count) / 20.0),
            request.metadata?.fileName?.lowercased().hasSuffix(".pdf") == true ? 1.0 : 0.0,
            request.metadata?.originalName?.lowercased().hasSuffix(".pdf") == true ? 1.0 : 0.0,
            request.sample_file_names.isEmpty ? 0.0 : 1.0
        ]

        features.append(contentsOf: keywordGroups.map { group in
            group.contains { lowered.contains($0) } ? 1.0 : 0.0
        })

        if features.count > targetLength {
            return Array(features.prefix(targetLength))
        }
        if features.count < targetLength {
            features.append(contentsOf: repeatElement(0.0, count: targetLength - features.count))
        }
        return features
    }
}
#else
public final class CoreMLNamingPredictionProvider: NamingPredictionProvider {
    public let provider_id = "coreml"

    public init(
        modelURL: URL? = nil,
        ruleLabelMap: [String: String] = [:],
        inputName: String? = nil,
        outputName: String? = nil,
        vectorSize: Int? = nil
    ) {}

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        []
    }
}
#endif
