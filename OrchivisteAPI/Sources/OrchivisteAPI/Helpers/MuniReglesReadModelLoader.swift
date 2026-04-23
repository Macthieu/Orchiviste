import Fluent
import Foundation
import Vapor

struct MuniReglesValidationIssueSnapshot: Sendable {
    let severity: String
    let code: String
    let message: String
    let field: String
}

struct MuniReglesValidationSnapshot: Sendable {
    let sourceKey: String
    let sourceLabel: String
    let summary: String
    let reportPath: String?
    let generatedAt: String?
    let taxonomyID: String?
    let errorCount: Int?
    let warningCount: Int?
    let issues: [MuniReglesValidationIssueSnapshot]
    let fallbackReason: String?
}

struct MuniReglesVersionsSnapshot: Sendable {
    let sourceKey: String
    let sourceLabel: String
    let bundlePath: String?
    let inspectReportPath: String?
    let moduleVersion: String?
    let bundleVersion: String?
    let bundleGeneratedAt: String?
    let inspectGeneratedAt: String?
    let taxonomyID: String?
    let errorCount: Int?
    let warningCount: Int?
    let classificationEntryCount: Int?
    let namingRuleCount: Int?
    let routingRuleCount: Int?
    let guideConventionCount: Int?
    let fallbackReason: String?
}

struct MuniReglesClassificationEntrySnapshot: Sendable {
    let code: String
    let label: String
    let path: String
}

struct MuniReglesClassificationSnapshot: Sendable {
    let sourceKey: String
    let sourceLabel: String
    let summary: String
    let taxonomyID: String?
    let version: String?
    let entryCount: Int?
    let entries: [MuniReglesClassificationEntrySnapshot]
    let bundlePath: String?
    let fallbackReason: String?
}

struct MuniReglesRulesNamingRuleSnapshot: Sendable {
    let id: String
    let label: String
    let template: String
}

struct MuniReglesRulesRoutingRuleSnapshot: Sendable {
    let id: String
    let classCode: String
    let destinationTemplate: String
}

struct MuniReglesRulesSnapshot: Sendable {
    let sourceKey: String
    let sourceLabel: String
    let summary: String
    let version: String?
    let namingRuleCount: Int?
    let routingRuleCount: Int?
    let namingRules: [MuniReglesRulesNamingRuleSnapshot]
    let routingRules: [MuniReglesRulesRoutingRuleSnapshot]
    let bundlePath: String?
    let fallbackReason: String?
}

struct MuniReglesGuideExampleSnapshot: Sendable {
    let input: String
    let output: String
}

struct MuniReglesGuideSnapshot: Sendable {
    let sourceKey: String
    let sourceLabel: String
    let summary: String
    let title: String?
    let conventionCount: Int?
    let conventions: [String]
    let examples: [MuniReglesGuideExampleSnapshot]
    let bundlePath: String?
    let fallbackReason: String?
}

struct MuniReglesUISnapshot: Sendable {
    let validation: MuniReglesValidationSnapshot
    let versions: MuniReglesVersionsSnapshot
    let classification: MuniReglesClassificationSnapshot
    let rules: MuniReglesRulesSnapshot
    let guide: MuniReglesGuideSnapshot
}

enum MuniReglesReadModelLoader {
    private struct BundleSource: Sendable {
        let path: String
        let bundle: ReglesBundleProbe
    }

    static func load(on db: Database, logger: Logger) async -> MuniReglesUISnapshot {
        let history = await CockpitCanonicalLauncher.history(limit: 200, on: db, logger: logger)
        let entries = history.entries.filter { entry in
            entry.toolID == "MuniRegles" && shouldConsider(status: entry.status.rawValue)
        }

        let bundleSource = latestBundle(entries: entries, logger: logger)
        let validation = readValidation(entries: entries, logger: logger)
        let versions = readVersions(entries: entries, bundleSource: bundleSource, logger: logger)
        let classification = readClassification(entries: entries, bundleSource: bundleSource, logger: logger)
        let rules = readRules(entries: entries, bundleSource: bundleSource, logger: logger)
        let guide = readGuide(entries: entries, bundleSource: bundleSource, logger: logger)

        return MuniReglesUISnapshot(
            validation: validation,
            versions: versions,
            classification: classification,
            rules: rules,
            guide: guide
        )
    }

