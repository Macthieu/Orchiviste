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
    public let deterministic_score: Double
    public let ml_score: Double
    public let semantic_score: Double
    public let reasons: [String]
    public let sources: [String]

    public init(
        rule: LoadedNamingRule,
        score: Double,
        deterministic_score: Double,
        ml_score: Double,
        semantic_score: Double = 0,
        reasons: [String],
        sources: [String]
    ) {
        self.rule = rule
        self.score = score
        self.deterministic_score = deterministic_score
        self.ml_score = ml_score
        self.semantic_score = semantic_score
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

    public init(
        providers: [NamingPredictionProvider] = [
            CoreMLNamingPredictionProvider(),
            EmbeddingNamingPredictionProvider(),
        ]
    ) {
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
    private static let coreMLSourceID = "coreml"
    private static let semanticSourceID = EmbeddingNamingPredictionProvider.providerSourceID

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
            let mlScore = maxScore(
                for: candidate.rule_id,
                in: mlByRule,
                source: Self.coreMLSourceID
            )
            let semanticScore = maxScore(
                for: candidate.rule_id,
                in: mlByRule,
                source: Self.semanticSourceID
            )
            let auxiliaryScore = maxScoreExcluding(
                for: candidate.rule_id,
                in: mlByRule,
                excludedSources: [Self.coreMLSourceID, Self.semanticSourceID]
            )
            let assistedScore = blendedAssistedScore(
                coreMLScore: mlScore,
                semanticScore: semanticScore,
                auxiliaryScore: auxiliaryScore
            )
            let finalScore: Double
            if assistedScore > 0 {
                finalScore = min(1.0, (deterministicScore * 0.30) + (assistedScore * 0.70))
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
            return RankedNamingRule(
                rule: candidate,
                score: finalScore,
                deterministic_score: deterministicScore,
                ml_score: mlScore,
                semantic_score: semanticScore,
                reasons: reasons,
                sources: sources
            )
        }
        .sorted {
            if $0.score == $1.score {
                return $0.rule.rule_id < $1.rule.rule_id
            }
            return $0.score > $1.score
        }
    }

    private func maxScore(
        for ruleID: String,
        in groupedPredictions: [String: [NamingRulePrediction]],
        source: String
    ) -> Double {
        groupedPredictions[ruleID]?
            .filter { $0.source == source }
            .map(\.score)
            .max() ?? 0
    }

    private func maxScoreExcluding(
        for ruleID: String,
        in groupedPredictions: [String: [NamingRulePrediction]],
        excludedSources: Set<String>
    ) -> Double {
        groupedPredictions[ruleID]?
            .filter { !excludedSources.contains($0.source) }
            .map(\.score)
            .max() ?? 0
    }

    private func maxScoreExcluding(
        for ruleID: String,
        in groupedPredictions: [String: [NamingRulePrediction]],
        excludedSources: [String]
    ) -> Double {
        maxScoreExcluding(
            for: ruleID,
            in: groupedPredictions,
            excludedSources: Set(excludedSources)
        )
    }

    private func blendedAssistedScore(
        coreMLScore: Double,
        semanticScore: Double,
        auxiliaryScore: Double
    ) -> Double {
        if coreMLScore > 0, semanticScore > 0 {
            return min(1.0, (coreMLScore * 0.65) + (semanticScore * 0.35))
        }
        if coreMLScore > 0 {
            return max(coreMLScore, auxiliaryScore)
        }
        if semanticScore > 0 {
            return max(semanticScore, auxiliaryScore)
        }
        return auxiliaryScore
    }
}

public struct EmbeddingNamingPredictionProvider: NamingPredictionProvider {
    public static let providerSourceID = "embedding_similarity"
    public let provider_id = providerSourceID

    private let enabled: Bool
    private let indexPath: String?
    private let topK: Int
    private let minScore: Double

