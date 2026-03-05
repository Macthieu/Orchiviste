import Foundation
import OrchivisteAnalyseCore
import OrchivisteSharedKit
import Vapor

private struct UINamingContext: Encodable {
    let notice: String?
    let error: String?
    let legacy_default_name_format: String
    let runtime_fallback_active: Bool
    let ranking_preview_text: String
    let ranking_preview_file_name: String
    let ranking_preview_sample_count: String
    let ranking_preview_provider_status: String
    let ranking_preview_rows: [UINamingRuleRankingSummary]
    let ranking_preview_has_results: Bool
    let rules: [UINamingRuleSummary]
    let thesauri: [UINamingThesaurusSummary]
    let rule_drafts: [UINamingRuleDraftSummary]
    let thesaurus_drafts: [UINamingThesaurusDraftSummary]
    let selected_rule_id: String?
    let selected_rule_source: String
    let selected_rule_status: String
    let selected_rule_loaded_from: String
    let selected_rule_is_fallback: Bool
    let selected_rule_json: String
    let selected_rule_feedback_examples: [UINamingFeedbackExampleSummary]
    let selected_rule_feedback_present: Bool
    let selected_thesaurus_id: String?
    let selected_thesaurus_source: String
    let selected_thesaurus_status: String
    let selected_thesaurus_loaded_from: String
    let selected_thesaurus_is_fallback: Bool
    let selected_thesaurus_json: String
    let selected_thesaurus_draft_id: String?
    let draft_conflicts: [UIThesaurusConflictSummary]
    let draft_warnings: [String]
    let draft_has_conflicts: Bool
    let draft_has_warnings: Bool
}

private struct UINamingRuleRankingSummary: Encodable {
    let rule_id: String
    let label: String
    let document_family: String
    let final_score: String
    let deterministic_score: String
    let ml_score: String
    let sources: String
    let reasons: String
}

private struct UINamingFeedbackExampleSummary: Encodable {
    let created_at: String
    let source_filename: String
    let corrected_filename: String
    let notes: String
}

private struct UINamingRuleSummary: Encodable {
    let id: String
    let label: String
    let version: String
    let document_family: String
    let template: String
    let class_code: String
    let status: String
    let source: String
    let loaded_from: String
    let is_fallback: Bool
}

private struct UINamingThesaurusSummary: Encodable {
    let id: String
    let version: String
    let description: String
    let entries: Int
    let status: String
    let source: String
    let loaded_from: String
    let is_fallback: Bool
}

private struct UINamingRuleDraftSummary: Encodable {
    let draft_id: String
    let created_at: String
    let source_folder: String
    let confidence: String
    let needs_review: Bool
    let proposed_rule_id: String
}

private struct UINamingThesaurusDraftSummary: Encodable {
    let draft_id: String
    let created_at: String
    let source_name: String
    let format: String
    let strategy: String
    let target_thesaurus_id: String
    let conflicts: Int
}

private struct UIThesaurusConflictSummary: Encodable {
    let kind: String
    let alias: String
    let existing_canonical: String
    let incoming_canonical: String
    let message: String
}

private struct UINamingRuleJSONForm: Content {
    let rule_json: String
}

private struct UINamingRuleLearnForm: Content {
    let folder_path: String
    let sample_size: String?
    let extensions: String?
}

private struct UINamingThesaurusJSONForm: Content {
    let thesaurus_json: String
}

private struct UINamingThesaurusImportPreviewForm: Content {
    let target_thesaurus_id: String?
    let strategy: String?
    let format: String?
    let source_name: String?
    let raw_text: String
}

private struct UINamingThesaurusImportConfirmForm: Content {
    let target_thesaurus_id: String?
    let strategy: String?
}

private struct UINamingLegacyFormatForm: Content {
    let default_name_format: String?
}