    private static func readValidation(entries: [CockpitHistoryEntry], logger: Logger) -> MuniReglesValidationSnapshot {
        for entry in entries {
            guard let reportPath = resolveArtifactPath(
                artifactID: "validation_report",
                kind: "report",
                entry: entry,
                logger: logger
            ) else {
                continue
            }
            guard let report = decodeJSON(ValidationReportProbe.self, fromPath: reportPath, logger: logger) else {
                continue
            }

            return MuniReglesValidationSnapshot(
                sourceKey: "muniregles_artifact",
                sourceLabel: "Artefact MuniRegles (validation_report)",
                summary: report.errorCount > 0
                    ? "Validation MuniRegles en erreur (bloquante)."
                    : (report.warningCount > 0
                        ? "Validation MuniRegles avec avertissements."
                        : "Validation MuniRegles conforme."),
                reportPath: reportPath,
                generatedAt: report.generatedAt,
                taxonomyID: report.taxonomyID,
                errorCount: report.errorCount,
                warningCount: report.warningCount,
                issues: report.issues.map {
                    MuniReglesValidationIssueSnapshot(
                        severity: $0.severity,
                        code: $0.code,
                        message: $0.message,
                        field: $0.field ?? "-"
                    )
                },
                fallbackReason: nil
            )
        }

        for entry in entries {
            guard let reportPath = resolveArtifactPath(
                artifactID: "inspect_report",
                kind: "report",
                entry: entry,
                logger: logger
            ) else {
                continue
            }
            guard let report = decodeJSON(InspectReportProbe.self, fromPath: reportPath, logger: logger) else {
                continue
            }

            return MuniReglesValidationSnapshot(
                sourceKey: "muniregles_artifact_partial",
                sourceLabel: "Artefact MuniRegles (inspect_report en fallback)",
                summary: report.errorCount > 0
                    ? "Inspection MuniRegles signale des erreurs bloquantes."
                    : (report.warningCount > 0
                        ? "Inspection MuniRegles avec avertissements."
                        : "Inspection MuniRegles conforme."),
                reportPath: reportPath,
                generatedAt: report.generatedAt,
                taxonomyID: report.taxonomyID,
                errorCount: report.errorCount,
                warningCount: report.warningCount,
                issues: [],
                fallbackReason: nil
            )
        }

        if entries.isEmpty {
            return MuniReglesValidationSnapshot(
                sourceKey: "unavailable",
                sourceLabel: "Aucun artefact MuniRegles disponible",
                summary: "Aucune exécution MuniRegles détectée dans l'historique cockpit.",
                reportPath: nil,
                generatedAt: nil,
                taxonomyID: nil,
                errorCount: nil,
                warningCount: nil,
                issues: [],
                fallbackReason: "Aucun run MuniRegles trouvé. La vue reste en mode legacy."
            )
        }

        return MuniReglesValidationSnapshot(
            sourceKey: "legacy_fallback",
            sourceLabel: "Fallback legacy",
            summary: "Runs MuniRegles présents, mais aucun rapport lisible.",
            reportPath: nil,
            generatedAt: nil,
            taxonomyID: nil,
            errorCount: nil,
            warningCount: nil,
            issues: [],
            fallbackReason: "Impossible de lire validation_report/inspect_report. La vue reste en mode legacy."
        )
    }