    public init(
        enabled: Bool? = nil,
        indexPath: String? = nil,
        topK: Int? = nil,
        minScore: Double? = nil
    ) {
        let resolvedPath = indexPath
            ?? namingTrimmedEnvironment("ORCHIVISTE_NAMING_EMBEDDINGS_INDEX_PATH")
            ?? namingTrimmedEnvironment("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_INDEX_PATH")
        self.indexPath = resolvedPath
        let defaultEnabled = resolvedPath != nil
        self.enabled = enabled ?? namingEnvironmentBool(
            "ORCHIVISTE_NAMING_EMBEDDINGS_ENABLED",
            defaultValue: defaultEnabled
        )
        self.topK = max(
            1,
            topK
                ?? namingEnvironmentInt("ORCHIVISTE_NAMING_EMBEDDINGS_TOP_K")
                ?? namingEnvironmentInt("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_TOP_K")
                ?? 8
        )
        self.minScore = max(
            0,
            minScore
                ?? namingEnvironmentDouble("ORCHIVISTE_NAMING_EMBEDDINGS_MIN_SCORE")
                ?? namingEnvironmentDouble("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_MIN_SCORE")
                ?? 0.12
        )
    }

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        guard enabled,
              let indexPath,
              !indexPath.isEmpty,
              !candidates.isEmpty else {
            return []
        }

        let mergedText = [
            request.text,
            request.metadata?.fileName,
            request.metadata?.originalName,
            request.sample_file_names.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !mergedText.isEmpty else {
            return []
        }

        let matches: [ScoredNamingEmbeddingReference]
        do {
            matches = try NamingEmbeddingReferenceRuntime.shared.search(
                indexPath: indexPath,
                text: mergedText,
                topK: topK
            )
        } catch {
            return []
        }
        guard !matches.isEmpty else {
            return []
        }

        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.rule_id, $0) })
        var predictionsByRule: [String: NamingRulePrediction] = [:]

        for match in matches where match.score >= minScore {
            let targets = predictionTargets(
                for: match.record,
                candidates: candidates,
                candidatesByID: candidatesByID
            )
            for target in targets {
                let weightedScore = max(0, min(1, match.score * target.weight))
                guard weightedScore >= max(0.05, minScore * 0.60) else {
                    continue
                }

                let reason = "embedding \(target.reason): \(match.record.reference_id)=\(String(format: "%.3f", match.score))"
                let existingScore = predictionsByRule[target.ruleID]?.score ?? 0
                if weightedScore > existingScore {
                    predictionsByRule[target.ruleID] = NamingRulePrediction(
                        rule_id: target.ruleID,
                        score: weightedScore,
                        source: provider_id,
                        reasons: [reason]
                    )
                }
            }
        }

        return predictionsByRule.values.sorted {
            if $0.score == $1.score {
                return $0.rule_id < $1.rule_id
            }
            return $0.score > $1.score
        }
    }

    private func predictionTargets(
        for record: NamingEmbeddingReferenceRecord,
        candidates: [LoadedNamingRule],
        candidatesByID: [String: LoadedNamingRule]
    ) -> [EmbeddingPredictionTarget] {
        var targets: [String: EmbeddingPredictionTarget] = [:]
        func upsert(ruleID: String, weight: Double, reason: String) {
            guard candidatesByID[ruleID] != nil else { return }
            let normalizedWeight = max(0, min(1, weight))
            if let existing = targets[ruleID], existing.weight >= normalizedWeight {
                return
            }
            targets[ruleID] = EmbeddingPredictionTarget(
                ruleID: ruleID,
                weight: normalizedWeight,
                reason: reason
            )
        }

        if let directRuleID = namingTrimmed(record.rule_id) {
            upsert(ruleID: directRuleID, weight: 1.00, reason: "rule_id")
        }
        if namingNormalizedKey(record.reference_kind) == "namingrule",
           let ruleID = namingTrimmed(record.reference_id) {
            upsert(ruleID: ruleID, weight: 0.96, reason: "reference_id")
        }

        if let classCode = namingNormalizedKey(record.class_code) {
            for candidate in candidates {
                let candidateCode = namingNormalizedKey(candidate.definition.metadata?.suggested_class_code)
                if candidateCode == classCode {
                    upsert(
                        ruleID: candidate.rule_id,
                        weight: 0.80,
                        reason: "class_code"
                    )
                }
            }
        }

        if let documentType = namingCanonicalDocumentType(
            namingTrimmed(record.metadata_type_document) ?? namingTrimmed(record.label)
        ) {
            for candidate in candidates where candidateMatchesDocumentType(candidate, documentType: documentType) {
                upsert(
                    ruleID: candidate.rule_id,
                    weight: 0.72,
                    reason: "document_type"
                )
            }
        }

        return Array(targets.values)
    }

    private func candidateMatchesDocumentType(
        _ candidate: LoadedNamingRule,
        documentType: String
    ) -> Bool {
        let signatures: [String?] = [
            candidate.definition.document_family,
            candidate.definition.label,
            candidate.definition.metadata?.canonical_output_label
        ] + (candidate.definition.conditions.source_document_families ?? [])
        let normalizedSignatures = Set(
            signatures.compactMap(namingCanonicalDocumentType)
        )
        return normalizedSignatures.contains(documentType)
    }
}

