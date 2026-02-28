import Foundation
import Vapor
#if canImport(PDFKit) && canImport(AppKit)
import PDFKit
import AppKit
#endif

enum PreviewRenderer {
    static func makePreview(for job: JobRecord, logger: Logger) -> PreviewRecord {
        guard job.source.kind.lowercased() == "local",
              let localFileURL = resolveLocalFileURL(raw: job.fileURL),
              FileManager.default.fileExists(atPath: localFileURL.path) else {
            return placeholder(jobId: job.id)
        }

        let ext = localFileURL.pathExtension.lowercased()
        if ext == "pdf" {
            return makePDFPreview(fileURL: localFileURL, jobId: job.id, logger: logger)
        }

        guard let extracted = DocumentTextExtractor.extract(fileURL: localFileURL, logger: logger) else {
            return placeholder(jobId: job.id)
        }
        defer {
            cleanupTemporaryArtifacts(extracted.temporaryArtifacts, logger: logger)
        }

        if let previewPDFURL = extracted.previewPDFURL {
            let pdfPreview = makePDFPreview(fileURL: previewPDFURL, jobId: job.id, logger: logger)
            return mergePreview(pdfPreview, withExtractedPages: extracted.pages)
        }

        if extracted.kind == "image" {
            return makeImagePreview(
                fileURL: localFileURL,
                jobId: job.id,
                extractedPages: extracted.pages,
                logger: logger
            )
        }

        return makeTextOnlyPreview(jobId: job.id, pages: extracted.pages, logger: logger)
    }

    private static func makePDFPreview(fileURL: URL, jobId: UUID, logger: Logger) -> PreviewRecord {
        #if canImport(PDFKit) && canImport(AppKit)
        guard let document = PDFDocument(url: fileURL) else {
            return placeholder(jobId: jobId)
        }

        var textPages: [Int: String] = [:]
        var imagesByPage: [Int: Data] = [:]

        let pageCount = max(document.pageCount, 1)
        for pageIndex in 0..<pageCount {
            let pageNumber = pageIndex + 1
            guard let page = document.page(at: pageIndex) else {
                textPages[pageNumber] = PreviewHelper.defaultText(page: pageNumber)
                imagesByPage[pageNumber] = PreviewHelper.placeholderJPEG()
                continue
            }

            let pageBounds = page.bounds(for: .mediaBox)
            let safeWidth = max(1, pageBounds.width)
            let ratio = max(0.2, pageBounds.height / safeWidth)
            let width: CGFloat = 1200
            let size = NSSize(width: width, height: max(400, width * ratio))
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            imagesByPage[pageNumber] = jpegData(from: thumbnail) ?? PreviewHelper.placeholderJPEG()

            if let extracted = page.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !extracted.isEmpty {
                textPages[pageNumber] = extracted
            } else {
                textPages[pageNumber] = PreviewHelper.defaultText(page: pageNumber)
            }
        }

        logger.info("Aperçu genere.", metadata: ["job_id": .string(jobId.uuidString), "pages": .stringConvertible(pageCount)])
        return PreviewRecord(
            jobId: jobId,
            pages: pageCount,
            textPages: textPages,
            imagesByPage: imagesByPage,
            createdAt: Date()
        )
        #else
        if let external = makeExternalPreview(fileURL: fileURL, jobId: jobId, logger: logger) {
            return external
        }
        logger.warning("Rendu PDF indisponible sur cette plateforme et extraction texte externe indisponible.")
        return placeholder(jobId: jobId)
        #endif
    }

    static func placeholder(jobId: UUID) -> PreviewRecord {
        PreviewRecord(
            jobId: jobId,
            pages: 1,
            textPages: [1: PreviewHelper.defaultText(page: 1)],
            imagesByPage: [1: PreviewHelper.placeholderJPEG()],
            createdAt: Date()
        )
    }

    private static func resolveLocalFileURL(raw: String) -> URL? {
        if let url = URL(string: raw), url.isFileURL {
            return url
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return current.appendingPathComponent(raw)
    }

    private static func mergePreview(
        _ preview: PreviewRecord,
        withExtractedPages pages: [String]
    ) -> PreviewRecord {
        guard !pages.isEmpty else {
            return preview
        }

        var merged = preview
        merged.pages = max(preview.pages, pages.count)
        for (index, pageText) in pages.enumerated() {
            let pageNumber = index + 1
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                merged.textPages[pageNumber] = trimmed
            }
            if merged.imagesByPage[pageNumber] == nil {
                merged.imagesByPage[pageNumber] = PreviewHelper.placeholderJPEG()
            }
        }
        return merged
    }

