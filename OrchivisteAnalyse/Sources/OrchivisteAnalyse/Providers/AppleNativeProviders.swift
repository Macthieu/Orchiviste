import Foundation
import Vapor
#if canImport(CoreML)
import CoreML
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleCoreMLProvider: AnalysisProvider {
    let name = "AppleCoreML"
    let weight: Double = 0.95

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        guard localProviderEnabled("ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_ENABLED") else {
            return nil
        }
        guard let modelPath = nonEmpty(Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_MODEL_PATH")) else {
            logger.debug("AppleCoreML inactif: modèle absent.")
            return nil
        }
        guard let sourceText = analysisSourceText(for: request) else {
            return nil
        }

        #if canImport(CoreML)
        let prediction = try await AppleCoreMLRuntime.shared.predict(
            modelPath: modelPath,
            textFeatureName: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_INPUT_TEXT") ?? "text",
            labelFeatureName: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_LABEL") ?? "label",
            probabilityFeatureName: Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_PROBABILITIES") ?? "labelProbability",
            text: sourceText
        )
        guard let prediction else {
            return nil
        }

        let typeDoc = canonicalTypeDocument(from: prediction.label)
        let classCode = classCode(for: typeDoc)
        let preset = presetID(for: typeDoc) ?? request.preset_id
        let confidence = min(0.99, max(0.2, prediction.confidence))

        var champs: [String: String] = [
            "doc_type_hint": typeDoc,
            "metadata.type_document": typeDoc,
            "apple_coreml.label": prediction.label
        ]
        if let probability = prediction.probabilities[prediction.label] {
            champs["apple_coreml.label_confidence"] = String(format: "%.4f", probability)
        }

        return ProviderCandidate(
            provider: name,
            typeDoc: typeDoc,
            sujets: defaultSubjects(for: typeDoc),
            hasSignature: false,
            pages: max(1, estimatedPages(for: request.text)),
            champs: champs,
            confidence: confidence,
            suggestedPreset: preset,
            suggestedClassCode: classCode,
            matchedRules: ["apple_coreml_local_model"],
            topNodes: [classCode ?? typeDoc],
            capture: nil,
            review: nil
        )
        #else
        logger.debug("AppleCoreML indisponible: framework CoreML absent.")
        return nil
        #endif
    }
}

struct AppleFoundationModelsProvider: AnalysisProvider {
    let name = "AppleFoundationModels"
    let weight: Double = 0.7

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        guard localProviderEnabled("ORCHIVISTE_ANALYSE_PROVIDER_APPLE_FM_ENABLED", defaultEnabled: true) else {
            return nil
        }
        guard let sourceText = analysisSourceText(for: request) else {
            return nil
        }

        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            logger.debug("AppleFoundationModels indisponible: macOS 26 requis.")
            return nil
        }

        guard let enrichment = try await AppleFoundationModelsRuntime.generate(
            fileID: request.file_id,
            text: sourceText,
            logger: logger
        ) else {
            return nil
        }

        let sanitized = sanitizeFoundationModelEnrichment(enrichment, sourceText: sourceText)
        let typeDoc = canonicalTypeDocument(from: sanitized.typeDocument)
        let classCode = classCode(for: typeDoc)
        let preset = presetID(for: typeDoc) ?? request.preset_id

        var champs: [String: String] = [:]
        if typeDoc != "Autre" {
            champs["metadata.type_document"] = typeDoc
            champs["doc_type_hint"] = typeDoc
        }
        if let number = nonEmpty(sanitized.documentNumber) {
            champs["metadata.numero_document"] = number
            champs["numero"] = number
        }
        if let object = nonEmpty(sanitized.object) {
            champs["metadata.objet"] = object
            champs["document_objet"] = object
            champs["summary.title"] = object
        }
        if let date = nonEmpty(sanitized.documentDate) {
            champs["metadata.date_document"] = date
            champs["date_document"] = date
            champs["date"] = date
        }
        if let issuer = nonEmpty(sanitized.issuer) {
            champs["metadata.organisme_emetteur"] = issuer
            champs["organisme_emetteur"] = issuer
            champs["comite"] = issuer
        }
        if let summary = nonEmpty(sanitized.summary) {
            champs["summary.generated"] = summary
        }
        if !sanitized.keywords.isEmpty {
            champs["metadata.mots_cles"] = sanitized.keywords.joined(separator: ", ")
            champs["summary.highlights"] = sanitized.keywords.prefix(4).joined(separator: " | ")
        }

        let confidence = foundationModelConfidence(for: sanitized)

        return ProviderCandidate(
            provider: name,
            typeDoc: typeDoc,
            sujets: sanitized.keywords.isEmpty ? defaultSubjects(for: typeDoc) : Array(sanitized.keywords.prefix(2)),
            hasSignature: false,
            pages: max(1, estimatedPages(for: request.text)),
            champs: champs,
            confidence: confidence,
            suggestedPreset: preset,
            suggestedClassCode: classCode,
            matchedRules: ["apple_foundation_models_json_enrichment"],
            topNodes: [classCode ?? typeDoc, "AppleFoundationModels"],
            capture: nil,
            review: nil
        )
        #else
        logger.debug("AppleFoundationModels indisponible: framework absent.")
        return nil
        #endif
    }
}

