import Foundation
import OrchivisteSharedKit

public struct RuleLearner: RuleLearning {
    private let engine: DeclarativeNamingRuleEngine
    private let ranker: NamingRuleRanker

    public init(
        engine: DeclarativeNamingRuleEngine = .init(),
        ranker: NamingRuleRanker = .init()
    ) {
        self.engine = engine
        self.ranker = ranker
    }

    public func learn(
        request: RuleLearningRequest,
        samples: [LearningDocumentSample],
        baseThesaurus: NamingThesaurus
    ) -> NamingRuleDraft {
        learn(
            request: request,
            samples: samples,
            catalog: .fallback(thesaurus: baseThesaurus),
            baseThesaurus: baseThesaurus
        )
    }

    public func learn(
        request: RuleLearningRequest,
        samples: [LearningDocumentSample],
        catalog: NamingRuntimeCatalog,
        baseThesaurus: NamingThesaurus? = nil
    ) -> NamingRuleDraft {
        let sampleLimit = max(1, min(request.sample_size ?? samples.count, samples.count))
        let effectiveSamples = Array(samples.prefix(sampleLimit))
        let effectiveCatalog = resolvedCatalog(from: catalog, baseThesaurus: baseThesaurus)
        let selectedThesaurus = baseThesaurus
            ?? effectiveCatalog.primaryThesaurus()
            ?? NamingFoundationSeeds.bootstrapFallbackThesaurus()
        let rankingRequest = makeRankingRequest(samples: effectiveSamples)
        let ranked = ranker.rank(request: rankingRequest, candidates: effectiveCatalog.active_rules)
        let bestCandidate = ranked.first
        let selectedConfidence = max(0.2, bestCandidate?.score ?? 0.2)
        let selectedRule = selectRuleProposal(bestCandidate: bestCandidate, samples: effectiveSamples)
        let suggestedSynonyms = suggestSynonyms(for: selectedRule, samples: effectiveSamples)

        let detectedTokens = topTokens(in: effectiveSamples)
        let examples = buildExamples(rule: selectedRule, samples: effectiveSamples, thesaurus: selectedThesaurus)
        let warnings = buildWarnings(
            confidence: selectedConfidence,
            examples: examples,
            ranked: ranked,
            catalog: effectiveCatalog
        )
        let thesaurusDraft = buildThesaurusDraft(
            base: selectedThesaurus,
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
                inferred_transformations: inferredTransformations(for: selectedRule, ranked: ranked),
                suggested_stopwords: Array(selectedThesaurus.stopwords.prefix(16)),
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

    private func buildWarnings(
        confidence: Double,
        examples: [[String: String]],
        ranked: [RankedNamingRule],
        catalog: NamingRuntimeCatalog
    ) -> [String] {
        var warnings: [String] = []
        if confidence < 0.8 {
            warnings.append("needs_review_low_confidence")
        }
        if examples.contains(where: { ($0["after"] ?? "").isEmpty }) {
            warnings.append("missing_examples_after")
        }
        if ranked.isEmpty {
            warnings.append("no_active_rule_match")
        }
        if catalog.fallback_active {
            warnings.append("fallback_catalog_in_use")
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

    private func inferredTransformations(for rule: NamingRuleDefinition, ranked: [RankedNamingRule]) -> [String] {
        let scoringNote = ranked.first.map { first in
            "Règle priorisée via \(first.sources.joined(separator: "+")) avec un score de \(String(format: "%.2f", first.score))."
        }
        switch rule.document_family {
        case "resolution_conseil":
            return [
                scoringNote,
                "Uniformiser le préfixe vers Résolution NO",
                "Supprimer la mention Ville d'Amos du nom final",
                "Normaliser la date au format AAAA-MM-JJ"
            ].compactMap { $0 }
        case "entente_uniformisee":
            return [
                scoringNote,
                "Uniformiser contrat, convention, bail et protocole vers Entente",
                "Nettoyer les mots-outils dans l'objet",
                "Inférer une période compacte AAAA ou AAAA-AAAA"
            ].compactMap { $0 }
        default:
            return [scoringNote, "Nettoyer les mentions techniques", "Normaliser la typographie française"].compactMap { $0 }
        }
    }

    private func resolvedCatalog(
        from catalog: NamingRuntimeCatalog,
        baseThesaurus: NamingThesaurus?
    ) -> NamingRuntimeCatalog {
        if !catalog.active_rules.isEmpty && !catalog.active_thesauri.isEmpty {
            return catalog
        }
        return .fallback(thesaurus: baseThesaurus ?? NamingFoundationSeeds.bootstrapFallbackThesaurus())
    }

    private func makeRankingRequest(samples: [LearningDocumentSample]) -> NamingPredictionRequest {
        let text = samples
            .map { "\($0.file_name)\n\($0.text)" }
            .joined(separator: "\n\n")
        return NamingPredictionRequest(
            text: text,
            metadata: NamingSourceMetadata(
                fileName: samples.first?.file_name,
                fileExtension: samples.first?.file_extension,
                originalName: samples.first?.file_name,
                hints: samples.first?.metadata
            ),
            sample_count: samples.count,
            sample_file_names: samples.map(\.file_name)
        )
    }

    private func selectRuleProposal(
        bestCandidate: RankedNamingRule?,
        samples: [LearningDocumentSample]
    ) -> NamingRuleDefinition {
        guard let bestCandidate else {
            return buildMinimalDraftRule(from: samples)
        }
        if bestCandidate.score >= 0.80 {
            return bestCandidate.rule.definition
        }
        if bestCandidate.score >= 0.40 {
            return deriveRule(from: bestCandidate.rule.definition, samples: samples, score: bestCandidate.score)
        }
        return buildMinimalDraftRule(from: samples)
    }

    private func deriveRule(
        from base: NamingRuleDefinition,
        samples: [LearningDocumentSample],
        score: Double
    ) -> NamingRuleDefinition {
        let suggestedSignals = Array(topTokens(in: samples).prefix(6))
        let mergedSignals = Array(Set((base.conditions.signals_any ?? []) + suggestedSignals)).sorted()
        let metadata = NamingRuleMetadata(
            suggested_class_code: base.metadata?.suggested_class_code,
            canonical_output_label: base.metadata?.canonical_output_label,
            rendering: base.metadata?.rendering,
            feedback_examples: base.metadata?.feedback_examples,
            notes: (base.metadata?.notes ?? []) + ["Brouillon dérivé automatiquement (score \(String(format: "%.2f", score)))."]
        )
        return NamingRuleDefinition(
            id: "draft-\(base.id)-\(timestampLabel())",
            label: "\(base.label) (brouillon)",
            version: "draft-1",
            document_family: base.document_family,
            template: base.template,
            conditions: NamingRuleCondition(
                signals_any: mergedSignals,
                regex_any: base.conditions.regex_any,
                source_document_families: base.conditions.source_document_families
            ),
            fields: base.fields,
            normalization: base.normalization,
            forbidden_terms: base.forbidden_terms,
            validations: base.validations,
            metadata: metadata
        )
    }

    private func buildMinimalDraftRule(from samples: [LearningDocumentSample]) -> NamingRuleDefinition {
        let tokens = Array(topTokens(in: samples).prefix(5))
        let typeHint = inferDocumentFamily(from: samples)
        return NamingRuleDefinition(
            id: "draft-generic-\(timestampLabel())",
            label: "Règle générique proposée",
            version: "draft-1",
            document_family: typeHint,
            template: "{original}.pdf",
            conditions: NamingRuleCondition(
                signals_any: tokens,
                regex_any: nil,
                source_document_families: typeHint == "generic_document" ? nil : [typeHint]
            ),
            fields: [
                NamingFieldDefinition(
                    key: "original",
                    label: "Nom original",
                    required: true,
                    strategies: [NamingFieldStrategy(kind: "semantic", semantic_hint: "original_filename")]
                )
            ],
            normalization: ["trim", "collapse_spaces", "separator_en_dash", "strip_technical_mentions"],
            forbidden_terms: ["signé", "non signé", "OCR", "numérisé", "scanné", "version finale", "PDF/A"],
            validations: [NamingValidationRule(kind: "max_length", parameter: "255")],
            metadata: NamingRuleMetadata(
                notes: ["Brouillon minimal généré faute de règle active suffisamment proche."]
            )
        )
    }

    private func inferDocumentFamily(from samples: [LearningDocumentSample]) -> String {
        let haystack = normalizedSearchText(samples.map { $0.file_name + " " + $0.text }.joined(separator: " "))
        if haystack.contains("resolution") || haystack.contains("proces verbal") {
            return "resolution_conseil"
        }
        if haystack.contains("entente") || haystack.contains("contrat") || haystack.contains("convention") || haystack.contains("bail") {
            return "entente_uniformisee"
        }
        return "generic_document"
    }

    private func suggestSynonyms(
        for rule: NamingRuleDefinition,
        samples: [LearningDocumentSample]
    ) -> [String: [String]] {
        switch rule.document_family {
        case "resolution_conseil":
            return ["resolution": ["résolution", "resolution", "extrait du procès-verbal"]]
        case "entente_uniformisee":
            return ["entente": ["contrat", "convention", "bail", "protocole", "avenant"]]
        default:
            let tokens = Array(topTokens(in: samples).prefix(5))
            return tokens.isEmpty ? [:] : ["document": tokens]
        }
    }
}