    private static func readVersions(
        entries: [CockpitHistoryEntry],
        bundleSource: BundleSource?,
        logger: Logger
    ) -> MuniReglesVersionsSnapshot {
        var inspectPath: String?
        var inspect: InspectReportProbe?
        for entry in entries {
            guard let resolvedInspectPath = resolveArtifactPath(
                artifactID: "inspect_report",
                kind: "report",
                entry: entry,
                logger: logger
            ),
            let decoded = decodeJSON(InspectReportProbe.self, fromPath: resolvedInspectPath, logger: logger) else {
                continue
            }
            inspectPath = resolvedInspectPath
            inspect = decoded
            break
        }

        let hasBundle = bundleSource != nil
        let hasInspect = inspect != nil

        if hasBundle || hasInspect {
            let sourceLabel: String
            if hasBundle && hasInspect {
                sourceLabel = "Artefacts MuniRegles (bundle + inspect)"
            } else {
                sourceLabel = "Artefacts MuniRegles partiels"
            }

            return MuniReglesVersionsSnapshot(
                sourceKey: hasBundle && hasInspect ? "muniregles_artifact" : "muniregles_artifact_partial",
                sourceLabel: sourceLabel,
                bundlePath: bundleSource?.path,
                inspectReportPath: inspectPath,
                moduleVersion: inspect?.moduleVersion ?? bundleSource?.bundle.manifest.moduleVersion,
                bundleVersion: inspect?.bundleVersion ?? bundleSource?.bundle.manifest.bundleVersion,
                bundleGeneratedAt: bundleSource?.bundle.manifest.generatedAt,
                inspectGeneratedAt: inspect?.generatedAt,
                taxonomyID: inspect?.taxonomyID ?? bundleSource?.bundle.classificationPlan.taxonomyID,
                errorCount: inspect?.errorCount,
                warningCount: inspect?.warningCount,
                classificationEntryCount: inspect?.classificationEntryCount,
                namingRuleCount: inspect?.namingRuleCount,
                routingRuleCount: inspect?.routingRuleCount,
                guideConventionCount: inspect?.guideConventionCount,
                fallbackReason: nil
            )
        }

        if entries.isEmpty {
            return MuniReglesVersionsSnapshot(
                sourceKey: "unavailable",
                sourceLabel: "Aucun artefact MuniRegles disponible",
                bundlePath: nil,
                inspectReportPath: nil,
                moduleVersion: nil,
                bundleVersion: nil,
                bundleGeneratedAt: nil,
                inspectGeneratedAt: nil,
                taxonomyID: nil,
                errorCount: nil,
                warningCount: nil,
                classificationEntryCount: nil,
                namingRuleCount: nil,
                routingRuleCount: nil,
                guideConventionCount: nil,
                fallbackReason: "Aucun run MuniRegles trouvé. La vue reste en mode legacy."
            )
        }

        return MuniReglesVersionsSnapshot(
            sourceKey: "legacy_fallback",
            sourceLabel: "Fallback legacy",
            bundlePath: nil,
            inspectReportPath: nil,
            moduleVersion: nil,
            bundleVersion: nil,
            bundleGeneratedAt: nil,
            inspectGeneratedAt: nil,
            taxonomyID: nil,
            errorCount: nil,
            warningCount: nil,
            classificationEntryCount: nil,
            namingRuleCount: nil,
            routingRuleCount: nil,
            guideConventionCount: nil,
            fallbackReason: "Runs MuniRegles présents, mais aucun artefact bundle/inspect lisible."
        )
    }

    private static func readClassification(
        entries: [CockpitHistoryEntry],
        bundleSource: BundleSource?,
        logger: Logger
    ) -> MuniReglesClassificationSnapshot {
        if let bundleSource {
            let plan = bundleSource.bundle.classificationPlan
            let rows = plan.entries.map {
                MuniReglesClassificationEntrySnapshot(
                    code: $0.code,
                    label: $0.label ?? "-",
                    path: $0.path ?? "-"
                )
            }

            return MuniReglesClassificationSnapshot(
                sourceKey: "muniregles_artifact",
                sourceLabel: "Artefact MuniRegles (classification_plan du bundle)",
                summary: "Plan de classification chargé depuis le bundle MuniRegles.",
                taxonomyID: plan.taxonomyID,
                version: plan.version,
                entryCount: rows.count,
                entries: rows,
                bundlePath: bundleSource.path,
                fallbackReason: nil
            )
        }

        for entry in entries {
            guard let classificationPath = resolveRequestParameterPath(
                parameterKey: "classification_path",
                entry: entry,
                logger: logger
            ),
            let plan = decodeJSON(ClassificationPlanProbe.self, fromPath: classificationPath, logger: logger) else {
                continue
            }

            let rows = plan.entries.map {
                MuniReglesClassificationEntrySnapshot(
                    code: $0.code,
                    label: $0.label ?? "-",
                    path: $0.path ?? "-"
                )
            }

            return MuniReglesClassificationSnapshot(
                sourceKey: "muniregles_request_path",
                sourceLabel: "Source MuniRegles (classification_path du dernier run)",
                summary: "Classification chargée via le chemin source du dernier run MuniRegles.",
                taxonomyID: plan.taxonomyID,
                version: plan.version,
                entryCount: rows.count,
                entries: rows,
                bundlePath: classificationPath,
                fallbackReason: nil
            )
        }

        if entries.isEmpty {
            return MuniReglesClassificationSnapshot(
                sourceKey: "unavailable",
                sourceLabel: "Aucun artefact MuniRegles disponible",
                summary: "Aucune exécution MuniRegles détectée pour la classification.",
                taxonomyID: nil,
                version: nil,
                entryCount: nil,
                entries: [],
                bundlePath: nil,
                fallbackReason: "Aucun run MuniRegles trouvé. La vue reste en mode legacy (Préréglages)."
            )
        }

        return MuniReglesClassificationSnapshot(
            sourceKey: "legacy_fallback",
            sourceLabel: "Fallback legacy",
            summary: "Aucune source classification exploitable dans les artefacts MuniRegles.",
            taxonomyID: nil,
            version: nil,
            entryCount: nil,
            entries: [],
            bundlePath: nil,
            fallbackReason: "Impossible de lire classification_plan/classification_path. La vue reste en mode legacy (Préréglages)."
        )
    }

