import Foundation
import OrchivisteKitContracts
import Vapor

struct CockpitToolDescriptor: Codable, Content, Sendable {
    var id: String
    var displayName: String
    var mission: String
    var repositoryPath: String?
    var executable: String
    var executablePath: String?
    var version: String
    var integrationStatus: String
    var capabilities: [String]
    var defaultAction: String
    var defaultParameters: [String: JSONValue]
    var supportsDryRun: Bool
    var destructiveRequiresConfirmation: Bool
    var confirmationParameter: String?
    var enabled: Bool

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

struct CockpitConfig: Codable, Sendable {
    var schemaVersion: String
    var workspacePath: String
    var runtimeDirectory: String
    var requestsDirectory: String
    var resultsDirectory: String
    var historyFile: String
    var toolTimeoutSeconds: Int
    var tools: [CockpitToolDescriptor]

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

struct CockpitToolRuntimeDescriptor: Content, Sendable {
    var descriptor: CockpitToolDescriptor
    var isAvailable: Bool
    var resolvedExecutable: String?
    var availabilityReason: String

    enum CodingKeys: String, CodingKey {
        case descriptor
        case isAvailable = "is_available"
        case resolvedExecutable = "resolved_executable"
        case availabilityReason = "availability_reason"
    }
}

struct CockpitRunRequestPayload: Content, Sendable {
    var toolID: String
    var action: String?
    var correlationID: String?
    var workspacePath: String?
    var inputArtifacts: [ArtifactDescriptor]?
    var parameters: [String: JSONValue]?
    var allowDestructive: Bool?

    enum CodingKeys: String, CodingKey {
        case toolID = "tool_id"
        case action
        case correlationID = "correlation_id"
        case workspacePath = "workspace_path"
        case inputArtifacts = "input_artifacts"
        case parameters
        case allowDestructive = "allow_destructive"
    }
}

struct CockpitRunResponsePayload: Content, Sendable {
    var executionID: String
    var requestID: String
    var toolID: String
    var action: String
    var status: ToolStatus
    var summary: String?
    var command: [String]
    var requestFile: String
    var resultFile: String
    var historyFile: String
    var exitCode: Int32?
    var startedAt: String
    var finishedAt: String
    var errors: [ToolError]

    enum CodingKeys: String, CodingKey {
        case executionID = "execution_id"
        case requestID = "request_id"
        case toolID = "tool_id"
        case action
        case status
        case summary
        case command
        case requestFile = "request_file"
        case resultFile = "result_file"
        case historyFile = "history_file"
        case exitCode = "exit_code"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case errors
    }
}

struct CockpitHistoryEntry: Codable, Content, Sendable {
    var executionID: String
    var requestID: String
    var toolID: String
    var action: String
    var status: ToolStatus
    var summary: String?
    var command: [String]
    var requestFile: String
    var resultFile: String
    var exitCode: Int32?
    var startedAt: String
    var finishedAt: String
    var dryRun: Bool?
    var errorCodes: [String]

    enum CodingKeys: String, CodingKey {
        case executionID = "execution_id"
        case requestID = "request_id"
        case toolID = "tool_id"
        case action
        case status
        case summary
        case command
        case requestFile = "request_file"
        case resultFile = "result_file"
        case exitCode = "exit_code"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case dryRun = "dry_run"
        case errorCodes = "error_codes"
    }
}

struct CockpitHistoryResponse: Content, Sendable {
    var historyFile: String
    var entries: [CockpitHistoryEntry]

    enum CodingKeys: String, CodingKey {
        case historyFile = "history_file"
        case entries
    }
}

struct CockpitConfigSummary: Content, Sendable {
    var workspacePath: String
    var runtimeDirectory: String
    var requestsDirectory: String
    var resultsDirectory: String
    var historyFile: String
    var toolTimeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case workspacePath = "workspace_path"
        case runtimeDirectory = "runtime_directory"
        case requestsDirectory = "requests_directory"
        case resultsDirectory = "results_directory"
        case historyFile = "history_file"
        case toolTimeoutSeconds = "tool_timeout_seconds"
    }
}

struct CockpitLaunchRequest: Sendable {
    var toolID: String
    var action: String?
    var correlationID: String?
    var workspacePath: String?
    var inputArtifacts: [ArtifactDescriptor]
    var parameters: [String: JSONValue]
    var allowDestructive: Bool
}

struct CockpitLaunchOutcome: Sendable {
    var executionID: String
    var request: ToolRequest
    var result: ToolResult
    var command: [String]
    var requestFile: URL
    var resultFile: URL
    var historyFile: URL
    var exitCode: Int32?
}
