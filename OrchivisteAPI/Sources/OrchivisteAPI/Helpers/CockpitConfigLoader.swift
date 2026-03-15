import Foundation
import OrchivisteKitContracts
import Vapor

private struct PartialCockpitToolDescriptor: Codable {
    var id: String?
    var displayName: String?
    var mission: String?
    var repositoryPath: String?
    var executable: String?
    var executablePath: String?
    var version: String?
    var integrationStatus: String?
    var capabilities: [String]?
    var defaultAction: String?
    var defaultParameters: [String: JSONValue]?
    var supportsDryRun: Bool?
    var destructiveRequiresConfirmation: Bool?
    var confirmationParameter: String?
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case mission
        case repositoryPath = "repository_path"
        case executable
        case executablePath = "executable_path"
        case version
        case integrationStatus = "integration_status"
        case capabilities
        case defaultAction = "default_action"
        case defaultParameters = "default_parameters"
        case supportsDryRun = "supports_dry_run"
        case destructiveRequiresConfirmation = "destructive_requires_confirmation"
        case confirmationParameter = "confirmation_parameter"
        case enabled
    }
}

private struct PartialCockpitConfig: Codable {
    var schemaVersion: String?
    var workspacePath: String?
    var runtimeDirectory: String?
    var requestsDirectory: String?
    var resultsDirectory: String?
    var historyFile: String?
    var toolTimeoutSeconds: Int?
    var tools: [PartialCockpitToolDescriptor]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case workspacePath = "workspace_path"
        case runtimeDirectory = "runtime_directory"
        case requestsDirectory = "requests_directory"
        case resultsDirectory = "results_directory"
        case historyFile = "history_file"
        case toolTimeoutSeconds = "tool_timeout_seconds"
        case tools
    }
}