    private static func makeTextOnlyPreview(jobId: UUID, pages: [String], logger: Logger) -> PreviewRecord {
        let safePages = pages.isEmpty ? [PreviewHelper.defaultText(page: 1)] : pages
        var textPages: [Int: String] = [:]
        var imagesByPage: [Int: Data] = [:]

        for (index, pageText) in safePages.enumerated() {
            let page = index + 1
            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            textPages[page] = trimmed.isEmpty ? PreviewHelper.defaultText(page: page) : trimmed
            imagesByPage[page] = PreviewHelper.placeholderJPEG()
        }

        logger.info("Aperçu texte genere sans rendu natif.", metadata: [
            "job_id": .string(jobId.uuidString),
            "pages": .stringConvertible(safePages.count)
        ])
        return PreviewRecord(
            jobId: jobId,
            pages: safePages.count,
            textPages: textPages,
            imagesByPage: imagesByPage,
            createdAt: Date()
        )
    }

    private static func makeImagePreview(
        fileURL: URL,
        jobId: UUID,
        extractedPages: [String],
        logger: Logger
    ) -> PreviewRecord {
        let imageData = loadImageJPEGData(fileURL: fileURL)
        let text = extractedPages.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? PreviewHelper.defaultText(page: 1)

        logger.info("Aperçu image genere.", metadata: [
            "job_id": .string(jobId.uuidString),
            "path": .string(fileURL.path)
        ])
        return PreviewRecord(
            jobId: jobId,
            pages: 1,
            textPages: [1: text.isEmpty ? PreviewHelper.defaultText(page: 1) : text],
            imagesByPage: [1: imageData ?? PreviewHelper.placeholderJPEG()],
            createdAt: Date()
        )
    }

    private static func cleanupTemporaryArtifacts(_ urls: [URL], logger: Logger) {
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.debug("Nettoyage d'un artefact temporaire ignore.", metadata: [
                    "path": .string(url.path),
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }

    private static func makeExternalPreview(
        fileURL: URL,
        jobId: UUID,
        logger: Logger
    ) -> PreviewRecord? {
        let directText = extractTextWithPdftotext(fileURL: fileURL, logger: logger)
        let directPages = splitTextByPages(directText ?? "")
        var selectedPages = directPages
        var selectedSource = "pdftotext"
        let directChars = meaningfulCharactersCount(directPages)

        if shouldTryOCRFallback(directChars: directChars) {
            if let ocrPages = extractTextWithTesseract(fileURL: fileURL, logger: logger) {
                let ocrChars = meaningfulCharactersCount(ocrPages)
                if ocrChars > directChars {
                    selectedPages = ocrPages
                    selectedSource = "tesseract"
                }
            }
        }

        guard !selectedPages.isEmpty else {
            return nil
        }

        let renderedImages = extractImagesWithPdftoppm(fileURL: fileURL, logger: logger)
        var textPages: [Int: String] = [:]
        var imagesByPage: [Int: Data] = [:]
        let totalPages = max(selectedPages.count, renderedImages.count, 1)
        for index in 0..<totalPages {
            let page = index + 1
            let text = index < selectedPages.count ? selectedPages[index] : ""
            textPages[page] = text.isEmpty ? PreviewHelper.defaultText(page: page) : text
            if index < renderedImages.count {
                imagesByPage[page] = renderedImages[index]
            } else {
                imagesByPage[page] = PreviewHelper.placeholderJPEG()
            }
        }

        logger.info("Aperçu texte externe généré.", metadata: [
            "job_id": .string(jobId.uuidString),
            "pages": .stringConvertible(totalPages),
            "source": .string(selectedSource)
        ])
        return PreviewRecord(
            jobId: jobId,
            pages: totalPages,
            textPages: textPages,
            imagesByPage: imagesByPage,
            createdAt: Date()
        )
    }

    private static func extractTextWithPdftotext(fileURL: URL, logger: Logger) -> String? {
        let result = runCommand(
            executable: "pdftotext",
            arguments: ["-enc", "UTF-8", "-layout", fileURL.path, "-"]
        )
        if result.exitCode != 0 {
            logger.warning("pdftotext non disponible ou en échec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(result.stderr)
            ])
            return nil
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func splitTextByPages(_ raw: String) -> [String] {
        let wholeTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if wholeTrimmed.isEmpty {
            return []
        }
        let rawPages = raw.components(separatedBy: "\u{0C}")
        let trimmed = rawPages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let lastIndex = trimmed.lastIndex(where: { !$0.isEmpty }) ?? -1
        guard lastIndex >= 0 else {
            return [wholeTrimmed]
        }
        return Array(trimmed.prefix(lastIndex + 1))
    }

    private static func meaningfulCharactersCount(_ pages: [String]) -> Int {
        pages
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .count
    }

    private static func shouldTryOCRFallback(directChars: Int) -> Bool {
        guard ocrEnabled() else {
            return false
        }
        return directChars < ocrMinTextChars()
    }

    private static func ocrEnabled() -> Bool {
        let raw = (Environment.get("ORCHIVISTE_OCR_ENABLED") ?? "1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !(raw == "0" || raw == "false" || raw == "no" || raw == "off")
    }

    private static func ocrMinTextChars() -> Int {
        max(20, Int(Environment.get("ORCHIVISTE_OCR_MIN_TEXT_CHARS") ?? "140") ?? 140)
    }

    private static func ocrMaxPages() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_OCR_MAX_PAGES") ?? "12") ?? 12
        return max(1, min(200, parsed))
    }

    private static func previewMaxPages() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_PREVIEW_MAX_PAGES") ?? "\(ocrMaxPages())") ?? ocrMaxPages()
        return max(1, min(200, parsed))
    }

    private static func previewImageDPI() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_PREVIEW_DPI") ?? "140") ?? 140
        return max(72, min(300, parsed))
    }

    private static func ocrDPI() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_OCR_DPI") ?? "220") ?? 220
        return max(120, min(600, parsed))
    }