private func localProviderEnabled(_ key: String, defaultEnabled: Bool = false) -> Bool {
    guard let raw = Environment.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else {
        return defaultEnabled
    }
    switch raw.lowercased() {
    case "1", "true", "yes", "on":
        return true
    case "0", "false", "no", "off":
        return false
    default:
        return defaultEnabled
    }
}

private func nonEmpty(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func analysisSourceText(for request: AnalysisRequest) -> String? {
    let base = [request.file_id, request.text ?? ""]
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !base.isEmpty else {
        return nil
    }
    let maxCharacters = max(
        1000,
        Int(Environment.get("ORCHIVISTE_ANALYSE_APPLE_TEXT_MAX_CHARS") ?? "12000") ?? 12000
    )
    return String(base.prefix(maxCharacters))
}

private func estimatedPages(for text: String?) -> Int {
    guard let text, !text.isEmpty else {
        return 1
    }
    let byFormFeed = text.components(separatedBy: "\u{0C}").count
    if byFormFeed > 1 {
        return max(1, min(500, byFormFeed))
    }
    return max(1, Int(ceil(Double(text.split(whereSeparator: \.isNewline).count) / 45.0)))
}

private func canonicalTypeDocument(from raw: String?) -> String {
    let normalized = raw?
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if normalized.contains("facture") || normalized.contains("invoice") {
        return "Facture"
    }
    if normalized.contains("resolution") || normalized.contains("résolution") {
        return "Resolution"
    }
    if normalized.contains("proces-verbal") || normalized.contains("procès-verbal") || normalized == "pv" {
        return "ProcesVerbal"
    }
    if normalized.contains("permis") {
        return "Permis"
    }
    return raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? (raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Autre")
        : "Autre"
}

private func classCode(for typeDoc: String) -> String? {
    switch typeDoc {
    case "Facture":
        return "FIN-001"
    case "Resolution":
        return "ADM-RES"
    case "ProcesVerbal":
        return "ADM-PV"
    case "Permis":
        return "URB-PER"
    default:
        return nil
    }
}

private func presetID(for typeDoc: String) -> String? {
    switch typeDoc {
    case "Facture":
        return "preset_facture"
    case "Resolution":
        return "preset_resolution"
    case "ProcesVerbal":
        return "preset_pv"
    default:
        return nil
    }
}

private func defaultSubjects(for typeDoc: String) -> [String] {
    switch typeDoc {
    case "Facture":
        return ["Finance", "Achat"]
    case "Resolution":
        return ["Decision", "Gouvernance"]
    case "ProcesVerbal":
        return ["Seance", "Comite"]
    case "Permis":
        return ["Urbanisme"]
    default:
        return ["General"]
    }
}

private func foundationModelConfidence(for enrichment: AppleFoundationModelEnrichment) -> Double {
    let values = [
        enrichment.typeDocument,
        enrichment.documentNumber,
        enrichment.object,
        enrichment.documentDate,
        enrichment.issuer,
        enrichment.summary
    ]
    let filled = values.compactMap(nonEmpty).count
    let keywordBoost = min(0.12, Double(enrichment.keywords.count) * 0.02)
    return min(0.92, max(0.45, 0.48 + (Double(filled) * 0.06) + keywordBoost))
}

private func sanitizeFoundationModelEnrichment(
    _ enrichment: AppleFoundationModelEnrichment,
    sourceText: String
) -> AppleFoundationModelEnrichment {
    let normalizedSource = sourceText
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()

    let typeDocument: String?
    let candidateType = canonicalTypeDocument(from: enrichment.typeDocument)
    if candidateType != "Autre",
       typeDocumentAppearsInSource(candidateType, normalizedSource: normalizedSource) {
        typeDocument = candidateType
    } else {
        typeDocument = nil
    }

    let documentNumber = looselyAppearsInSource(enrichment.documentNumber, normalizedSource: normalizedSource)
        ? nonEmpty(enrichment.documentNumber)
        : nil
    let documentDate = looselyAppearsInSource(enrichment.documentDate, normalizedSource: normalizedSource)
        ? nonEmpty(enrichment.documentDate)
        : nil
    let issuer = issuerAppearsInSource(enrichment.issuer, normalizedSource: normalizedSource)
        ? nonEmpty(enrichment.issuer)
        : nil
    let keywords = enrichment.keywords.filter { keywordAppearsInSource($0, normalizedSource: normalizedSource) }

    return AppleFoundationModelEnrichment(
        typeDocument: typeDocument,
        documentNumber: documentNumber,
        object: nonEmpty(enrichment.object),
        documentDate: documentDate,
        issuer: issuer,
        summary: nonEmpty(enrichment.summary),
        keywords: keywords
    )
}

private func typeDocumentAppearsInSource(_ typeDocument: String, normalizedSource: String) -> Bool {
    switch canonicalTypeDocument(from: typeDocument) {
    case "Resolution":
        return normalizedSource.contains("resolution")
    case "Facture":
        return normalizedSource.contains("facture") || normalizedSource.contains("invoice")
    case "ProcesVerbal":
        return normalizedSource.contains("proces-verbal") || normalizedSource.contains("proces verbal") || normalizedSource.contains("pv")
    case "Permis":
        return normalizedSource.contains("permis")
    default:
        return false
    }
}

private func looselyAppearsInSource(_ value: String?, normalizedSource: String) -> Bool {
    guard let value = nonEmpty(value) else {
        return false
    }
    let normalizedValue = value
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    if normalizedSource.contains(normalizedValue) {
        return true
    }
    let compactSource = normalizedSource.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
    let compactValue = normalizedValue.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
    guard compactValue.count >= 4 else {
        return false
    }
    return compactSource.contains(compactValue)
}

private func issuerAppearsInSource(_ issuer: String?, normalizedSource: String) -> Bool {
    guard let issuer = nonEmpty(issuer) else {
        return false
    }
    let tokens = issuer
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { $0.count >= 3 }
    guard !tokens.isEmpty else {
        return false
    }
    return tokens.allSatisfy { normalizedSource.contains($0) }
}

private func keywordAppearsInSource(_ keyword: String, normalizedSource: String) -> Bool {
    guard let keyword = nonEmpty(keyword) else {
        return false
    }
    let normalizedKeyword = keyword
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    if normalizedKeyword.count < 3 {
        return false
    }
    return normalizedSource.contains(normalizedKeyword)
}

private struct AppleFoundationModelEnrichment {
    let typeDocument: String?
    let documentNumber: String?
    let object: String?
    let documentDate: String?
    let issuer: String?
    let summary: String?
    let keywords: [String]
}

#if canImport(CoreML)
private actor AppleCoreMLRuntime {
    static let shared = AppleCoreMLRuntime()

    private var cache: [String: MLModel] = [:]

    func predict(
        modelPath: String,
        textFeatureName: String,
        labelFeatureName: String,
        probabilityFeatureName: String,
        text: String
    ) throws -> (label: String, confidence: Double, probabilities: [String: Double])? {
        let model = try loadModel(at: modelPath)
        let input = try MLDictionaryFeatureProvider(dictionary: [
            textFeatureName: MLFeatureValue(string: text)
        ])
        let output = try model.prediction(from: input)

        let rawLabel = output.featureValue(for: labelFeatureName)?.stringValue
        let probabilities = normalizedProbabilityDictionary(
            output.featureValue(for: probabilityFeatureName)?.dictionaryValue
        )

        let resolvedLabel = nonEmpty(rawLabel) ?? probabilities.max(by: { $0.value < $1.value })?.key
        guard let resolvedLabel else {
            return nil
        }
        let confidence = probabilities[resolvedLabel] ?? 0.6
        return (resolvedLabel, confidence, probabilities)
    }

    private func loadModel(at rawPath: String) throws -> MLModel {
        if let existing = cache[rawPath] {
            return existing
        }

        let sourceURL = URL(fileURLWithPath: rawPath)
        let configuration = MLModelConfiguration()
        let loadURL: URL
        if sourceURL.pathExtension == "mlmodelc" {
            loadURL = sourceURL
        } else {
            loadURL = try MLModel.compileModel(at: sourceURL)
        }

        let model = try MLModel(contentsOf: loadURL, configuration: configuration)
        cache[rawPath] = model
        return model
    }

    private func normalizedProbabilityDictionary(_ raw: [AnyHashable: Any]?) -> [String: Double] {
        guard let raw else {
            return [:]
        }
        var result: [String: Double] = [:]
        for (key, value) in raw {
            let label = String(describing: key)
            if let number = value as? NSNumber {
                result[label] = number.doubleValue
            } else if let double = value as? Double {
                result[label] = double
            } else if let float = value as? Float {
                result[label] = Double(float)
            }
        }
        return result
    }
}
#endif

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum AppleFoundationModelsRuntime {
    static func generate(
        fileID: String,
        text: String,
        logger: Logger
    ) async throws -> AppleFoundationModelEnrichment? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            logger.info("Apple Foundation Models indisponible sur cette machine.")
            return nil
        }

        let instructions = """
        Tu assistes un logiciel d'archivistique municipal sur macOS.
        Retourne uniquement un objet JSON compact.
        N'invente jamais une information absente.
        Si une information est incertaine ou absente, mets null.
        Respecte ces clés exactes:
        type_document, numero_document, objet, date_document, organisme_emetteur, resume, mots_cles.
        mots_cles doit etre un tableau de 1 a 6 chaines courtes.
        Le resume doit tenir sur 1 ou 2 phrases.
        N'inclus aucune mention technique dans le nom ou l'objet.
        """

        let prompt = """
        Fichier: \(fileID)
        Texte:
        \(text)
        """

        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(
                temperature: 0.2,
                maximumResponseTokens: 400
            )
        )

        guard let json = extractJSONObject(from: response.content),
              let payload = json.data(using: .utf8) else {
            logger.warning("Apple Foundation Models a retourne une reponse non JSON.")
            return nil
        }

        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        return AppleFoundationModelEnrichment(
            typeDocument: stringValue(object?["type_document"]),
            documentNumber: stringValue(object?["numero_document"]),
            object: stringValue(object?["objet"]),
            documentDate: stringValue(object?["date_document"]),
            issuer: stringValue(object?["organisme_emetteur"]),
            summary: stringValue(object?["resume"]),
            keywords: stringArrayValue(object?["mots_cles"])
        )
    }

    private static func extractJSONObject(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return trimmed
        }
        if let fenceStart = trimmed.range(of: "```json") ?? trimmed.range(of: "```"),
           let fenceEnd = trimmed.range(of: "```", options: .backwards),
           fenceStart.lowerBound != fenceEnd.lowerBound {
            let fenced = trimmed[fenceStart.upperBound..<fenceEnd.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fenced.hasPrefix("{"), fenced.hasSuffix("}") {
                return fenced
            }
        }
        guard let first = trimmed.firstIndex(of: "{"),
              let last = trimmed.lastIndex(of: "}") else {
            return nil
        }
        let candidate = trimmed[first...last]
        return String(candidate)
    }

    private static func stringValue(_ raw: Any?) -> String? {
        guard let raw else {
            return nil
        }
        if raw is NSNull {
            return nil
        }
        if let string = raw as? String {
            return nonEmpty(string)
        }
        return nonEmpty(String(describing: raw))
    }

    private static func stringArrayValue(_ raw: Any?) -> [String] {
        guard let values = raw as? [Any] else {
            return []
        }
        return values.compactMap { value in
            if value is NSNull {
                return nil
            }
            return nonEmpty(String(describing: value))
        }
    }
}
#endif
