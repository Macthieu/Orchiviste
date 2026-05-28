import Foundation
import Vapor

func normalizedMuniEmployeeDirectoryPath(_ rawValue: String, label: String) throws -> String {
    guard let path = normalizedMuniEmployeePathInput(rawValue) else {
        throw Abort(.badRequest, reason: "Le dossier \(label) est requis.")
    }

    let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw Abort(.badRequest, reason: "Le dossier \(label) doit exister et être accessible.")
    }
    return url.path
}

func normalizedMuniEmployeePathInput(_ rawValue: String?) -> String? {
    guard let rawValue else {
        return nil
    }

    let unquoted = strippedMuniEmployeeWrappingQuotes(rawValue)
    guard !unquoted.isEmpty else {
        return nil
    }

    if let fileURLPath = muniEmployeePathFromFileURL(unquoted) {
        return fileURLPath
    }

    let expanded = (unquoted as NSString).expandingTildeInPath
    let normalized = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
    return normalized.isEmpty ? nil : normalized
}

private func strippedMuniEmployeeWrappingQuotes(_ rawValue: String) -> String {
    var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.count >= 2 {
        let first = trimmed.first
        let last = trimmed.last
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            break
        }
    }
    return trimmed
}

private func muniEmployeePathFromFileURL(_ rawValue: String) -> String? {
    guard rawValue.lowercased().hasPrefix("file://") else {
        return nil
    }

    if let url = URL(string: rawValue), url.isFileURL {
        return url.standardizedFileURL.path
    }

    let spaceEncoded = rawValue.replacingOccurrences(of: " ", with: "%20")
    if let url = URL(string: spaceEncoded), url.isFileURL {
        return url.standardizedFileURL.path
    }

    let pathPrefix = "file://"
    let remainder = String(rawValue.dropFirst(pathPrefix.count))
    let localPath: String
    if remainder.hasPrefix("/") {
        localPath = remainder
    } else if remainder.lowercased().hasPrefix("localhost/") {
        localPath = "/" + remainder.dropFirst("localhost/".count)
    } else {
        return nil
    }

    let decoded = localPath.removingPercentEncoding ?? localPath
    return URL(fileURLWithPath: decoded, isDirectory: true).standardizedFileURL.path
}
