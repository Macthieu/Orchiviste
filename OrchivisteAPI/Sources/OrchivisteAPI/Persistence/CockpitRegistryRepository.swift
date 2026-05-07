import Fluent
import Foundation
import OrchivisteKitContracts
import Vapor

enum CockpitRegistryRepository {
    static func loadToolDescriptors(
        baseConfig: CockpitConfig,
        on db: Database,
        logger: Logger? = nil
    ) async -> [CockpitToolDescriptor] {
        do {
            try await syncRegistryIfNeeded(from: baseConfig.tools, on: db)
            let rows = try await MuniAppRow.query(on: db)
                .sort(\.$displayName, .ascending)
                .all()
            let descriptors = try rows.map(toolDescriptor(from:))
            return descriptors.isEmpty ? baseConfig.tools : descriptors
        } catch {
            logger?.warning("Chargement du registre Muni depuis SQLite impossible, fallback config conserve.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return baseConfig.tools
        }
    }

    static func listMuniApps(
        baseConfig: CockpitConfig,
        on db: Database
    ) async throws -> [MuniAppRecord] {
        try await syncRegistryIfNeeded(from: baseConfig.tools, on: db)
        let rows = try await MuniAppRow.query(on: db)
            .sort(\.$displayName, .ascending)
            .all()
        return try await rows.asyncMap { row in
            try await muniAppRecord(from: row, on: db)
        }
    }

    static func fetchMuniApp(
        appID: String,
        baseConfig: CockpitConfig,
        on db: Database
    ) async throws -> MuniAppRecord? {
        try await syncRegistryIfNeeded(from: baseConfig.tools, on: db)
        guard let row = try await MuniAppRow.query(on: db)
            .filter(\.$appID == appID)
            .first() else {
            return nil
        }
        return try await muniAppRecord(from: row, on: db)
    }

    static func updateMuniAppEnabled(
        appID: String,
        enabled: Bool,
        on db: Database
    ) async throws -> MuniAppRecord? {
        guard let row = try await MuniAppRow.query(on: db)
            .filter(\.$appID == appID)
            .first() else {
            return nil
        }

        row.enabled = enabled
        row.updatedAt = Date()
        try await row.update(on: db)
        return try await muniAppRecord(from: row, on: db)
    }

    static func appendHistoryEntry(
        _ entry: CockpitHistoryEntry,
        on db: Database,
        logger: Logger
    ) async throws {
        let now = Date()
        let commandJSON = try encodeJSONString(entry.command)
        let errorCodesJSON = try encodeJSONString(entry.errorCodes)

        if let existing = try await RunHistoryRow.query(on: db)
            .filter(\.$executionID == entry.executionID)
            .first() {
            existing.requestID = entry.requestID
            existing.appID = entry.toolID
            existing.action = entry.action
            existing.status = entry.status.rawValue
            existing.summary = entry.summary
            existing.commandJSON = commandJSON
            existing.requestFile = entry.requestFile
            existing.resultFile = entry.resultFile
            existing.exitCode = entry.exitCode.map(Int.init)
            existing.startedAt = parseISO8601(entry.startedAt) ?? existing.startedAt
            existing.finishedAt = parseISO8601(entry.finishedAt) ?? now
            existing.dryRun = entry.dryRun
            existing.errorCodesJSON = errorCodesJSON
            existing.createdAt = existing.createdAt
            try await existing.update(on: db)
        } else {
            let row = RunHistoryRow(
                entry: entry,
                appID: entry.toolID,
                commandJSON: commandJSON,
                errorCodesJSON: errorCodesJSON,
                createdAt: now
            )
            try await row.create(on: db)
        }

        try await RunDiagnosticRow.query(on: db)
            .filter(\.$executionID == entry.executionID)
            .delete()

        let diagnostics = try deriveDiagnostics(for: entry, logger: logger)
        for diagnostic in diagnostics {
            let row = RunDiagnosticRow(
                executionID: diagnostic.executionID,
                diagnosticID: diagnostic.diagnosticID,
                severity: diagnostic.severity,
                label: diagnostic.label,
                cta: diagnostic.cta,
                source: diagnostic.source,
                details: diagnostic.details,
                createdAt: now
            )
            try await row.create(on: db)
        }
    }

    static func listHistoryEntries(
        limit: Int,
        on db: Database
    ) async throws -> [CockpitHistoryEntry] {
        let bounded = max(1, min(500, limit))
        let rows = try await RunHistoryRow.query(on: db)
            .sort(\.$finishedAt, .descending)
            .limit(bounded)
            .all()
        return try rows.map(historyEntry(from:))
    }

    static func listRecentRuns(
        appID: String,
        limit: Int,
        on db: Database
    ) async throws -> [CockpitHistoryEntry] {
        let bounded = max(1, min(50, limit))
        let rows = try await RunHistoryRow.query(on: db)
            .filter(\.$appID == appID)
            .sort(\.$finishedAt, .descending)
            .limit(bounded)
            .all()
        return try rows.map(historyEntry(from:))
    }

    static func topDiagnostic(
        executionID: String,
        on db: Database
    ) async throws -> RunDiagnosticRecord? {
        let rows = try await RunDiagnosticRow.query(on: db)
            .filter(\.$executionID == executionID)
            .all()
        return rows
            .map(runDiagnosticRecord(from:))
            .sorted(by: compareDiagnostics)
            .first
    }

    private static func syncRegistryIfNeeded(
        from toolDescriptors: [CockpitToolDescriptor],
        on db: Database
    ) async throws {
        let now = Date()
        for descriptor in toolDescriptors {
            let capabilitiesJSON = try encodeJSONString(descriptor.capabilities)
            let defaultParametersJSON = try encodeJSONString(descriptor.defaultParameters)

            if try await MuniAppRow.query(on: db)
                .filter(\.$appID == descriptor.id)
                .first() == nil {
                let row = MuniAppRow(
                    descriptor: descriptor,
                    now: now,
                    capabilitiesJSON: capabilitiesJSON,
                    defaultParametersJSON: defaultParametersJSON
                )
                try await row.create(on: db)
            }

            for action in seededActions(for: descriptor) {
                if try await MuniAppActionRow.query(on: db)
                    .filter(\.$appID == descriptor.id)
                    .filter(\.$actionKey == action.actionKey)
                    .first() == nil {
                    let row = MuniAppActionRow(
                        appID: descriptor.id,
                        actionKey: action.actionKey,
                        actionLabel: action.actionLabel,
                        isPrimary: action.isPrimary,
                        now: now
                    )
                    try await row.create(on: db)
                }
            }

            if try await RunProfileRow.query(on: db)
                .filter(\.$appID == descriptor.id)
                .filter(\.$profileKey == "expert-default")
                .first() == nil {
                let row = RunProfileRow(
                    appID: descriptor.id,
                    profileKey: "expert-default",
                    displayName: "Profil expert par défaut",
                    actionKey: descriptor.defaultAction,
                    parametersJSON: defaultParametersJSON,
                    allowDestructive: false,
                    expertOnly: true,
                    now: now
                )
                try await row.create(on: db)
            }
        }
    }

    private static func seededActions(for descriptor: CockpitToolDescriptor) -> [MuniAppActionRecord] {
        let actionableCapabilities: Set<String> = [
            "run", "preview", "apply", "validate", "bundle", "inspect",
            "analyze", "convert", "enrich", "preclassify", "audit"
        ]
        var ordered: [String] = []
        func append(_ value: String) {
            guard !ordered.contains(value) else { return }
            ordered.append(value)
        }

        append(descriptor.defaultAction)
        descriptor.capabilities
            .filter { actionableCapabilities.contains($0) }
            .forEach(append)

        return ordered.map { actionKey in
            MuniAppActionRecord(
                appID: descriptor.id,
                actionKey: actionKey,
                actionLabel: actionLabel(for: actionKey),
                isPrimary: actionKey == descriptor.defaultAction
            )
        }
    }

    private static func actionLabel(for actionKey: String) -> String {
        switch actionKey {
        case "preview":
            return "Prévisualisation"
        case "apply":
            return "Application contrôlée"
        case "validate":
            return "Validation"
        case "bundle":
            return "Bundle"
        case "inspect":
            return "Inspection"
        case "analyze":
            return "Analyse"
        case "convert":
            return "Conversion"
        case "enrich":
            return "Enrichissement"
        case "preclassify":
            return "Préclassement"
        case "audit":
            return "Contrôle"
        case "run":
            return "Exécution"
        default:
            return actionKey
        }
    }

    private static func toolDescriptor(from row: MuniAppRow) throws -> CockpitToolDescriptor {
        CockpitToolDescriptor(
            id: row.appID,
            displayName: row.displayName,
            mission: row.mission,
            repositoryPath: row.repositoryPath,
            executable: row.executable,
            executablePath: row.executablePath,
            version: row.version,
            integrationStatus: row.integrationStatus,
            capabilities: try decodeJSONValue(row.capabilitiesJSON),
            defaultAction: row.defaultAction,
            defaultParameters: try decodeJSONValue(row.defaultParametersJSON),
            supportsDryRun: row.supportsDryRun,
            destructiveRequiresConfirmation: row.destructiveRequiresConfirmation,
            confirmationParameter: row.confirmationParameter,
            enabled: row.enabled
        )
    }

    private static func muniAppRecord(from row: MuniAppRow, on db: Database) async throws -> MuniAppRecord {
        let descriptor = try toolDescriptor(from: row)
        let actionRows = try await MuniAppActionRow.query(on: db)
            .filter(\.$appID == row.appID)
            .sort(\.$isPrimary, .descending)
            .sort(\.$actionLabel, .ascending)
            .all()
        let profileRows = try await RunProfileRow.query(on: db)
            .filter(\.$appID == row.appID)
            .sort(\.$displayName, .ascending)
            .all()
        return MuniAppRecord(
            descriptor: descriptor,
            actions: actionRows.map {
                MuniAppActionRecord(
                    appID: $0.appID,
                    actionKey: $0.actionKey,
                    actionLabel: $0.actionLabel,
                    isPrimary: $0.isPrimary
                )
            },
            profiles: try profileRows.map {
                RunProfileRecord(
                    appID: $0.appID,
                    profileKey: $0.profileKey,
                    displayName: $0.displayName,
                    actionKey: $0.actionKey,
                    parameters: try decodeJSONValue($0.parametersJSON),
                    allowDestructive: $0.allowDestructive,
                    expertOnly: $0.expertOnly
                )
            }
        )
    }

    private static func historyEntry(from row: RunHistoryRow) throws -> CockpitHistoryEntry {
        CockpitHistoryEntry(
            executionID: row.executionID,
            requestID: row.requestID,
            toolID: row.appID,
            action: row.action,
            status: ToolStatus(rawValue: row.status) ?? .failed,
            summary: row.summary,
            command: try decodeJSONValue(row.commandJSON),
            requestFile: row.requestFile,
            resultFile: row.resultFile,
            exitCode: row.exitCode.map(Int32.init),
            startedAt: isoTimestamp(row.startedAt),
            finishedAt: isoTimestamp(row.finishedAt),
            dryRun: row.dryRun,
            errorCodes: try decodeJSONValue(row.errorCodesJSON)
        )
    }

    private static func deriveDiagnostics(
        for entry: CockpitHistoryEntry,
        logger: Logger
    ) throws -> [RunDiagnosticRecord] {
        let root = readJSONObject(atPath: entry.resultFile, logger: logger) ?? [:]
        let metadata = root["metadata"] as? [String: Any] ?? [:]
        let summary = (entry.summary ?? "").lowercased()
        let errorsText = extractErrorLabels(fromResultRoot: root).joined(separator: " ").lowercased()
        let fallbackReason = stringValue(from: metadata["regles_fallback_reason"])?.lowercased() ?? ""
        let extractionProvenance = stringValue(from: metadata["extraction_provenance"])?.lowercased()
        let collisionCount = intValue(from: metadata["collision_count"]) ?? 0
        let idempotentCount = intValue(from: metadata["idempotent_count"]) ?? 0
        let warningCount = intValue(from: metadata["warning_count"]) ?? 0

        var diagnostics: [RunDiagnosticRecord] = []

        if collisionCount > 0 ||
            summary.contains("collision") ||
            errorsText.contains("collision") ||
            summary.contains("destination_exists") ||
            summary.contains("destination already exists") ||
            summary.contains("destination existante") ||
            errorsText.contains("destination_exists") ||
            errorsText.contains("destination already exists") ||
            errorsText.contains("destination existante") {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RN_COLLISION_BLOCKING",
                    severity: "blocking",
                    label: "Collision bloquante / destination existante",
                    cta: "Stop Apply",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if summary.contains("expected_plan_digest") ||
            summary.contains("digest") ||
            errorsText.contains("expected_plan_digest") ||
            errorsText.contains("plan_digest") {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RN_PLAN_DIGEST_MISMATCH",
                    severity: "blocking",
                    label: "Digest preview/apply incohérent",
                    cta: "Re-preview",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if summary.contains("allow_destructive") ||
            summary.contains("confirm_apply") ||
            errorsText.contains("allow_destructive") {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RN_DESTRUCTIVE_GUARD_MISSING",
                    severity: "blocking",
                    label: "Garde-fou apply manquant",
                    cta: "Stop Apply",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if fallbackReason == "required_metadata_fields_missing" ||
            summary.contains("required_metadata_fields") ||
            errorsText.contains("required_metadata_fields") {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RG_REQUIRED_METADATA_FIELDS_MISSING",
                    severity: "blocking",
                    label: "Metadata requises manquantes",
                    cta: "Re-run Analyse",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if ["bundle_unreadable_or_invalid", "bundle_has_no_naming_rules"].contains(fallbackReason) {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RG_BUNDLE_UNREADABLE_OR_INVALID",
                    severity: "blocking",
                    label: "Bundle règles invalide",
                    cta: "Rebuild Bundle",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if ["naming_rule_not_found", "template_not_supported", "naming_rule_id_missing", "class_code_missing", "document_metadata_not_provided"].contains(fallbackReason) {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RG_RULE_NOT_FOUND_OR_NOT_APPLICABLE",
                    severity: "blocking",
                    label: "Règle absente ou non applicable",
                    cta: "Re-preview",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if !fallbackReason.isEmpty && diagnostics.isEmpty {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RG_FALLBACK_REASON_PRESENT",
                    severity: "warning",
                    label: "Fallback règle: \(fallbackReason)",
                    cta: "Re-preview",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if warningCount > 0 {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "AN_EXTRACTION_WARNING_STRUCTURED",
                    severity: "warning",
                    label: "Qualité extraction à vérifier",
                    cta: "Re-run Analyse",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if extractionProvenance == "filename_fallback" {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "AN_EXTRACTION_PROVENANCE_FALLBACK",
                    severity: "warning",
                    label: "Extraction en provenance fallback",
                    cta: "Re-run Analyse",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if idempotentCount > 0, entry.status == .succeeded {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RN_IDEMPOTENT_NOOP",
                    severity: "info",
                    label: "Aucun changement requis (no-op)",
                    cta: nil,
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        if diagnostics.isEmpty, entry.status == .failed {
            diagnostics.append(
                RunDiagnosticRecord(
                    executionID: entry.executionID,
                    diagnosticID: "RN_EXECUTION_FAILED",
                    severity: "warning",
                    label: "Échec d'exécution à revoir",
                    cta: "Re-preview",
                    source: entry.toolID,
                    details: entry.summary
                )
            )
        }

        return deduplicate(diagnostics)
    }

    private static func deduplicate(_ diagnostics: [RunDiagnosticRecord]) -> [RunDiagnosticRecord] {
        var seen: Set<String> = []
        var ordered: [RunDiagnosticRecord] = []
        for diagnostic in diagnostics.sorted(by: compareDiagnostics) {
            let key = "\(diagnostic.executionID)|\(diagnostic.diagnosticID)|\(diagnostic.severity)"
            guard seen.insert(key).inserted else { continue }
            ordered.append(diagnostic)
        }
        return ordered
    }

    private static func compareDiagnostics(_ lhs: RunDiagnosticRecord, _ rhs: RunDiagnosticRecord) -> Bool {
        severityRank(lhs.severity) < severityRank(rhs.severity)
            || (severityRank(lhs.severity) == severityRank(rhs.severity) && lhs.diagnosticID < rhs.diagnosticID)
    }

    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case "blocking":
            return 0
        case "warning":
            return 1
        default:
            return 2
        }
    }

    private static func runDiagnosticRecord(from row: RunDiagnosticRow) -> RunDiagnosticRecord {
        RunDiagnosticRecord(
            executionID: row.executionID,
            diagnosticID: row.diagnosticID,
            severity: row.severity,
            label: row.label,
            cta: row.cta,
            source: row.source,
            details: row.details
        )
    }

    private static func readJSONObject(atPath path: String, logger: Logger) -> [String: Any]? {
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            logger.debug("Lecture JSON run result ignorée pour run_diagnostics.", metadata: [
                "path": .string(fileURL.path),
                "error": .string(error.localizedDescription)
            ])
            return nil
        }
    }

    private static func extractErrorLabels(fromResultRoot root: [String: Any]) -> [String] {
        guard let errors = root["errors"] as? [[String: Any]] else {
            return []
        }
        return errors.compactMap { error in
            if let code = stringValue(from: error["code"]) {
                return code
            }
            return stringValue(from: error["message"])
        }
    }

    private static func stringValue(from rawValue: Any?) -> String? {
        guard let rawValue = rawValue as? String else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(from rawValue: Any?) -> Int? {
        if let int = rawValue as? Int {
            return int
        }
        if let number = rawValue as? NSNumber {
            return number.intValue
        }
        if let text = rawValue as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw Abort(.internalServerError, reason: "Échec de l'encodage JSON.")
        }
        return text
    }

    private static func decodeJSONValue<T: Decodable>(_ string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw Abort(.internalServerError, reason: "Charge JSON invalide.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