private struct EmbeddingPredictionTarget {
    let ruleID: String
    let weight: Double
    let reason: String
}

private struct NamingEmbeddingReferenceRecord: Decodable, Sendable {
    let reference_id: String
    let reference_kind: String
    let text: String
    let label: String?
    let class_code: String?
    let rule_id: String?
    let preset_id: String?
    let path_hint: String?
    let metadata_type_document: String?
}

private struct ScoredNamingEmbeddingReference: Sendable {
    let record: NamingEmbeddingReferenceRecord
    let score: Double
}

private final class NamingEmbeddingReferenceRuntime {
    static let shared = NamingEmbeddingReferenceRuntime()

    private let lock = NSLock()
    private var cache: [String: [NamingEmbeddingReferenceRecord]] = [:]

    private init() {}

    func search(
        indexPath: String,
        text: String,
        topK: Int
    ) throws -> [ScoredNamingEmbeddingReference] {
        let references = try loadReferences(indexPath: indexPath)
        let scored = references
            .map { record in
                ScoredNamingEmbeddingReference(
                    record: record,
                    score: namingTokenSimilarity(lhs: text, rhs: record.text)
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.record.reference_id < rhs.record.reference_id
            }
        if scored.isEmpty {
            return []
        }
        return Array(scored.prefix(max(1, topK)))
    }

    private func loadReferences(indexPath: String) throws -> [NamingEmbeddingReferenceRecord] {
        lock.lock()
        if let cached = cache[indexPath] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let url = URL(fileURLWithPath: indexPath)
        let data = try Data(contentsOf: url)
        let references: [NamingEmbeddingReferenceRecord]

        if url.pathExtension.lowercased() == "jsonl" {
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            references = lines.compactMap { line in
                try? JSONDecoder().decode(NamingEmbeddingReferenceRecord.self, from: Data(line.utf8))
            }
        } else {
            references = try JSONDecoder().decode([NamingEmbeddingReferenceRecord].self, from: data)
        }

        lock.lock()
        cache[indexPath] = references
        lock.unlock()
        return references
    }
}

private func namingEnvironmentBool(_ key: String, defaultValue: Bool) -> Bool {
    guard let raw = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(),
          !raw.isEmpty else {
        return defaultValue
    }
    return ["1", "true", "yes", "on"].contains(raw)
}

private func namingEnvironmentInt(_ key: String) -> Int? {
    guard let raw = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }
    return Int(raw)
}

private func namingEnvironmentDouble(_ key: String) -> Double? {
    guard let raw = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }
    return Double(raw)
}

private func namingTrimmedEnvironment(_ key: String) -> String? {
    guard let raw = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return nil
    }
    return raw
}