    private static func readRules(
        entries: [CockpitHistoryEntry],
        bundleSource: BundleSource?,
        logger: Logger
    ) -> MuniReglesRulesSnapshot {
        if let bundleSource {
            let rules = bundleSource.bundle.namingAndRoutingRules
            let namingRows = rules.namingRules.map {
                MuniReglesRulesNamingRuleSnapshot(
                    id: $0.id,
                    label: $0.label ?? "-",
                    template: $0.template ?? "-"
                )
            }
            let routingRows = rules.routingRules.map {
                MuniReglesRulesRoutingRuleSnapshot(
                    id: $0.id,
                    classCode: $0.classCode ?? "-",
                    destinationTemplate: $0.destinationTemplate ?? "-"
                )
            }

            return MuniReglesRulesSnapshot(
                sourceKey: "muniregles_artifact",
                sourceLabel: "Artefact MuniRegles (naming_and_routing_rules du bundle)",
                summary: "Règles de nommage et de routage chargées depuis le bundle MuniRegles.",
                version: rules.version,
                namingRuleCount: namingRows.count,
                routingRuleCount: routingRows.count,
                namingRules: namingRows,
                routingRules: routingRows,
                bundlePath: bundleSource.path,
                fallbackReason: nil
            )
        }

        for entry in entries {
            guard let rulesPath = resolveRequestParameterPath(
                parameterKey: "rules_path",
                entry: entry,
                logger: logger
            ),
            let rules = decodeJSON(NamingAndRoutingRulesProbe.self, fromPath: rulesPath, logger: logger) else {
                continue
            }

            let namingRows = rules.namingRules.map {
                MuniReglesRulesNamingRuleSnapshot(
                    id: $0.id,
                    label: $0.label ?? "-",
                    template: $0.template ?? "-"
                )
            }
            let routingRows = rules.routingRules.map {
                MuniReglesRulesRoutingRuleSnapshot(
                    id: $0.id,
                    classCode: $0.classCode ?? "-",
                    destinationTemplate: $0.destinationTemplate ?? "-"
                )
            }

            return MuniReglesRulesSnapshot(
                sourceKey: "muniregles_request_path",
                sourceLabel: "Source MuniRegles (rules_path du dernier run)",
                summary: "Règles chargées via le chemin source du dernier run MuniRegles.",
                version: rules.version,
                namingRuleCount: namingRows.count,
                routingRuleCount: routingRows.count,
                namingRules: namingRows,
                routingRules: routingRows,
                bundlePath: rulesPath,
                fallbackReason: nil
            )
        }

        if entries.isEmpty {
            return MuniReglesRulesSnapshot(
                sourceKey: "unavailable",
                sourceLabel: "Aucun artefact MuniRegles disponible",
                summary: "Aucune exécution MuniRegles détectée pour les règles.",
                version: nil,
                namingRuleCount: nil,
                routingRuleCount: nil,
                namingRules: [],
                routingRules: [],
                bundlePath: nil,
                fallbackReason: "Aucun run MuniRegles trouvé. Les vues legacy Nommage/Préréglages restent la source."
            )
        }

        return MuniReglesRulesSnapshot(
            sourceKey: "legacy_fallback",
            sourceLabel: "Fallback legacy",
            summary: "Aucune source rules exploitable dans les artefacts MuniRegles.",
            version: nil,
            namingRuleCount: nil,
            routingRuleCount: nil,
            namingRules: [],
            routingRules: [],
            bundlePath: nil,
            fallbackReason: "Impossible de lire naming_and_routing_rules/rules_path. Les vues legacy restent actives."
        )
    }

