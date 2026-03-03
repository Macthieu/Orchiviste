import Foundation
import OrchivisteSharedKit

public struct RuleLearner: RuleLearning {
    private let engine: DeclarativeNamingRuleEngine

    public init(engine: DeclarativeNamingRuleEngine = .init()) {
        self.engine = engine
    }

    public func learn(
        request: RuleLearningRequest,
        samples: [LearningDocumentSample],
        baseThesaurus: NamingThesaurus
    ) -> NamingRuleDraft {
        let sampleLimit = max(1, min(request.sample_size ?? samples.count, samples.count))
        let effectiveSamples = Array(samples.prefix(sampleLimit))

        let resolutionHits = effectiveSamples.filter { sample in
            let text = normalizedSearchText(sample.text + "\n" + sample.file_name)
            return text.contains("resolution") || text.contains("proces verbal")
        }
        let ententeHits = effectiveSamples.filter { sample in
            let text = normalizedSearchText(sample.text + "\n" + sample.file_name)
            return text.contains("entente") || text.contains("contrat") || text.contains("convention") || text.contains("bail")
        }

        let selectedRule: NamingRuleDefinition
        let selectedConfidence: Double
        let suggestedSynonyms: [String: [String]]
        if resolutionHits.count >= ententeHits.count {
            selectedRule = NamingFoundationSeeds.resolutionRule()
            selectedConfidence = effectiveSamples.isEmpty ? 0.2 : Double(resolutionHits.count) / Double(effectiveSamples.count)
            suggestedSynonyms = ["resolution": ["résolution", "resolution", "extrait du procès-verbal"]]
        } else {
            selectedRule = NamingFoundationSeeds.ententeRule()
            selectedConfidence = effectiveSamples.isEmpty ? 0.2 : Double(ententeHits.count) / Double(effectiveSamples.count)
            suggestedSynonyms = ["entente": ["contrat", "convention", "bail", "protocole", "avenant"]]
        }

        let detectedTokens = topTokens(in: effectiveSamples)
        let examples = buildExamples(rule: selectedRule, samples: effectiveSamples, thesaurus: baseThesaurus)
        let warnings = buildWarnings(confidence: selectedConfidence, examples: examples)
        let thesaurusDraft = buildThesaurusDraft(
            base: baseThesaurus,
            selectedRule: selectedRule,
            suggestedSynonyms: suggestedSynonyms,
            request: request
        )

        return NamingRuleDraft(
            draft_id: "draft-rule-\(timestampLabel())",
            created_at: Date(),
            source_folder: request.folder_path,
            needs_review: selectedConfidence < 0.8 || !warnings.isEmpty,
            confidence: min(0.95, max(0.25, selectedConfidence)),
            proposed_rule: selectedRule,
            proposed_thesaurus: thesaurusDraft,
            report: RuleLearningReport(
                scanned_files: samples.count,
                sampled_files: effectiveSamples.count,
                detected_tokens: Array(detectedTokens.prefix(20)),
                suggested_synonyms: suggestedSynonyms,
                inferred_transformations: inferredTransformations(for: selectedRule),
                suggested_stopwords: Array(baseThesaurus.stopwords.prefix(16)),
                examples_before_after: examples,
                warnings: warnings
            )
        )
    }

    private func buildExamples(
        rule: NamingRuleDefinition,
        samples: [LearningDocumentSample],
        thesaurus: NamingThesaurus
    ) -> [[String: String]] {
        samples.prefix(10).map { sample in
            let fields = engine.extractFields(
                from: sample.text,
                rule: rule,
                metadata: NamingSourceMetadata(
                    fileName: sample.file_name,
                    fileExtension: sample.file_extension,
                    originalName: sample.file_name,
                    hints: sample.metadata
                )
            )
            let normalized = engine.normalizeFields(fields, rule: rule, thesaurus: thesaurus)
            let rendered = engine.renderFilename(rule: rule, fields: normalized)
            return [
                "before": sample.file_name,
                "after": rendered
            ]
        }
    }

    private func buildWarnings(confidence: Double, examples: [[String: String]]) -> [String] {
        var warnings: [String] = []
        if confidence < 0.8 {
            warnings.append("needs_review_low_confidence")
        }
        if examples.contains(where: { ($0["after"] ?? "").isEmpty }) {
            warnings.append("missing_examples_after")
        }
        return warnings
    }

    private func buildThesaurusDraft(
        base: NamingThesaurus,
        selectedRule: NamingRuleDefinition,
        suggestedSynonyms: [String: [String]],
        request: RuleLearningRequest
    ) -> NamingThesaurus {
        var entries = base.entries
        for (canonical, aliases) in suggestedSynonyms {
            if !entries.contains(where: { normalizedSearchText($0.canonical) == normalizedSearchText(canonical) }) {
                entries.append(
                    NamingThesaurusEntry(
                        canonical: canonical.capitalized,
                        aliases: aliases,
                        kind: "learned_family",
                        normalized_output: canonical.capitalized,
                        notes: ["Proposé automatiquement depuis \(request.folder_path)."]
                    )
                )
            }
        }

        return NamingThesaurus(
            thesaurus_id: "draft-thesaurus-\(selectedRule.document_family)",
            version: "draft-1",
            description: "Brouillon de thésaurus généré depuis un dossier.",
            trace: NamingThesaurusTrace(
                source: request.folder_path,
                imported_at: Date(),
                imported_version: "draft-1"
            ),
            entries: entries,
            stopwords: base.stopwords,
            preserve_terms: base.preserve_terms
        )
    }

    private func topTokens(in samples: [LearningDocumentSample]) -> [String] {
        var counts: [String: Int] = [:]
        for sample in samples {
            let haystack = normalizedSearchText(sample.file_name + " " + sample.text)
            for token in haystack.split(separator: " ").map(String.init) where token.count >= 4 {
                counts[token, default: 0] += 1
            }
        }
        return counts.sorted {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        }.map(\.key)
    }

    private func inferredTransformations(for rule: NamingRuleDefinition) -> [String] {
        switch rule.document_family {
        case "resolution_conseil":
            return [
                "Uniformiser le préfixe vers Résolution NO",
                "Supprimer la mention Ville d'Amos du nom final",
                "Normaliser la date au format AAAA-MM-JJ"
            ]
        case "entente_uniformisee":
            return [
                "Uniformiser contrat, convention, bail et protocole vers Entente",
                "Nettoyer les mots-outils dans l'objet",
                "Inférer une période compacte AAAA ou AAAA-AAAA"
            ]
        default:
            return ["Nettoyer les mentions techniques", "Normaliser la typographie française"]
        }
    }
}
