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

struct MuniReglesUISnapshot: Sendable {
    let validation: MuniReglesValidationSnapshot
    let versions: MuniReglesVersionsSnapshot
}

enum MuniReglesReadModelLoader {
    static func load(logger: Logger) async -> MuniReglesUISnapshot {
        let history = await CockpitCanonicalLauncher.history(limit: 200, logger: logger)
        let entries = history.entries.filter { entry in
            entry.toolID == "MuniRegles" && shouldConsider(status: entry.status.rawValue)
        }

        let validation = readValidation(entries: entries, logger: logger)
        let versions = readVersions(entries: entries, logger: logger)
        return MuniReglesUISnapshot(validation: validation, versions: versions)
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

    private static func readVersions(entries: [CockpitHistoryEntry], logger: Logger) -> MuniReglesVersionsSnapshot {
        var bundlePath: String?
        var bundle: ReglesBundleProbe?
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
            bundlePath = resolvedBundlePath
            bundle = decoded
            break
        }

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

        let hasBundle = bundle != nil
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
                bundlePath: bundlePath,
                inspectReportPath: inspectPath,
                moduleVersion: inspect?.moduleVersion ?? bundle?.manifest.moduleVersion,
                bundleVersion: inspect?.bundleVersion ?? bundle?.manifest.bundleVersion,
                bundleGeneratedAt: bundle?.manifest.generatedAt,
                inspectGeneratedAt: inspect?.generatedAt,
                taxonomyID: inspect?.taxonomyID,
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