    private static func readGuide(
        entries: [CockpitHistoryEntry],
        bundleSource: BundleSource?,
        logger: Logger
    ) -> MuniReglesGuideSnapshot {
        if let bundleSource {
            let guide = bundleSource.bundle.renamingGuide
            return MuniReglesGuideSnapshot(
                sourceKey: "muniregles_artifact",
                sourceLabel: "Artefact MuniRegles (renaming_guide du bundle)",
                summary: "Guide de renommage chargé depuis le bundle MuniRegles.",
                title: guide.title,
                conventionCount: guide.conventions.count,
                conventions: guide.conventions,
                examples: guide.examples.map {
                    MuniReglesGuideExampleSnapshot(input: $0.input, output: $0.output)
                },
                bundlePath: bundleSource.path,
                fallbackReason: nil
            )
        }

        for entry in entries {
            guard let guidePath = resolveRequestParameterPath(
                parameterKey: "guide_path",
                entry: entry,
                logger: logger
            ),
            let guide = decodeJSON(RenamingGuideProbe.self, fromPath: guidePath, logger: logger) else {
                continue
            }

            return MuniReglesGuideSnapshot(
                sourceKey: "muniregles_request_path",
                sourceLabel: "Source MuniRegles (guide_path du dernier run)",
                summary: "Guide chargé via le chemin source du dernier run MuniRegles.",
                title: guide.title,
                conventionCount: guide.conventions.count,
                conventions: guide.conventions,
                examples: guide.examples.map {
                    MuniReglesGuideExampleSnapshot(input: $0.input, output: $0.output)
                },
                bundlePath: guidePath,
                fallbackReason: nil
            )
        }

        if entries.isEmpty {
            return MuniReglesGuideSnapshot(
                sourceKey: "unavailable",
                sourceLabel: "Aucun artefact MuniRegles disponible",
                summary: "Aucune exécution MuniRegles détectée pour le guide.",
                title: nil,
                conventionCount: nil,
                conventions: [],
                examples: [],
                bundlePath: nil,
                fallbackReason: "Aucun run MuniRegles trouvé. Le guide legacy reste la source."
            )
        }

        return MuniReglesGuideSnapshot(
            sourceKey: "legacy_fallback",
            sourceLabel: "Fallback legacy",
            summary: "Aucune source guide exploitable dans les artefacts MuniRegles.",
            title: nil,
            conventionCount: nil,
            conventions: [],
            examples: [],
            bundlePath: nil,
            fallbackReason: "Impossible de lire renaming_guide/guide_path. Le guide legacy reste actif."
        )
    }

    private static func latestBundle(entries: [CockpitHistoryEntry], logger: Logger) -> BundleSource? {
        for entry in entries {
            guard let resolvedBundlePath = resolveArtifactPath(
                artifactID: "regles_bundle",
                kind: "output",
                entry: entry,
                logger: logger
            ),
            let decoded = decodeJSON(ReglesBundleProbe.self, fromPath: resolvedBundlePath, logger: logger) else {
                continue
            }
            return BundleSource(path: resolvedBundlePath, bundle: decoded)
        }
        return nil
    }

    private static func shouldConsider(status: String) -> Bool {
        switch status {
        case "queued", "running", "cancelled":
            return false
        default:
            return true
        }
    }

    private static func resolveArtifactPath(
        artifactID: String,
        kind: String,
        entry: CockpitHistoryEntry,
        logger: Logger
    ) -> String? {
        guard let probe = decodeJSON(ToolResultProbe.self, fromPath: entry.resultFile, logger: logger) else {
            return nil
        }

        guard let artifact = probe.outputArtifacts.first(where: { artifact in
            artifact.id == artifactID && artifact.kind == kind
        }) else {
            return nil
        }

        return resolvePath(artifact.uri, relativeToFile: entry.resultFile)
    }

    private static func resolveRequestParameterPath(
        parameterKey: String,
        entry: CockpitHistoryEntry,
        logger: Logger
    ) -> String? {
        guard let rawPath = readStringParameter(parameterKey, fromRequestFile: entry.requestFile, logger: logger) else {
            return nil
        }
        return resolvePath(rawPath, relativeToFile: entry.requestFile)
    }

    private static func readStringParameter(
        _ key: String,
        fromRequestFile requestFile: String,
        logger: Logger
    ) -> String? {
        let fileURL = URL(fileURLWithPath: requestFile)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parameters = root["parameters"] as? [String: Any],
                  let value = parameters[key] as? String else {
                return nil
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            logger.debug("Lecture request.json MuniRegles ignorée (best effort).", metadata: [
                "path": .string(fileURL.path),
                "error": .string(error.localizedDescription)
            ])
            return nil
        }
    }

