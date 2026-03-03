import Foundation
import OrchivisteAnalyseCore
import OrchivisteSharedKit
import Vapor

func registerNamingRoutes(_ app: Application) {
    app.group("v1", "naming") { naming in
        naming.get("rules") { _ async throws -> [NamingRuleDefinition] in
            ConfigLoader.loadNamingRules()
        }

        naming.get("rules", ":id") { req async throws -> NamingRuleDefinition in
            guard let id = req.parameters.get("id"),
                  let rule = ConfigLoader.loadNamingRule(id: id) else {
                throw Abort(.notFound, reason: "Règle de nommage introuvable.")
            }
            return rule
        }

        naming.post("rules") { req async throws -> NamingRuleDefinition in
            let rule = try req.content.decode(NamingRuleDefinition.self)
            let issues = validateNamingRuleDefinition(rule)
            if issues.contains(where: { $0.level == .error }) {
                throw Abort(.badRequest, reason: issues.map(\.message).joined(separator: " | "))
            }
            try ConfigLoader.saveNamingRule(rule)
            return rule
        }

        naming.post("rules", "validate") { req async throws -> NamingRuleValidationResult in
            let request = try req.content.decode(NamingRuleValidationRequest.self)
            let engine = DeclarativeNamingRuleEngine()
            return engine.validate(request)
        }

        naming.post("rules", "learn") { req async throws -> NamingRuleDraft in
            let request = try req.content.decode(RuleLearningRequest.self)
            let samples = try collectLearningSamples(request: request, logger: req.logger)
            let learner = RuleLearner()
            let draft = learner.learn(
                request: request,
                samples: samples,
                baseThesaurus: ConfigLoader.loadNamingThesauri().first ?? NamingFoundationSeeds.defaultThesaurus()
            )
            try ConfigLoader.saveNamingRuleDraft(draft)
            return draft
        }

        naming.post("folder", "learn") { req async throws -> NamingRuleDraft in
            let request = try req.content.decode(RuleLearningRequest.self)
            let samples = try collectLearningSamples(request: request, logger: req.logger)
            let learner = RuleLearner()
            let draft = learner.learn(
                request: request,
                samples: samples,
                baseThesaurus: ConfigLoader.loadNamingThesauri().first ?? NamingFoundationSeeds.defaultThesaurus()
            )
            try ConfigLoader.saveNamingRuleDraft(draft)
            return draft
        }

        naming.get("drafts") { _ async throws -> NamingDraftIndex in
            NamingDraftIndex(
                rule_drafts: ConfigLoader.loadNamingRuleDrafts(),
                thesaurus_drafts: ConfigLoader.loadNamingThesaurusDrafts()
            )
        }

        naming.get("thesaurus") { _ async throws -> [NamingThesaurus] in
            ConfigLoader.loadNamingThesauri()
        }

        naming.get("thesaurus", ":id") { req async throws -> NamingThesaurus in
            guard let id = req.parameters.get("id"),
                  let thesaurus = ConfigLoader.loadNamingThesaurus(id: id) else {
                throw Abort(.notFound, reason: "Thésaurus introuvable.")
            }
            return thesaurus
        }

        naming.post("thesaurus") { req async throws -> NamingThesaurus in
            let thesaurus = try req.content.decode(NamingThesaurus.self)
            try ConfigLoader.saveNamingThesaurus(thesaurus)
            return thesaurus
        }

        naming.post("thesaurus", "import", "preview") { req async throws -> ImportedThesaurusDraft in
            let request = try req.content.decode(ThesaurusImportPreviewRequest.self)
            let service = ThesaurusImportService()
            let existing = request.target_thesaurus_id.flatMap(ConfigLoader.loadNamingThesaurus(id:))
                ?? ConfigLoader.loadNamingThesauri().first
            let draft = try service.preview(request: request, existing: existing)
            try ConfigLoader.saveNamingThesaurusDraft(draft)
            return draft
        }

        naming.post("thesaurus", "import", "confirm") { req async throws -> NamingThesaurus in
            let request = try req.content.decode(ThesaurusImportConfirmRequest.self)
            guard let draft = ConfigLoader.loadNamingThesaurusDraft(id: request.draft_id) else {
                throw Abort(.notFound, reason: "Brouillon d'import introuvable.")
            }

            let mergeService = ThesaurusMergeService()
            let strategy = request.strategy ?? draft.preview.strategy
            let targetID = request.target_thesaurus_id ?? draft.preview.target_thesaurus_id
            let existing = ConfigLoader.loadNamingThesaurus(id: targetID)
            let preview = mergeService.previewMerge(target: existing, imported: draft.imported, strategy: strategy)
            try ConfigLoader.saveNamingThesaurus(preview.merged)
            return preview.merged
        }
    }
}

private func validateNamingRuleDefinition(_ rule: NamingRuleDefinition) -> [NamingRuleValidationIssue] {
    var issues: [NamingRuleValidationIssue] = []

    if rule.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(level: .error, code: "missing_id", message: "L'identifiant de la règle est requis."))
    }
    if rule.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(level: .error, code: "missing_label", message: "Le libellé de la règle est requis."))
    }
    if rule.template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(level: .error, code: "missing_template", message: "Le template de nommage est requis."))
    }

    let sampleFields = Dictionary(uniqueKeysWithValues: rule.fields.map { field in
        (field.key, field.key == "date" ? "2026-03-02" : "\(field.key.capitalized)")
    })
    let filename = DeclarativeNamingRuleEngine().renderFilename(rule: rule, fields: sampleFields)
    issues.append(contentsOf: DeclarativeNamingRuleEngine().validateFilename(filename, rule: rule, fields: sampleFields))
    return issues
}

private func collectLearningSamples(
    request: RuleLearningRequest,
    logger: Logger
) throws -> [LearningDocumentSample] {
    let folderURL = URL(fileURLWithPath: request.folder_path, isDirectory: true).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw Abort(.badRequest, reason: "Le dossier source est introuvable.")
    }

    let allowedExtensions = normalizeLearningExtensions(request.extensions)
    let sampleSize = max(1, min(request.sample_size ?? 50, 200))
    guard let enumerator = FileManager.default.enumerator(
        at: folderURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var samples: [LearningDocumentSample] = []
    for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        let fileExtension = fileURL.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else { continue }
        guard let extracted = DocumentTextExtractor.extract(fileURL: fileURL, logger: logger) else { continue }
        let mergedText = extracted.pages.joined(separator: "\n\u{000C}\n")
        samples.append(
            LearningDocumentSample(
                file_name: fileURL.lastPathComponent,
                file_path: fileURL.path,
                file_extension: fileExtension,
                text: mergedText,
                metadata: [
                    "page_count": "\(extracted.pages.count)",
                    "kind": extracted.kind
                ]
            )
        )
        if samples.count >= sampleSize {
            break
        }
    }

    if samples.isEmpty {
        throw Abort(.badRequest, reason: "Aucun document exploitable trouvé dans ce dossier.")
    }
    return samples
}

private func normalizeLearningExtensions(_ raw: [String]?) -> Set<String> {
    let normalized = (raw ?? DocumentTextExtractor.supportedExtensions()).map {
        $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
            .lowercased()
    }.filter { DocumentTextExtractor.supportedExtensions().contains($0) }
    return Set(normalized.isEmpty ? DocumentTextExtractor.supportedExtensions() : normalized)
}