    private static func ocrLanguage() -> String {
        guard let value = Environment.get("ORCHIVISTE_OCR_LANG")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "fra+eng"
        }
        return value
    }

    private static func extractTextWithTesseract(fileURL: URL, logger: Logger) -> [String]? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-ocr-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Impossible de créer le dossier temporaire OCR.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return nil
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let imagePrefix = tempDir.appendingPathComponent("page").path
        let maxPages = ocrMaxPages()
        let dpi = ocrDPI()
        let convert = runCommand(
            executable: "pdftoppm",
            arguments: [
                "-f", "1",
                "-l", "\(maxPages)",
                "-r", "\(dpi)",
                "-png",
                fileURL.path,
                imagePrefix
            ]
        )
        if convert.exitCode != 0 {
            logger.warning("OCR ignoré: conversion PDF -> image en échec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(convert.stderr)
            ])
            return nil
        }

        let imageURLs: [URL]
        do {
            imageURLs = try FileManager.default
                .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            logger.warning("OCR ignoré: impossible de lister les images converties.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return nil
        }

        guard !imageURLs.isEmpty else {
            logger.warning("OCR ignoré: aucune image générée.")
            return nil
        }

        let language = ocrLanguage()
        var pages: [String] = []
        pages.reserveCapacity(imageURLs.count)

        for imageURL in imageURLs {
            let ocr = runCommand(
                executable: "tesseract",
                arguments: [
                    imageURL.path,
                    "stdout",
                    "-l", language,
                    "--dpi", "\(dpi)"
                ]
            )
            if ocr.exitCode != 0 {
                logger.warning("OCR en échec pour une page.", metadata: [
                    "image": .string(imageURL.lastPathComponent),
                    "stderr": .string(ocr.stderr)
                ])
                pages.append("")
                continue
            }
            pages.append(ocr.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let chars = meaningfulCharactersCount(pages)
        if chars == 0 {
            return nil
        }
        return pages
    }

    private static func extractImagesWithPdftoppm(fileURL: URL, logger: Logger) -> [Data] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Aperçu image externe indisponible: création dossier temporaire échouée.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return []
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let imagePrefix = tempDir.appendingPathComponent("page").path
        let convert = runCommand(
            executable: "pdftoppm",
            arguments: [
                "-f", "1",
                "-l", "\(previewMaxPages())",
                "-r", "\(previewImageDPI())",
                "-jpeg",
                fileURL.path,
                imagePrefix
            ]
        )
        if convert.exitCode != 0 {
            logger.warning("Aperçu image externe indisponible: pdftoppm en échec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(convert.stderr)
            ])
            return []
        }

        let imageURLs: [URL]
        do {
            imageURLs = try FileManager.default
                .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            logger.warning("Aperçu image externe indisponible: lecture des images échouée.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return []
        }

        var images: [Data] = []
        images.reserveCapacity(imageURLs.count)
        for url in imageURLs {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                images.append(data)
            }
        }
        return images
    }

    private static func runCommand(executable: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ("", "\(error)", -1)
        }
        process.waitUntilExit()

        let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    #if canImport(PDFKit) && canImport(AppKit)
    private static func loadImageJPEGData(fileURL: URL) -> Data? {
        if fileURL.pathExtension.lowercased() == "jpg" || fileURL.pathExtension.lowercased() == "jpeg" {
            return try? Data(contentsOf: fileURL)
        }
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        return jpegData(from: image)
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.72]
        )
    }
    #else
    private static func loadImageJPEGData(fileURL: URL) -> Data? {
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "jpg" || ext == "jpeg" else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }
    #endif
}