private func namingTrimmed(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        return nil
    }
    return value
}

private func namingNormalizedKey(_ value: String?) -> String? {
    guard let value = namingTrimmed(value) else {
        return nil
    }
    let normalized = normalizedSearchText(value).replacingOccurrences(of: " ", with: "")
    return normalized.isEmpty ? nil : normalized
}

private func namingCanonicalDocumentType(_ raw: String?) -> String? {
    guard let value = namingNormalizedKey(raw) else {
        return nil
    }
    if value.contains("resolution") {
        return "resolution"
    }
    if value.contains("entente") || value.contains("contrat") || value.contains("convention") || value.contains("bail") || value.contains("protocole") || value.contains("avenant") {
        return "entente"
    }
    if value.contains("procesverbal") || value == "pv" {
        return "procesverbal"
    }
    if value.contains("facture") || value.contains("invoice") {
        return "facture"
    }
    if value.contains("permis") {
        return "permis"
    }
    if value.contains("avismotion") {
        return "avismotion"
    }
    if value.contains("depot") {
        return "depot"
    }
    return nil
}

private func namingTokenSimilarity(lhs: String, rhs: String) -> Double {
    let lhsTokens = Set(namingFeatureTokens(from: lhs))
    let rhsTokens = Set(namingFeatureTokens(from: rhs))
    guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
        return 0
    }
    let intersection = lhsTokens.intersection(rhsTokens).count
    let scale = sqrt(Double(lhsTokens.count * rhsTokens.count))
    guard scale > 0 else {
        return 0
    }
    return Double(intersection) / scale
}

private func namingFeatureTokens(from text: String) -> [String] {
    let normalized = text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA"))
        .lowercased()
    let stopWords: Set<String> = [
        "avec", "dans", "pour", "sans", "par", "sur", "aux", "des", "les",
        "une", "que", "qui", "est", "sont", "dont", "ceci", "cela", "ville",
        "amos", "conseil", "municipal", "document", "fichier", "type", "objet", "resume"
    ]
    return normalized
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { token in
            token.count >= 3 && !stopWords.contains(token)
        }
}

#if canImport(CoreML)
public final class CoreMLNamingPredictionProvider: NamingPredictionProvider {
    public let provider_id = "coreml"
    private static let cacheLock = NSLock()
    private static var modelCache: [String: MLModel] = [:]
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

    public convenience init(
        modelURL: URL? = nil,
        ruleLabelMap: [String: String] = [:]
    ) {
        self.init(
            modelURL: modelURL,
            ruleLabelMap: ruleLabelMap,
            inputName: nil,
            outputName: nil,
            vectorSize: nil
        )
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
        let cacheKey = modelURL.path
        Self.cacheLock.lock()
        if let cached = Self.modelCache[cacheKey] {
            Self.cacheLock.unlock()
            return cached
        }
        Self.cacheLock.unlock()

        let loadedModel: MLModel?
        if modelURL.pathExtension == "mlmodelc" {
            loadedModel = try? MLModel(contentsOf: modelURL)
        } else if let compiledURL = try? MLModel.compileModel(at: modelURL) {
            loadedModel = try? MLModel(contentsOf: compiledURL)
        } else {
            loadedModel = try? MLModel(contentsOf: modelURL)
        }
        if let loadedModel {
            Self.cacheLock.lock()
            Self.modelCache[cacheKey] = loadedModel
            Self.cacheLock.unlock()
        }
        return loadedModel
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

    public convenience init(
        modelURL: URL? = nil,
        ruleLabelMap: [String: String] = [:]
    ) {
        self.init(
            modelURL: modelURL,
            ruleLabelMap: ruleLabelMap,
            inputName: nil,
            outputName: nil,
            vectorSize: nil
        )
    }

    public func predict(
        request: NamingPredictionRequest,
        candidates: [LoadedNamingRule]
    ) -> [NamingRulePrediction] {
        []
    }
}
#endif
