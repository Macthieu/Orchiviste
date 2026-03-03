import OrchivisteSharedKit
import Vapor

func collectNamingLearningSamples(
    request: RuleLearningRequest,
    logger: Logger
) throws -> [LearningDocumentSample] {
    let folderURL = URL(fileURLWithPath: request.folder_path, isDirectory: true).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw Abort(.badRequest, reason: "Le dossier source est introuvable.")
    }

    let allowedExtensions = normalizeNamingLearningExtensions(request.extensions)
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

func normalizeNamingLearningExtensions(_ raw: [String]?) -> Set<String> {
    let normalized = (raw ?? DocumentTextExtractor.supportedExtensions()).map {
        $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
            .lowercased()
    }.filter { DocumentTextExtractor.supportedExtensions().contains($0) }
    return Set(normalized.isEmpty ? DocumentTextExtractor.supportedExtensions() : normalized)
}