func registerNamingUIRoutes(_ app: Application) {
    app.get("ui", "naming") { req async throws -> View in
        let runtimeCatalog = ConfigLoader.loadNamingRuntimeCatalog()
        let ruleRecords = runtimeCatalog.active_rules
        let rules = ruleRecords.map(\.definition)
        let thesaurusRecords = runtimeCatalog.active_thesauri
        let thesauri = thesaurusRecords.map(\.definition)
        let ruleDrafts = ConfigLoader.loadNamingRuleDrafts()
        let thesaurusDrafts = ConfigLoader.loadNamingThesaurusDrafts()

        let selectedRuleDraftID = req.query[String.self, at: "rule_draft_id"]
        let selectedRuleID = req.query[String.self, at: "rule_id"]
        let selectedThesaurusDraftID = req.query[String.self, at: "thesaurus_draft_id"]
        let selectedThesaurusID = req.query[String.self, at: "thesaurus_id"]

        let selectedRuleDraft = selectedRuleDraftID.flatMap { id in
            ruleDrafts.first(where: { $0.draft_id == id })
        }
        let rankingPreviewText = req.query[String.self, at: "ranking_text"] ?? ""
        let rankingPreviewFileName = req.query[String.self, at: "ranking_file_name"] ?? ""
        let rankingPreviewSampleCountRaw = req.query[String.self, at: "ranking_sample_count"] ?? "1"
        let rankingPreviewSampleCount = max(1, parseOptionalInt(rankingPreviewSampleCountRaw) ?? 1)
        let rankingRequest = namingNonEmpty(rankingPreviewText).map {
            NamingPredictionRequest(
                text: $0,
                metadata: NamingSourceMetadata(
                    fileName: namingNonEmpty(rankingPreviewFileName),
                    originalName: namingNonEmpty(rankingPreviewFileName)
                ),
                sample_count: rankingPreviewSampleCount,
                sample_file_names: namingNonEmpty(rankingPreviewFileName).map { [$0] } ?? []
            )
        }
        let rankingResults = rankingRequest.map { request in
            NamingRuleRanker().rank(request: request, candidates: ruleRecords)
        } ?? []
        let rankingRows = rankingResults.map {
            UINamingRuleRankingSummary(
                rule_id: $0.rule.rule_id,
                label: $0.rule.definition.label,
                document_family: $0.rule.definition.document_family,
                final_score: namingFormatScore($0.score),
                deterministic_score: namingFormatScore($0.deterministic_score),
                ml_score: namingFormatScore($0.ml_score),
                sources: $0.sources.isEmpty ? "-" : $0.sources.joined(separator: ", "),
                reasons: $0.reasons.isEmpty ? "-" : Array($0.reasons.prefix(4)).joined(separator: " | ")
            )
        }
        let rankingProviderStatus: String = {
            guard rankingRequest != nil else { return "Aucun test exécuté" }
            let hasCoreML = rankingResults.contains(where: { $0.ml_score > 0 || $0.sources.contains("coreml") })
            let hasSemantic = rankingResults.contains(where: { $0.sources.contains("embedding_similarity") })
            if hasCoreML && hasSemantic {
                return "Core ML + similarité sémantique + heuristique déterministe"
            }
            if hasCoreML {
                return "Core ML + heuristique déterministe"
            }
            if hasSemantic {
                return "Similarité sémantique + heuristique déterministe"
            }
            return "Heuristique déterministe seulement"
        }()
        let selectedRule = selectedRuleID.flatMap { id in
            rules.first(where: { $0.id == id })
        } ?? rules.first
        let selectedRuleRecord = selectedRule.flatMap { rule in
            runtimeCatalog.ruleRecord(id: rule.id, includeDrafts: false)
        }

        let selectedThesaurusDraft = selectedThesaurusDraftID.flatMap { id in
            thesaurusDrafts.first(where: { $0.draft_id == id })
        }
        let selectedThesaurus = selectedThesaurusID.flatMap { id in
            thesauri.first(where: { $0.thesaurus_id == id })
        } ?? thesauri.first
        let selectedThesaurusRecord = selectedThesaurus.flatMap { thesaurus in
            thesaurusRecords.first(where: { $0.thesaurus_id == thesaurus.thesaurus_id })
        }

        let effectiveRuleJSON = prettyJSONString(selectedRuleDraft?.proposed_rule ?? selectedRule)
        let effectiveThesaurusJSON = prettyJSONString(
            selectedThesaurusDraft?.preview.merged ?? selectedThesaurus
        )

        let context = UINamingContext(
            notice: req.query[String.self, at: "notice"],
            error: req.query[String.self, at: "error"],
            legacy_default_name_format: ConfigLoader.loadRoutingLocalSettings()?.default_name_format ?? "{class_code}-{type_doc}-{sujet}-{date}-{numero}",
            runtime_fallback_active: runtimeCatalog.fallback_active,
            ranking_preview_text: rankingPreviewText,
            ranking_preview_file_name: rankingPreviewFileName,
            ranking_preview_sample_count: String(rankingPreviewSampleCount),
            ranking_preview_provider_status: rankingProviderStatus,
            ranking_preview_rows: rankingRows,
            ranking_preview_has_results: !rankingRows.isEmpty,
            rules: ruleRecords.map {
                UINamingRuleSummary(
                    id: $0.definition.id,
                    label: $0.definition.label,
                    version: $0.version,
                    document_family: $0.definition.document_family,
                    template: $0.definition.template,
                    class_code: $0.definition.metadata?.suggested_class_code ?? "-",
                    status: $0.status.rawValue,
                    source: $0.source.rawValue,
                    loaded_from: $0.loaded_from ?? "-",
                    is_fallback: $0.is_fallback
                )
            },
            thesauri: thesaurusRecords.map {
                UINamingThesaurusSummary(
                    id: $0.definition.thesaurus_id,
                    version: $0.version,
                    description: $0.definition.description ?? "-",
                    entries: $0.definition.entries.count,
                    status: $0.status.rawValue,
                    source: $0.source.rawValue,
                    loaded_from: $0.loaded_from ?? "-",
                    is_fallback: $0.is_fallback
                )
            },
            rule_drafts: ruleDrafts.map {
                UINamingRuleDraftSummary(
                    draft_id: $0.draft_id,
                    created_at: namingFormatTimestamp($0.created_at),
                    source_folder: $0.source_folder,
                    confidence: String(format: "%.2f", $0.confidence),
                    needs_review: $0.needs_review,
                    proposed_rule_id: $0.proposed_rule.id
                )
            },
            thesaurus_drafts: thesaurusDrafts.map {
                UINamingThesaurusDraftSummary(
                    draft_id: $0.draft_id,
                    created_at: namingFormatTimestamp($0.created_at),
                    source_name: $0.source_name,
                    format: $0.format,
                    strategy: $0.preview.strategy.rawValue,
                    target_thesaurus_id: $0.preview.target_thesaurus_id,
                    conflicts: $0.preview.conflicts.count
                )
            },
            selected_rule_id: selectedRuleDraft?.proposed_rule.id ?? selectedRule?.id,
            selected_rule_source: selectedRuleDraft == nil ? (selectedRuleRecord?.source.rawValue ?? "configFile") : "draftFile",
            selected_rule_status: selectedRuleDraft == nil ? (selectedRuleRecord?.status.rawValue ?? "active") : NamingArtifactStatus.draft.rawValue,
            selected_rule_loaded_from: selectedRuleDraft == nil ? (selectedRuleRecord?.loaded_from ?? "-") : "configs/naming/drafts/rules",
            selected_rule_is_fallback: selectedRuleDraft == nil ? (selectedRuleRecord?.is_fallback ?? false) : false,
            selected_rule_json: effectiveRuleJSON,
            selected_rule_feedback_examples: (selectedRuleDraft?.proposed_rule.metadata?.feedback_examples
                ?? selectedRule?.metadata?.feedback_examples
                ?? []).suffix(10).map {
                    UINamingFeedbackExampleSummary(
                        created_at: namingFormatTimestamp($0.created_at),
                        source_filename: $0.source_filename,
                        corrected_filename: $0.corrected_filename,
                        notes: $0.notes ?? "-"
                    )
                },
            selected_rule_feedback_present: !((selectedRuleDraft?.proposed_rule.metadata?.feedback_examples
                ?? selectedRule?.metadata?.feedback_examples
                ?? []).isEmpty),
            selected_thesaurus_id: selectedThesaurusDraft?.preview.target_thesaurus_id ?? selectedThesaurus?.thesaurus_id,
            selected_thesaurus_source: selectedThesaurusDraft == nil ? (selectedThesaurusRecord?.source.rawValue ?? "configFile") : "draftFile",
            selected_thesaurus_status: selectedThesaurusDraft == nil ? (selectedThesaurusRecord?.status.rawValue ?? "active") : NamingArtifactStatus.draft.rawValue,
            selected_thesaurus_loaded_from: selectedThesaurusDraft == nil ? (selectedThesaurusRecord?.loaded_from ?? "-") : "configs/naming/drafts/thesaurus",
            selected_thesaurus_is_fallback: selectedThesaurusDraft == nil ? (selectedThesaurusRecord?.is_fallback ?? false) : false,
            selected_thesaurus_json: effectiveThesaurusJSON,
            selected_thesaurus_draft_id: selectedThesaurusDraft?.draft_id,
            draft_conflicts: (selectedThesaurusDraft?.preview.conflicts ?? []).map {
                UIThesaurusConflictSummary(
                    kind: $0.kind.rawValue,
                    alias: $0.alias ?? "-",
                    existing_canonical: $0.existing_canonical ?? "-",
                    incoming_canonical: $0.incoming_canonical ?? "-",
                    message: $0.message
                )
            },
            draft_warnings: selectedThesaurusDraft?.preview.warnings ?? [],
            draft_has_conflicts: !(selectedThesaurusDraft?.preview.conflicts ?? []).isEmpty,
            draft_has_warnings: !(selectedThesaurusDraft?.preview.warnings ?? []).isEmpty
        )

        return try await req.view.render("naming", context)
    }

    app.on(.POST, "ui", "naming", "legacy-format", body: .collect(maxSize: "512kb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UINamingLegacyFormatForm.self)
            let existing = ConfigLoader.loadRoutingLocalSettings()
            let updated = RoutingLocalSettings(
                local_route_root: existing?.local_route_root,
                default_destination_template: existing?.default_destination_template,
                default_name_format: namingNonEmpty(form.default_name_format)
            )
            try ConfigLoader.saveRoutingLocalSettings(updated)
            return req.redirect(to: "/ui/naming?notice=\(namingQuery("Format de secours hérité mis à jour."))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/naming?error=\(namingQuery(abort.reason))")
        } catch {
            req.logger.error("Échec mise à jour format hérité UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant l'enregistrement du format hérité."))")
        }
    }

    app.on(.POST, "ui", "naming", "rules", "save", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UINamingRuleJSONForm.self)
            let data = Data(form.rule_json.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            let rule = try JSONDecoder().decode(NamingRuleDefinition.self, from: data)
            let issues = validateNamingRuleDefinition(rule)
            if issues.contains(where: { $0.level == .error }) {
                throw Abort(.badRequest, reason: issues.map(\.message).joined(separator: " | "))
            }
            try ConfigLoader.saveNamingRule(rule)
            return req.redirect(to: "/ui/naming?notice=\(namingQuery("Règle de nommage enregistrée."))&rule_id=\(namingQuery(rule.id))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/naming?error=\(namingQuery(abort.reason))")
        } catch {
            req.logger.error("Échec sauvegarde règle de nommage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant l'enregistrement de la règle."))")
        }
    }

    app.on(.POST, "ui", "naming", "rules", "learn", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UINamingRuleLearnForm.self)
            guard let folderPath = namingNonEmpty(form.folder_path) else {
                throw Abort(.badRequest, reason: "Le dossier source est requis.")
            }
            let request = RuleLearningRequest(
                folder_path: folderPath,
                sample_size: parseOptionalInt(form.sample_size),
                extensions: namingParseCSV(form.extensions)
            )
            let samples = try collectNamingLearningSamples(request: request, logger: req.logger)
            let learner = RuleLearner()
            let catalog = ConfigLoader.loadNamingRuntimeCatalog()
            let draft = learner.learn(
                request: request,
                samples: samples,
                catalog: catalog,
                baseThesaurus: catalog.primaryThesaurus()
            )
            try ConfigLoader.saveNamingRuleDraft(draft)
            return req.redirect(
                to: "/ui/naming?notice=\(namingQuery("Brouillon de règle appris."))&rule_draft_id=\(namingQuery(draft.draft_id))"
            )
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/naming?error=\(namingQuery(abort.reason))")
        } catch {
            req.logger.error("Échec apprentissage règle de nommage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant l'apprentissage."))")
        }
    }

    app.post("ui", "naming", "rule-drafts", ":id", "apply") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let draft = ConfigLoader.loadNamingRuleDrafts().first(where: { $0.draft_id == id }) else {
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Brouillon de règle introuvable."))")
        }
        do {
            try ConfigLoader.saveNamingRule(draft.proposed_rule)
            let draftPath = ConfigLoader.namingRuleDraftsDirectory()
                .appendingPathComponent("\(id).json")
            try? FileManager.default.removeItem(at: draftPath)

            return req.redirect(to: "/ui/naming?notice=\(namingQuery("Brouillon appliqué comme règle active."))&rule_id=\(namingQuery(draft.proposed_rule.id))")
        } catch {
            req.logger.error("Échec application brouillon de règle.", metadata: [
                "draft_id": .string(id),
                "rule_id": .string(draft.proposed_rule.id),
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant l'application du brouillon."))")
        }
    }

    app.on(.POST, "ui", "naming", "thesaurus", "save", body: .collect(maxSize: "3mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UINamingThesaurusJSONForm.self)
            let data = Data(form.thesaurus_json.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            let thesaurus = try JSONDecoder().decode(NamingThesaurus.self, from: data)
            try ConfigLoader.saveNamingThesaurus(thesaurus)
            return req.redirect(to: "/ui/naming?notice=\(namingQuery("Thésaurus enregistré."))&thesaurus_id=\(namingQuery(thesaurus.thesaurus_id))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/naming?error=\(namingQuery(abort.reason))")
        } catch {
            req.logger.error("Échec sauvegarde thésaurus UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant l'enregistrement du thésaurus."))")
        }
    }

    app.on(.POST, "ui", "naming", "thesaurus", "import-preview", body: .collect(maxSize: "3mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UINamingThesaurusImportPreviewForm.self)
            let rawText = form.raw_text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else {
                throw Abort(.badRequest, reason: "Le contenu du thésaurus à importer est requis.")
            }
            let strategy = NamingImportStrategy(rawValue: namingNonEmpty(form.strategy) ?? "") ?? .draft
            let request = ThesaurusImportPreviewRequest(
                target_thesaurus_id: namingNonEmpty(form.target_thesaurus_id),
                strategy: strategy,
                format: namingNonEmpty(form.format),
                raw_text: rawText,
                source_name: namingNonEmpty(form.source_name)
            )
            let service = ThesaurusImportService()
            let existing = request.target_thesaurus_id.flatMap(ConfigLoader.loadNamingThesaurus(id:))
                ?? ConfigLoader.loadNamingThesauri().first
            let draft = try service.preview(request: request, existing: existing)
            try ConfigLoader.saveNamingThesaurusDraft(draft)
            return req.redirect(
                to: "/ui/naming?notice=\(namingQuery("Prévisualisation d'import générée."))&thesaurus_draft_id=\(namingQuery(draft.draft_id))"
            )
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/naming?error=\(namingQuery(abort.reason))")
        } catch {
            req.logger.error("Échec preview import thésaurus UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant la prévisualisation d'import."))")
        }
    }

    app.on(.POST, "ui", "naming", "thesaurus-drafts", ":id", "confirm", body: .collect(maxSize: "512kb")) { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let draft = ConfigLoader.loadNamingThesaurusDraft(id: id) else {
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Brouillon d'import introuvable."))")
        }

        do {
            let form = try req.content.decode(UINamingThesaurusImportConfirmForm.self)
            let strategy = NamingImportStrategy(rawValue: namingNonEmpty(form.strategy) ?? "") ?? draft.preview.strategy
            let targetID = namingNonEmpty(form.target_thesaurus_id) ?? draft.preview.target_thesaurus_id
            let preview = ThesaurusMergeService().previewMerge(
                target: ConfigLoader.loadNamingThesaurus(id: targetID),
                imported: draft.imported,
                strategy: strategy
            )
            try ConfigLoader.saveNamingThesaurus(preview.merged)
            return req.redirect(to: "/ui/naming?notice=\(namingQuery("Import de thésaurus confirmé."))&thesaurus_id=\(namingQuery(preview.merged.thesaurus_id))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/naming?error=\(namingQuery(abort.reason))")
        } catch {
            req.logger.error("Échec confirmation import thésaurus UI.", metadata: [
                "draft_id": .string(id),
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/naming?error=\(namingQuery("Erreur interne pendant la confirmation de l'import."))")
        }
    }
}

private func namingFormatTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func prettyJSONString<T: Encodable>(_ value: T?) -> String {
    guard let value else { return "" }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return ""
    }
    return string
}

private func namingQuery(_ value: String) -> String {
    let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private func namingNonEmpty(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func namingParseCSV(_ raw: String?) -> [String]? {
    let items = (raw ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return items.isEmpty ? nil : items
}

private func parseOptionalInt(_ raw: String?) -> Int? {
    guard let raw = namingNonEmpty(raw) else { return nil }
    return Int(raw)
}

private func namingFormatScore(_ value: Double) -> String {
    String(format: "%.3f", value)
}
