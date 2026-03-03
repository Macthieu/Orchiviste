import Foundation
import OrchivisteSharedKit
import Yams

public enum ThesaurusImportError: Error {
    case unsupportedFormat
    case invalidPayload(String)
}

public final class JSONThesaurusImporter: ThesaurusImporting {
    public let format = "json"

    public init() {}

    public func parse(data: Data, sourceName: String?) throws -> NamingThesaurus {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(NamingThesaurus.self, from: data) {
            return direct
        }
        if let wrapped = try? decoder.decode(ImportedPayload.self, from: data) {
            return wrapped.thesaurus
        }
        throw ThesaurusImportError.invalidPayload("JSON de thésaurus invalide.")
    }
}

public final class YAMLThesaurusImporter: ThesaurusImporting {
    public let format = "yaml"

    public init() {}

    public func parse(data: Data, sourceName: String?) throws -> NamingThesaurus {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ThesaurusImportError.invalidPayload("YAML illisible.")
        }
        let decoder = YAMLDecoder()
        if let direct = try? decoder.decode(NamingThesaurus.self, from: text) {
            return direct
        }
        if let wrapped = try? decoder.decode(ImportedPayload.self, from: text) {
            return wrapped.thesaurus
        }
        throw ThesaurusImportError.invalidPayload("YAML de thésaurus invalide.")
    }
}

public struct ThesaurusMergeService {
    public init() {}

    public func previewMerge(
        target: NamingThesaurus?,
        imported: NamingThesaurus,
        strategy: NamingImportStrategy
    ) -> ThesaurusMergePreview {
        let targetID = target?.thesaurus_id ?? imported.thesaurus_id
        switch strategy {
        case .replace:
            let merged = NamingThesaurus(
                thesaurus_id: targetID,
                version: imported.version,
                description: imported.description,
                trace: imported.trace,
                entries: uniqueEntries(imported.entries),
                stopwords: uniqueStrings(imported.stopwords),
                preserve_terms: uniqueStrings(imported.preserve_terms)
            )
            return ThesaurusMergePreview(
                strategy: strategy,
                target_thesaurus_id: targetID,
                merged: merged,
                conflicts: [],
                warnings: []
            )
        case .draft:
            return ThesaurusMergePreview(
                strategy: strategy,
                target_thesaurus_id: targetID,
                merged: imported,
                conflicts: detectConflicts(existing: target, incoming: imported),
                warnings: ["Import conservé comme brouillon tant qu'il n'est pas confirmé."]
            )
        case .merge:
            let conflicts = detectConflicts(existing: target, incoming: imported)
            var mergedEntries = target?.entries ?? []
            let existingCanonical = Set(mergedEntries.map { normalizedSearchText($0.canonical) })
            for entry in imported.entries where !existingCanonical.contains(normalizedSearchText(entry.canonical)) {
                mergedEntries.append(entry)
            }
            let merged = NamingThesaurus(
                thesaurus_id: targetID,
                version: imported.version,
                description: imported.description ?? target?.description,
                trace: imported.trace ?? target?.trace,
                entries: uniqueEntries(mergedEntries),
                stopwords: uniqueStrings((target?.stopwords ?? []) + imported.stopwords),
                preserve_terms: uniqueStrings((target?.preserve_terms ?? []) + imported.preserve_terms)
            )
            return ThesaurusMergePreview(
                strategy: strategy,
                target_thesaurus_id: targetID,
                merged: merged,
                conflicts: conflicts,
                warnings: conflicts.isEmpty ? [] : ["Des conflits doivent être revus avant validation finale."]
            )
        }
    }

    private func detectConflicts(existing: NamingThesaurus?, incoming: NamingThesaurus) -> [ThesaurusConflict] {
        guard let existing else { return [] }
        var conflicts: [ThesaurusConflict] = []

        let aliasMap = existing.entries.reduce(into: [String: String]()) { partial, entry in
            partial[normalizedSearchText(entry.canonical)] = entry.canonical
            for alias in entry.aliases {
                partial[normalizedSearchText(alias)] = entry.canonical
            }
        }

        for entry in incoming.entries {
            let normalizedCanonical = normalizedSearchText(entry.canonical)
            if let current = aliasMap[normalizedCanonical], current != entry.canonical {
                conflicts.append(.init(
                    kind: .canonicalMismatch,
                    alias: entry.canonical,
                    existing_canonical: current,
                    incoming_canonical: entry.canonical,
                    message: "Le terme canonique \(entry.canonical) pointe déjà vers \(current)."
                ))
            }
            for alias in entry.aliases {
                let normalizedAlias = normalizedSearchText(alias)
                if let current = aliasMap[normalizedAlias], current != entry.canonical {
                    conflicts.append(.init(
                        kind: .aliasAlreadyExists,
                        alias: alias,
                        existing_canonical: current,
                        incoming_canonical: entry.canonical,
                        message: "L'alias \(alias) existe déjà pour \(current)."
                    ))
                }
            }
        }
        return conflicts
    }

    private func uniqueEntries(_ entries: [NamingThesaurusEntry]) -> [NamingThesaurusEntry] {
        var seen = Set<String>()
        var result: [NamingThesaurusEntry] = []
        for entry in entries {
            let key = normalizedSearchText(entry.canonical)
            if seen.insert(key).inserted {
                result.append(
                    NamingThesaurusEntry(
                        canonical: entry.canonical,
                        aliases: uniqueStrings(entry.aliases),
                        kind: entry.kind,
                        normalized_output: entry.normalized_output,
                        preserve_terms: uniqueStrings(entry.preserve_terms ?? []),
                        notes: entry.notes
                    )
                )
            }
        }
        return result
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = normalizedSearchText(value)
            if !key.isEmpty, seen.insert(key).inserted {
                result.append(value)
            }
        }
        return result
    }
}

public final class ThesaurusImportService {
    private let importers: [String: ThesaurusImporting]
    private let mergeService: ThesaurusMergeService

    public init(
        importers: [ThesaurusImporting] = [JSONThesaurusImporter(), YAMLThesaurusImporter()],
        mergeService: ThesaurusMergeService = .init()
    ) {
        self.importers = Dictionary(uniqueKeysWithValues: importers.map { ($0.format, $0) })
        self.mergeService = mergeService
    }

    public func preview(
        request: ThesaurusImportPreviewRequest,
        existing: NamingThesaurus?
    ) throws -> ImportedThesaurusDraft {
        let strategy = request.strategy ?? .draft
        let format = normalizedFormat(request.format, sourceName: request.source_name)
        guard let importer = importers[format] else {
            throw ThesaurusImportError.unsupportedFormat
        }
        let imported = try importer.parse(data: Data(request.raw_text.utf8), sourceName: request.source_name)
        let preview = mergeService.previewMerge(target: existing, imported: imported, strategy: strategy)
        return ImportedThesaurusDraft(
            draft_id: "draft-thesaurus-\(timestampLabel())",
            created_at: Date(),
            source_name: request.source_name ?? "thesaurus.\(format)",
            format: format,
            imported: imported,
            preview: preview
        )
    }

    private func normalizedFormat(_ format: String?, sourceName: String?) -> String {
        if let format = format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !format.isEmpty {
            return format == "yml" ? "yaml" : format
        }
        let ext = URL(fileURLWithPath: sourceName ?? "").pathExtension.lowercased()
        return ext == "yml" ? "yaml" : (ext.isEmpty ? "json" : ext)
    }
}

private struct ImportedPayload: Codable {
    let thesaurus: NamingThesaurus
}