enum CockpitConfigLoader {
    static func load(logger: Logger? = nil) -> CockpitConfig {
        var config = defaultConfig()
        let configURL = configFileURL()

        if FileManager.default.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let partial = try JSONDecoder().decode(PartialCockpitConfig.self, from: data)
                config = merge(partial: partial, into: config)
            } catch {
                logger?.warning("Impossible de charger configs/cockpit/config.json, valeurs par défaut conservées.", metadata: [
                    "path": .string(configURL.path),
                    "error": .string(error.localizedDescription)
                ])
            }
        }

        let env = ProcessInfo.processInfo.environment
        if let value = nonEmpty(env["ORCHIVISTE_WORKSPACE_PATH"]) {
            config.workspacePath = value
        }
        if let value = nonEmpty(env["ORCHIVISTE_COCKPIT_RUNTIME_DIR"]) {
            config.runtimeDirectory = value
        }
        if let value = nonEmpty(env["ORCHIVISTE_COCKPIT_REQUESTS_DIR"]) {
            config.requestsDirectory = value
        }
        if let value = nonEmpty(env["ORCHIVISTE_COCKPIT_RESULTS_DIR"]) {
            config.resultsDirectory = value
        }
        if let value = nonEmpty(env["ORCHIVISTE_COCKPIT_HISTORY_FILE"]) {
            config.historyFile = value
        }
        if let value = nonEmpty(env["ORCHIVISTE_COCKPIT_TIMEOUT_SECONDS"]), let seconds = Int(value), seconds > 0 {
            config.toolTimeoutSeconds = seconds
        }

        normalizePaths(&config)
        return config
    }

    static func configFileURL() -> URL {
        if let env = Environment.get("ORCHIVISTE_COCKPIT_CONFIG_FILE"), !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return ConfigLoader.baseDir().appendingPathComponent("cockpit/config.json")
    }

    static func defaultConfig() -> CockpitConfig {
        let workspacePath = defaultWorkspacePath()
        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-cockpit", isDirectory: true)
            .path

        return CockpitConfig(
            schemaVersion: "1.0",
            workspacePath: workspacePath,
            runtimeDirectory: runtimeDirectory,
            requestsDirectory: "requests",
            resultsDirectory: "results",
            historyFile: "history.jsonl",
            toolTimeoutSeconds: 300,
            tools: defaultTools(workspacePath: workspacePath)
        )
    }

    private static func merge(partial: PartialCockpitConfig, into base: CockpitConfig) -> CockpitConfig {
        var config = base

        if let value = nonEmpty(partial.schemaVersion) {
            config.schemaVersion = value
        }
        if let value = nonEmpty(partial.workspacePath) {
            config.workspacePath = value
        }
        if let value = nonEmpty(partial.runtimeDirectory) {
            config.runtimeDirectory = value
        }
        if let value = nonEmpty(partial.requestsDirectory) {
            config.requestsDirectory = value
        }
        if let value = nonEmpty(partial.resultsDirectory) {
            config.resultsDirectory = value
        }
        if let value = nonEmpty(partial.historyFile) {
            config.historyFile = value
        }
        if let value = partial.toolTimeoutSeconds, value > 0 {
            config.toolTimeoutSeconds = value
        }

        if let partialTools = partial.tools {
            let merged = partialTools.compactMap { partialTool -> CockpitToolDescriptor? in
                if let id = partialTool.id,
                   let existing = config.tools.first(where: { $0.id == id }) {
                    return mergeTool(partial: partialTool, into: existing)
                }
                return buildToolFromScratch(partial: partialTool)
            }
            if !merged.isEmpty {
                config.tools = merged
            }
        }

        return config
    }

    private static func mergeTool(partial: PartialCockpitToolDescriptor, into base: CockpitToolDescriptor) -> CockpitToolDescriptor {
        CockpitToolDescriptor(
            id: nonEmpty(partial.id) ?? base.id,
            displayName: nonEmpty(partial.displayName) ?? base.displayName,
            mission: nonEmpty(partial.mission) ?? base.mission,
            repositoryPath: nonEmpty(partial.repositoryPath) ?? base.repositoryPath,
            executable: nonEmpty(partial.executable) ?? base.executable,
            executablePath: nonEmpty(partial.executablePath) ?? base.executablePath,
            version: nonEmpty(partial.version) ?? base.version,
            integrationStatus: nonEmpty(partial.integrationStatus) ?? base.integrationStatus,
            capabilities: partial.capabilities ?? base.capabilities,
            defaultAction: nonEmpty(partial.defaultAction) ?? base.defaultAction,
            defaultParameters: partial.defaultParameters ?? base.defaultParameters,
            supportsDryRun: partial.supportsDryRun ?? base.supportsDryRun,
            destructiveRequiresConfirmation: partial.destructiveRequiresConfirmation ?? base.destructiveRequiresConfirmation,
            confirmationParameter: nonEmpty(partial.confirmationParameter) ?? base.confirmationParameter,
            enabled: partial.enabled ?? base.enabled
        )
    }

    private static func buildToolFromScratch(partial: PartialCockpitToolDescriptor) -> CockpitToolDescriptor? {
        guard let id = nonEmpty(partial.id),
              let displayName = nonEmpty(partial.displayName),
              let mission = nonEmpty(partial.mission),
              let executable = nonEmpty(partial.executable) else {
            return nil
        }

        return CockpitToolDescriptor(
            id: id,
            displayName: displayName,
            mission: mission,
            repositoryPath: nonEmpty(partial.repositoryPath),
            executable: executable,
            executablePath: nonEmpty(partial.executablePath),
            version: nonEmpty(partial.version) ?? "0.0.0",
            integrationStatus: nonEmpty(partial.integrationStatus) ?? "unknown",
            capabilities: partial.capabilities ?? [],
            defaultAction: nonEmpty(partial.defaultAction) ?? "run",
            defaultParameters: partial.defaultParameters ?? [:],
            supportsDryRun: partial.supportsDryRun ?? false,
            destructiveRequiresConfirmation: partial.destructiveRequiresConfirmation ?? false,
            confirmationParameter: nonEmpty(partial.confirmationParameter),
            enabled: partial.enabled ?? true
        )
    }

    private static func normalizePaths(_ config: inout CockpitConfig) {
        let configBaseURL = ConfigLoader.baseDir()
        config.workspacePath = normalizedDirectoryURL(from: config.workspacePath, relativeTo: configBaseURL).path

        let runtimeURL = normalizedDirectoryURL(from: config.runtimeDirectory, relativeTo: configBaseURL)
        config.runtimeDirectory = runtimeURL.path

        config.requestsDirectory = normalizedDirectoryURL(
            from: config.requestsDirectory,
            relativeTo: runtimeURL
        ).path
        config.resultsDirectory = normalizedDirectoryURL(
            from: config.resultsDirectory,
            relativeTo: runtimeURL
        ).path

        let historyURL: URL
        if (config.historyFile as NSString).isAbsolutePath {
            historyURL = URL(fileURLWithPath: config.historyFile)
        } else {
            historyURL = runtimeURL.appendingPathComponent(config.historyFile)
        }
        config.historyFile = historyURL.path

        config.tools = config.tools.map { tool in
            var mutable = tool
            if let repositoryPath = nonEmpty(tool.repositoryPath) {
                mutable.repositoryPath = normalizedDirectoryURL(
                    from: repositoryPath,
                    relativeTo: URL(fileURLWithPath: config.workspacePath)
                ).path
            }
            if let executablePath = nonEmpty(tool.executablePath) {
                mutable.executablePath = normalizedPathURL(
                    from: executablePath,
                    relativeTo: URL(fileURLWithPath: config.workspacePath)
                ).path
            }
            return mutable
        }
    }

    private static func normalizedDirectoryURL(from raw: String, relativeTo base: URL?) -> URL {
        normalizedPathURL(from: raw, relativeTo: base)
    }

    private static func normalizedPathURL(from raw: String, relativeTo base: URL?) -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        let candidate = URL(fileURLWithPath: expanded)
        if (expanded as NSString).isAbsolutePath {
            return candidate.standardizedFileURL
        }
        if let base {
            return base.appendingPathComponent(expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    private static func defaultWorkspacePath() -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let packageRoot = sourceURL
            .deletingLastPathComponent() // CockpitConfigLoader.swift
            .deletingLastPathComponent() // Helpers
            .deletingLastPathComponent() // OrchivisteAPI
            .deletingLastPathComponent() // Sources

        let orchivisteRoot = packageRoot.deletingLastPathComponent()
        let workspaceRoot = orchivisteRoot.deletingLastPathComponent()

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: workspaceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return workspaceRoot.path
        }
        return orchivisteRoot.path
    }

    private static func defaultTools(workspacePath: String) -> [CockpitToolDescriptor] {
        func repo(_ name: String) -> String {
            URL(fileURLWithPath: workspacePath, isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
                .path
        }

        return [
            CockpitToolDescriptor(
                id: "MuniRenommage",
                displayName: "MuniRenommage",
                mission: "Renommage documentaire selon presets validés.",
                repositoryPath: repo("MuniRenommage"),
                executable: "munirename-cli",
                executablePath: nil,
                version: "0.3.0",
                integrationStatus: "ready",
                capabilities: ["preview", "apply", "validate-preset", "canonical-run"],
                defaultAction: "preview",
                defaultParameters: [
                    "dry_run": .bool(true),
                    "confirm_apply": .bool(false),
                    "recursive": .bool(false),
                    "include_hidden": .bool(false)
                ],
                supportsDryRun: true,
                destructiveRequiresConfirmation: true,
                confirmationParameter: "confirm_apply",
                enabled: true
            ),
            CockpitToolDescriptor(
                id: "MuniConversion",
                displayName: "MuniConversion",
                mission: "Conversion documentaire multi-formats avec garde-fous.",
                repositoryPath: repo("MuniConversion"),
                executable: "municonversion-cli",
                executablePath: nil,
                version: "1.3.0",
                integrationStatus: "ready",
                capabilities: ["analyze", "convert", "canonical-run"],
                defaultAction: "analyze",
                defaultParameters: [
                    "dry_run": .bool(true),
                    "confirm_convert": .bool(false),
                    "include_subdirectories": .bool(false),
                    "ignore_hidden_files": .bool(true),
                    "preserve_relative_structure": .bool(false),
                    "collision_policy": .string("skip_existing")
                ],
                supportsDryRun: true,
                destructiveRequiresConfirmation: true,
                confirmationParameter: "confirm_convert",
                enabled: true
            ),
            CockpitToolDescriptor(
                id: "MuniMiseEnForme",
                displayName: "MuniMiseEnForme",
                mission: "Normalisation et mise en forme documentaire.",
                repositoryPath: repo("MuniMiseEnForme"),
                executable: "muni-mise-en-forme",
                executablePath: nil,
                version: "0.2.0-alpha",
                integrationStatus: "alpha",
                capabilities: ["run", "analyze", "worker", "canonical-run"],
                defaultAction: "analyze",
                defaultParameters: [
                    "structuring_mode": .string("foundation_models")
                ],
                supportsDryRun: false,
                destructiveRequiresConfirmation: false,
                confirmationParameter: nil,
                enabled: true
            ),
            CockpitToolDescriptor(
                id: "MuniAnalyse",
                displayName: "MuniAnalyse",
                mission: "Analyse textuelle documentaire deterministe (V1 texte-only, sans OCR).",
                repositoryPath: repo("MuniAnalyse"),
                executable: "muni-analyse-cli",
                executablePath: nil,
                version: "0.2.0",
                integrationStatus: "active",
                capabilities: ["run", "analyze", "canonical-run", "text-analysis-v1"],
                defaultAction: "analyze",
                defaultParameters: [
                    "text": .string("Compte rendu municipal a analyser pour un controle documentaire initial.")
                ],
                supportsDryRun: false,
                destructiveRequiresConfirmation: false,
                confirmationParameter: nil,
                enabled: true
            ),
            CockpitToolDescriptor(
                id: "MuniMetadonnees",
                displayName: "MuniMetadonnees",
                mission: "Enrichissement metadata deterministe (mots-cles, resume, titre suggere) avec seed MuniAnalyse.",
                repositoryPath: repo("MuniMetadonnees"),
                executable: "muni-metadonnees-cli",
                executablePath: nil,
                version: "0.2.0",
                integrationStatus: "active",
                capabilities: ["run", "enrich", "canonical-run", "metadata-enrichment-v1", "analysis-seed-v1"],
                defaultAction: "enrich",
                defaultParameters: [
                    "text": .string("Compte rendu municipal a enrichir pour indexation documentaire."),
                    "max_keywords": .number(10),
                    "summary_sentence_count": .number(2)
                ],
                supportsDryRun: false,
                destructiveRequiresConfirmation: false,
                confirmationParameter: nil,
                enabled: true
            ),
            CockpitToolDescriptor(
                id: "MuniPreclassement",
                displayName: "MuniPreclassement",
                mission: "Preclassement deterministe par profil municipal V1, avec seed metadata quand disponible.",
                repositoryPath: repo("MuniPreclassement"),
                executable: "muni-preclassement-cli",
                executablePath: nil,
                version: "0.2.0",
                integrationStatus: "active",
                capabilities: ["run", "preclassify", "canonical-run", "classification-v1", "metadata-seed-v1"],
                defaultAction: "preclassify",
                defaultParameters: [
                    "text": .string("Compte rendu municipal a preclasser pour orientation du plan de classification."),
                    "max_suggestions": .number(3)
                ],
                supportsDryRun: false,
                destructiveRequiresConfirmation: false,
                confirmationParameter: nil,
                enabled: true
            ),
            CockpitToolDescriptor(
                id: "MuniControle",
                displayName: "MuniControle",
                mission: "Contrôle qualité documentaire (squelette V1).",
                repositoryPath: repo("MuniControle"),
                executable: "muni-controle-cli",
                executablePath: nil,
                version: "0.1.0",
                integrationStatus: "scaffold",
                capabilities: ["run", "canonical-run"],
                defaultAction: "run",
                defaultParameters: [:],
                supportsDryRun: false,
                destructiveRequiresConfirmation: false,
                confirmationParameter: nil,
                enabled: true
            )
        ]
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
