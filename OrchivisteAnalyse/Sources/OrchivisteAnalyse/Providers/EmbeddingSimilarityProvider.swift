import Foundation
import Vapor

struct EmbeddingSimilarityProvider: AnalysisProvider {
    let name = "EmbeddingSimilarity"
    let weight: Double = 0.72

    func analyze(request: AnalysisRequest, logger: Logger) async throws -> ProviderCandidate? {
        guard analysisProviderEnabled("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_ENABLED") else {
            return nil
        }
        guard let indexPath = analysisTrimmed(Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_INDEX_PATH")) else {
            logger.debug("EmbeddingSimilarity inactif: index absent.")
            return nil
        }
        guard let sourceText = analysisRequestSourceText(for: request) else {
            return nil
        }

        let topK = max(1, Int(Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_TOP_K") ?? "5") ?? 5)
        let minScore = max(0, Double(Environment.get("ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_MIN_SCORE") ?? "0.18") ?? 0.18)
        let matches = try await EmbeddingReferenceRuntime.shared.search(
            indexPath: indexPath,
            text: sourceText,
            topK: topK
        )
        guard let best = matches.first, best.score >= minScore else {
            return nil
        }

        let typeDoc = analysisCanonicalTypeDocument(
            from: analysisTrimmed(best.record.metadata_type_document)
                ?? analysisTrimmed(best.record.label)
                ?? analysisTrimmed(best.record.reference_id)
        )
        let classCode = analysisTrimmed(best.record.class_code)
            ?? (best.record.reference_kind == "class_code" ? analysisTrimmed(best.record.reference_id) : nil)
            ?? analysisClassCode(for: typeDoc)
        let preset = analysisTrimmed(best.record.preset_id) ?? analysisPresetID(for: typeDoc)
        let subjects = analysisDefaultSubjects(for: typeDoc)
        let topMatchesSummary = matches.prefix(3).map {
            "\($0.record.reference_id):\(String(format: "%.3f", $0.score))"
        }.joined(separator: " | ")

        let confidence = min(0.9, max(0.35, best.score))
        let champs: [String: String] = [
            "embedding.top_match_id": best.record.reference_id,
            "embedding.top_match_label": analysisTrimmed(best.record.label) ?? best.record.reference_id,
            "embedding.top_match_score": String(format: "%.4f", best.score),
            "embedding.top_matches": topMatchesSummary,
            "embedding.match_kind": best.record.reference_kind,
            "doc_type_hint": typeDoc,
            "metadata.type_document": typeDoc
        ]

        return ProviderCandidate(
            provider: name,
            typeDoc: typeDoc,
            sujets: subjects,
            hasSignature: false,
            pages: max(1, analysisEstimatedPages(for: request.text)),
            champs: champs,
            confidence: confidence,
            suggestedPreset: preset,
            suggestedClassCode: classCode,
            matchedRules: ["embedding_similarity_local_index"],
            topNodes: [classCode ?? best.record.reference_id],
            capture: nil,
            review: nil
        )
    }
}

private struct EmbeddingReferenceRecord: Decodable, Sendable {
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

private struct ScoredEmbeddingReference: Sendable {
    let record: EmbeddingReferenceRecord
    let score: Double
}

private actor EmbeddingReferenceRuntime {
    static let shared = EmbeddingReferenceRuntime()

    private var cache: [String: [EmbeddingReferenceRecord]] = [:]

    func search(
        indexPath: String,
        text: String,
        topK: Int
    ) throws -> [ScoredEmbeddingReference] {
        let references = try loadReferences(indexPath: indexPath)
        return references
            .map { record in
                ScoredEmbeddingReference(
                    record: record,
                    score: analysisTokenSimilarity(lhs: text, rhs: record.text)
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.record.reference_id < rhs.record.reference_id
            }
            .prefix(max(1, topK))
            .map { $0 }
    }

    private func loadReferences(indexPath: String) throws -> [EmbeddingReferenceRecord] {
        if let cached = cache[indexPath] {
            return cached
        }

        let url = URL(fileURLWithPath: indexPath)
        let data = try Data(contentsOf: url)
        let references: [EmbeddingReferenceRecord]

        if url.pathExtension.lowercased() == "jsonl" {
            let lines = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            references = lines.compactMap { line in
                try? JSONDecoder().decode(EmbeddingReferenceRecord.self, from: Data(line.utf8))
            }
        } else {
            references = try JSONDecoder().decode([EmbeddingReferenceRecord].self, from: data)
        }

        cache[indexPath] = references
        return references
    }
}
