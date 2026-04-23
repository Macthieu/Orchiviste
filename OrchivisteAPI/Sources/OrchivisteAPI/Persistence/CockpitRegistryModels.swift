import Fluent
import Foundation
import OrchivisteKitContracts

final class MuniAppRow: Model, @unchecked Sendable {
    static let schema = "muni_apps"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "app_id")
    var appID: String

    @Field(key: "display_name")
    var displayName: String

    @Field(key: "mission")
    var mission: String

    @OptionalField(key: "repository_path")
    var repositoryPath: String?

    @Field(key: "executable")
    var executable: String

    @OptionalField(key: "executable_path")
    var executablePath: String?

    @Field(key: "version")
    var version: String

    @Field(key: "integration_status")
    var integrationStatus: String

    @Field(key: "capabilities_json")
    var capabilitiesJSON: String

    @Field(key: "default_action")
    var defaultAction: String

    @Field(key: "default_parameters_json")
    var defaultParametersJSON: String

    @Field(key: "supports_dry_run")
    var supportsDryRun: Bool

    @Field(key: "destructive_requires_confirmation")
    var destructiveRequiresConfirmation: Bool

    @OptionalField(key: "confirmation_parameter")
    var confirmationParameter: String?

    @Field(key: "enabled")
    var enabled: Bool

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    init() { }

    init(descriptor: CockpitToolDescriptor, now: Date, capabilitiesJSON: String, defaultParametersJSON: String) {
        self.appID = descriptor.id
        self.displayName = descriptor.displayName
        self.mission = descriptor.mission
        self.repositoryPath = descriptor.repositoryPath
        self.executable = descriptor.executable
        self.executablePath = descriptor.executablePath
        self.version = descriptor.version
        self.integrationStatus = descriptor.integrationStatus
        self.capabilitiesJSON = capabilitiesJSON
        self.defaultAction = descriptor.defaultAction
        self.defaultParametersJSON = defaultParametersJSON
        self.supportsDryRun = descriptor.supportsDryRun
        self.destructiveRequiresConfirmation = descriptor.destructiveRequiresConfirmation
        self.confirmationParameter = descriptor.confirmationParameter
        self.enabled = descriptor.enabled
        self.createdAt = now
        self.updatedAt = now
    }
}

final class MuniAppActionRow: Model, @unchecked Sendable {
    static let schema = "muni_app_actions"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "app_id")
    var appID: String

    @Field(key: "action_key")
    var actionKey: String

    @Field(key: "action_label")
    var actionLabel: String

    @Field(key: "is_primary")
    var isPrimary: Bool

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    init() { }

    init(appID: String, actionKey: String, actionLabel: String, isPrimary: Bool, now: Date) {
        self.appID = appID
        self.actionKey = actionKey
        self.actionLabel = actionLabel
        self.isPrimary = isPrimary
        self.createdAt = now
        self.updatedAt = now
    }
}

final class RunProfileRow: Model, @unchecked Sendable {
    static let schema = "run_profiles"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "app_id")
    var appID: String

    @Field(key: "profile_key")
    var profileKey: String

    @Field(key: "display_name")
    var displayName: String

    @Field(key: "action_key")
    var actionKey: String

    @Field(key: "parameters_json")
    var parametersJSON: String

    @Field(key: "allow_destructive")
    var allowDestructive: Bool

    @Field(key: "expert_only")
    var expertOnly: Bool

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    init() { }

    init(
        appID: String,
        profileKey: String,
        displayName: String,
        actionKey: String,
        parametersJSON: String,
        allowDestructive: Bool,
        expertOnly: Bool,
        now: Date
    ) {
        self.appID = appID
        self.profileKey = profileKey
        self.displayName = displayName
        self.actionKey = actionKey
        self.parametersJSON = parametersJSON
        self.allowDestructive = allowDestructive
        self.expertOnly = expertOnly
        self.createdAt = now
        self.updatedAt = now
    }
}

final class RunHistoryRow: Model, @unchecked Sendable {
    static let schema = "run_history"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "execution_id")
    var executionID: String

    @Field(key: "request_id")
    var requestID: String

    @Field(key: "app_id")
    var appID: String

    @Field(key: "action")
    var action: String

    @Field(key: "status")
    var status: String

    @OptionalField(key: "summary")
    var summary: String?

    @Field(key: "command_json")
    var commandJSON: String

    @Field(key: "request_file")
    var requestFile: String

    @Field(key: "result_file")
    var resultFile: String

    @OptionalField(key: "exit_code")
    var exitCode: Int?

    @Field(key: "started_at")
    var startedAt: Date

    @Field(key: "finished_at")
    var finishedAt: Date

    @OptionalField(key: "dry_run")
    var dryRun: Bool?

    @Field(key: "error_codes_json")
    var errorCodesJSON: String

    @Field(key: "created_at")
    var createdAt: Date

    init() { }

    init(
        entry: CockpitHistoryEntry,
        appID: String,
        commandJSON: String,
        errorCodesJSON: String,
        createdAt: Date
    ) {
        self.executionID = entry.executionID
        self.requestID = entry.requestID
        self.appID = appID
        self.action = entry.action
        self.status = entry.status.rawValue
        self.summary = entry.summary
        self.commandJSON = commandJSON
        self.requestFile = entry.requestFile
        self.resultFile = entry.resultFile
        self.exitCode = entry.exitCode.map(Int.init)
        self.startedAt = Self.parseISO8601(entry.startedAt) ?? createdAt
        self.finishedAt = Self.parseISO8601(entry.finishedAt) ?? createdAt
        self.dryRun = entry.dryRun
        self.errorCodesJSON = errorCodesJSON
        self.createdAt = createdAt
    }

    private static func parseISO8601(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

final class RunDiagnosticRow: Model, @unchecked Sendable {
    static let schema = "run_diagnostics"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "execution_id")
    var executionID: String

    @Field(key: "diagnostic_id")
    var diagnosticID: String

    @Field(key: "severity")
    var severity: String

    @Field(key: "label")
    var label: String

    @OptionalField(key: "cta")
    var cta: String?

    @Field(key: "source")
    var source: String

    @OptionalField(key: "details")
    var details: String?

    @Field(key: "created_at")
    var createdAt: Date

    init() { }

    init(
        executionID: String,
        diagnosticID: String,
        severity: String,
        label: String,
        cta: String?,
        source: String,
        details: String?,
        createdAt: Date
    ) {
        self.executionID = executionID
        self.diagnosticID = diagnosticID
        self.severity = severity
        self.label = label
        self.cta = cta
        self.source = source
        self.details = details
        self.createdAt = createdAt
    }
}

struct MuniAppRecord: Sendable {
    let descriptor: CockpitToolDescriptor
    let actions: [MuniAppActionRecord]
    let profiles: [RunProfileRecord]
}

struct MuniAppActionRecord: Sendable {
    let appID: String
    let actionKey: String
    let actionLabel: String
    let isPrimary: Bool
}

struct RunProfileRecord: Sendable {
    let appID: String
    let profileKey: String
    let displayName: String
    let actionKey: String
    let parameters: [String: JSONValue]
    let allowDestructive: Bool
    let expertOnly: Bool
}

struct RunDiagnosticRecord: Sendable {
    let executionID: String
    let diagnosticID: String
    let severity: String
    let label: String
    let cta: String?
    let source: String
    let details: String?
}