    private static func decodeJSON<T: Decodable>(
        _ type: T.Type,
        fromPath path: String,
        logger: Logger
    ) -> T? {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.debug("Lecture JSON MuniRegles ignorée (best effort).", metadata: [
                "path": .string(fileURL.path),
                "error": .string(error.localizedDescription)
            ])
            return nil
        }
    }

    private static func resolvePath(_ rawValue: String, relativeToFile resultFilePath: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("file://"), let url = URL(string: trimmed) {
            return url.path
        }
        if (trimmed as NSString).isAbsolutePath {
            return trimmed
        }

        let base = URL(fileURLWithPath: resultFilePath).deletingLastPathComponent()
        return base.appendingPathComponent(trimmed).standardizedFileURL.path
    }
}

private struct ToolResultProbe: Decodable {
    let outputArtifacts: [ToolResultArtifactProbe]

    enum CodingKeys: String, CodingKey {
        case outputArtifacts = "output_artifacts"
    }
}

private struct ToolResultArtifactProbe: Decodable {
    let id: String
    let kind: String
    let uri: String
}

private struct ValidationReportProbe: Decodable {
    let generatedAt: String
    let taxonomyID: String
    let errorCount: Int
    let warningCount: Int
    let issues: [ValidationIssueProbe]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case taxonomyID = "taxonomy_id"
        case errorCount = "error_count"
        case warningCount = "warning_count"
        case issues
    }
}

private struct ValidationIssueProbe: Decodable {
    let severity: String
    let code: String
    let message: String
    let field: String?
}

private struct InspectReportProbe: Decodable {
    let generatedAt: String
    let bundleVersion: String
    let moduleVersion: String
    let taxonomyID: String
    let classificationEntryCount: Int
    let namingRuleCount: Int
    let routingRuleCount: Int
    let guideConventionCount: Int
    let errorCount: Int
    let warningCount: Int

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case bundleVersion = "bundle_version"
        case moduleVersion = "module_version"
        case taxonomyID = "taxonomy_id"
        case classificationEntryCount = "classification_entry_count"
        case namingRuleCount = "naming_rule_count"
        case routingRuleCount = "routing_rule_count"
        case guideConventionCount = "guide_convention_count"
        case errorCount = "error_count"
        case warningCount = "warning_count"
    }
}

private struct ReglesBundleProbe: Decodable {
    let manifest: ReglesBundleManifestProbe
    let classificationPlan: ClassificationPlanProbe
    let namingAndRoutingRules: NamingAndRoutingRulesProbe
    let renamingGuide: RenamingGuideProbe

    enum CodingKeys: String, CodingKey {
        case manifest
        case classificationPlan = "classification_plan"
        case namingAndRoutingRules = "naming_and_routing_rules"
        case renamingGuide = "renaming_guide"
    }
}

private struct ReglesBundleManifestProbe: Decodable {
    let bundleVersion: String
    let moduleVersion: String
    let generatedAt: String

    enum CodingKeys: String, CodingKey {
        case bundleVersion = "bundle_version"
        case moduleVersion = "module_version"
        case generatedAt = "generated_at"
    }
}

private struct ClassificationPlanProbe: Decodable {
    let taxonomyID: String
    let version: String?
    let entries: [ClassificationEntryProbe]

    enum CodingKeys: String, CodingKey {
        case taxonomyID = "taxonomy_id"
        case version
        case entries
    }
}

private struct ClassificationEntryProbe: Decodable {
    let code: String
    let label: String?
    let path: String?
}

private struct NamingAndRoutingRulesProbe: Decodable {
    let version: String?
    let namingRules: [NamingRuleProbe]
    let routingRules: [RoutingRuleProbe]

    enum CodingKeys: String, CodingKey {
        case version
        case namingRules = "naming_rules"
        case routingRules = "routing_rules"
    }
}

private struct NamingRuleProbe: Decodable {
    let id: String
    let label: String?
    let template: String?
}

private struct RoutingRuleProbe: Decodable {
    let id: String
    let classCode: String?
    let destinationTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case classCode = "class_code"
        case destinationTemplate = "destination_template"
    }
}

private struct RenamingGuideProbe: Decodable {
    let title: String?
    let conventions: [String]
    let examples: [GuideExampleProbe]

    enum CodingKeys: String, CodingKey {
        case title
        case conventions
        case examples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        conventions = try container.decodeIfPresent([String].self, forKey: .conventions) ?? []
        examples = try container.decodeIfPresent([GuideExampleProbe].self, forKey: .examples) ?? []
    }
}

private struct GuideExampleProbe: Decodable {
    let input: String
    let output: String
}
