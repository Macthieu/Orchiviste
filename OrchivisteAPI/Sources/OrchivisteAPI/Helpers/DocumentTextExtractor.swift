import Foundation
import Vapor
#if canImport(PDFKit) && canImport(AppKit)
import PDFKit
import AppKit
#endif

struct ExtractedDocumentText {
    let kind: String
    let pages: [String]
    let previewPDFURL: URL?
    let temporaryArtifacts: [URL]
    let warnings: [String]
}

enum DocumentTextExtractor {
    private static let supportedExtensionsSet: Set<String> = [
        "pdf", "docx", "xlsx", "pptx", "png", "jpg", "jpeg", "tif", "tiff"
    ]

    static func supportedExtensions() -> [String] {
        supportedExtensionsSet.sorted()
    }

    static func isSupported(fileURL: URL) -> Bool {
        supportedExtensionsSet.contains(fileURL.pathExtension.lowercased())
    }

    static func extract(fileURL: URL, logger: Logger) -> ExtractedDocumentText? {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf":
            let pages = extractPDFPages(fileURL: fileURL, logger: logger)
            return ExtractedDocumentText(
                kind: "pdf",
                pages: pages.isEmpty ? [defaultText(for: fileURL)] : pages,
                previewPDFURL: nil,
                temporaryArtifacts: [],
                warnings: pages.isEmpty ? ["pdf_text_extraction_unavailable"] : []
            )
        case "docx":
            let pages = extractDOCXPages(fileURL: fileURL, logger: logger)
            let conversion = convertOfficeDocumentToPDFIfPossible(fileURL: fileURL, logger: logger)
            guard !pages.isEmpty || conversion.pdfURL != nil else { return nil }
            return ExtractedDocumentText(
                kind: "docx",
                pages: pages.isEmpty ? [defaultText(for: fileURL)] : pages,
                previewPDFURL: conversion.pdfURL,
                temporaryArtifacts: conversion.temporaryArtifacts,
                warnings: conversion.warnings
            )
        case "xlsx":
            let pages = extractXLSXPages(fileURL: fileURL, logger: logger)
            let conversion = convertOfficeDocumentToPDFIfPossible(fileURL: fileURL, logger: logger)
            guard !pages.isEmpty || conversion.pdfURL != nil else { return nil }
            return ExtractedDocumentText(
                kind: "xlsx",
                pages: pages.isEmpty ? [defaultText(for: fileURL)] : pages,
                previewPDFURL: conversion.pdfURL,
                temporaryArtifacts: conversion.temporaryArtifacts,
                warnings: conversion.warnings
            )
        case "pptx":
            let pages = extractPPTXPages(fileURL: fileURL, logger: logger)
            let conversion = convertOfficeDocumentToPDFIfPossible(fileURL: fileURL, logger: logger)
            guard !pages.isEmpty || conversion.pdfURL != nil else { return nil }
            return ExtractedDocumentText(
                kind: "pptx",
                pages: pages.isEmpty ? [defaultText(for: fileURL)] : pages,
                previewPDFURL: conversion.pdfURL,
                temporaryArtifacts: conversion.temporaryArtifacts,
                warnings: conversion.warnings
            )
        case "png", "jpg", "jpeg", "tif", "tiff":
            let pages = extractImagePages(fileURL: fileURL, logger: logger)
            let conversion = convertImageToPDFIfPossible(fileURL: fileURL, logger: logger)
            return ExtractedDocumentText(
                kind: "image",
                pages: pages.isEmpty ? [defaultText(for: fileURL)] : pages,
                previewPDFURL: conversion.pdfURL,
                temporaryArtifacts: conversion.temporaryArtifacts,
                warnings: conversion.warnings
            )
        default:
            return nil
        }
    }

    static func defaultText(for fileURL: URL) -> String {
        "Apercu texte indisponible pour \(fileURL.lastPathComponent)."
    }

    private static func extractPDFPages(fileURL: URL, logger: Logger) -> [String] {
        #if canImport(PDFKit) && canImport(AppKit)
        if let document = PDFDocument(url: fileURL) {
            var pages: [String] = []
            for index in 0..<document.pageCount {
                let text = document.page(at: index)?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty {
                    pages.append(text)
                }
            }
            if !pages.isEmpty {
                return pages
            }

            if ocrEnabled() {
                let renderedOCRPages = extractOCRPagesFromPDFWithPDFKit(document: document, logger: logger)
                if !renderedOCRPages.isEmpty {
                    return renderedOCRPages
                }
            }
        }
        #endif

        let direct = ShellCommand.run(
            executable: "pdftotext",
            arguments: ["-enc", "UTF-8", "-layout", fileURL.path, "-"]
        )
        var directPages = splitPages(direct.stdout)
        if !directPages.isEmpty, meaningfulCharacters(in: directPages) >= ocrMinCharacters() {
            return directPages
        }

        guard ocrEnabled() else {
            return directPages
        }

        let ocrPages = extractOCRPagesFromPDF(fileURL: fileURL, logger: logger)
        if meaningfulCharacters(in: ocrPages) > meaningfulCharacters(in: directPages) {
            directPages = ocrPages
        }
        return directPages
    }

    #if canImport(PDFKit) && canImport(AppKit)
    private static func extractOCRPagesFromPDFWithPDFKit(document: PDFDocument, logger: Logger) -> [String] {
        guard commandExists("tesseract") else {
            logger.warning("OCR PDF via PDFKit ignoré: tesseract absent.")
            return []
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-pdfkit-ocr-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Impossible de créer le dossier temporaire OCR PDFKit.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return []
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        var pages: [String] = []
        let maxPages = min(document.pageCount, ocrMaxPages())
        for index in 0..<maxPages {
            guard let page = document.page(at: index) else {
                continue
            }
            let pageBounds = page.bounds(for: .mediaBox)
            let safeWidth = max(1, pageBounds.width)
            let ratio = max(0.2, pageBounds.height / safeWidth)
            let size = NSSize(width: 1600, height: max(600, 1600 * ratio))
            let image = page.thumbnail(of: size, for: .mediaBox)
            let imageURL = tempDir.appendingPathComponent("page-\(index + 1).png")
            guard writePNGImage(image, to: imageURL) else {
                continue
            }

            let ocr = ShellCommand.run(
                executable: "tesseract",
                arguments: [
                    imageURL.path,
                    "stdout",
                    "-l", ocrLanguage(),
                    "--dpi", "\(ocrDPI())"
                ]
            )
            guard ocr.exitCode == 0 else {
                logger.warning("OCR PDFKit en échec pour une page.", metadata: [
                    "page": .stringConvertible(index + 1),
                    "stderr": .string(ocr.stderr)
                ])
                continue
            }
            let trimmed = ocr.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pages.append(trimmed)
            }
        }
        return pages
    }

    private static func writePNGImage(_ image: NSImage, to url: URL) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
    #endif

    private static func extractDOCXPages(fileURL: URL, logger: Logger) -> [String] {
        let preferredEntries = [
            "word/document.xml",
            "word/header1.xml",
            "word/header2.xml",
            "word/footer1.xml",
            "word/footer2.xml"
        ]
        var chunks: [String] = []
        for entry in preferredEntries {
            if let xml = zipEntryText(fileURL: fileURL, entry: entry),
               !xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chunks.append(xmlToPlainText(xml))
            }
        }
        let merged = chunks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if merged.isEmpty {
            logger.warning("Extraction DOCX vide.", metadata: ["path": .string(fileURL.path)])
            return []
        }
        return [merged]
    }

    private static func extractXLSXPages(fileURL: URL, logger: Logger) -> [String] {
        let sharedStrings = loadXLSXSharedStrings(fileURL: fileURL)
        let entries = zipEntryList(fileURL: fileURL)
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()

        var pages: [String] = []
        for entry in entries {
            guard let xml = zipEntryText(fileURL: fileURL, entry: entry) else {
                continue
            }
            let text = xlsxSheetToPlainText(xml: xml, sharedStrings: sharedStrings)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pages.append(trimmed)
            }
        }
        if pages.isEmpty {
            logger.warning("Extraction XLSX vide.", metadata: ["path": .string(fileURL.path)])
        }
        return pages
    }

    private static func extractPPTXPages(fileURL: URL, logger: Logger) -> [String] {
        let entries = zipEntryList(fileURL: fileURL)
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted()

        var pages: [String] = []
        for entry in entries {
            guard let xml = zipEntryText(fileURL: fileURL, entry: entry) else {
                continue
            }
            let text = xmlToPlainText(xml)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                pages.append(text)
            }
        }
        if pages.isEmpty {
            logger.warning("Extraction PPTX vide.", metadata: ["path": .string(fileURL.path)])
        }
        return pages
    }

    private static func extractImagePages(fileURL: URL, logger: Logger) -> [String] {
        guard ocrEnabled() else {
            return []
        }
        let ocr = ShellCommand.run(
            executable: "tesseract",
            arguments: [
                fileURL.path,
                "stdout",
                "-l", ocrLanguage()
            ]
        )
        guard ocr.exitCode == 0 else {
            logger.warning("OCR image en echec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(ocr.stderr)
            ])
            return []
        }
        let text = ocr.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? [] : [text]
    }

    private static func extractOCRPagesFromPDF(fileURL: URL, logger: Logger) -> [String] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-doc-ocr-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return []
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let imagePrefix = tempDir.appendingPathComponent("page").path
        let convert = ShellCommand.run(
            executable: "pdftoppm",
            arguments: [
                "-f", "1",
                "-l", "\(ocrMaxPages())",
                "-r", "\(ocrDPI())",
                "-png",
                fileURL.path,
                imagePrefix
            ]
        )
        guard convert.exitCode == 0 else {
            logger.warning("OCR PDF ignore: conversion en images en echec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(convert.stderr)
            ])
            return []
        }

        let imageURLs: [URL]
        do {
            imageURLs = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: nil
            )
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return []
        }

        var pages: [String] = []
        for imageURL in imageURLs {
            let ocr = ShellCommand.run(
                executable: "tesseract",
                arguments: [
                    imageURL.path,
                    "stdout",
                    "-l", ocrLanguage(),
                    "--dpi", "\(ocrDPI())"
                ]
            )
            if ocr.exitCode == 0 {
                pages.append(ocr.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return pages.filter { !$0.isEmpty }
    }

    private static func convertOfficeDocumentToPDFIfPossible(
        fileURL: URL,
        logger: Logger
    ) -> (pdfURL: URL?, temporaryArtifacts: [URL], warnings: [String]) {
        guard officeConversionEnabled() else {
            return (nil, [], ["office_preview_conversion_disabled"])
        }
        guard commandExists("soffice") || commandExists("libreoffice") else {
            return (nil, [], ["office_preview_conversion_unavailable"])
        }

        let executable = commandExists("soffice") ? "soffice" : "libreoffice"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-office-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return (nil, [], ["office_preview_conversion_tempdir_failed"])
        }

        let convert = ShellCommand.run(
            executable: executable,
            arguments: [
                "--headless",
                "--convert-to", "pdf",
                "--outdir", tempDir.path,
                fileURL.path
            ]
        )
        guard convert.exitCode == 0 else {
            logger.warning("Conversion Office -> PDF en echec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(convert.stderr)
            ])
            try? FileManager.default.removeItem(at: tempDir)
            return (nil, [], ["office_preview_conversion_failed"])
        }

        let pdfURL = tempDir.appendingPathComponent(
            fileURL.deletingPathExtension().lastPathComponent + ".pdf"
        )
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            try? FileManager.default.removeItem(at: tempDir)
            return (nil, [], ["office_preview_pdf_missing"])
        }
        return (pdfURL, [tempDir], [])
    }

    private static func convertImageToPDFIfPossible(
        fileURL: URL,
        logger: Logger
    ) -> (pdfURL: URL?, temporaryArtifacts: [URL], warnings: [String]) {
        guard ocrEnabled() else {
            return (nil, [], ["image_preview_pdf_disabled"])
        }
        guard commandExists("tesseract") else {
            return (nil, [], ["image_preview_pdf_unavailable"])
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-image-preview-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return (nil, [], ["image_preview_pdf_tempdir_failed"])
        }

        let outputBase = tempDir.appendingPathComponent("preview").path
        let convert = ShellCommand.run(
            executable: "tesseract",
            arguments: [
                fileURL.path,
                outputBase,
                "-l", ocrLanguage(),
                "pdf"
            ]
        )
        guard convert.exitCode == 0 else {
            logger.warning("Conversion image -> PDF de preview en echec.", metadata: [
                "path": .string(fileURL.path),
                "stderr": .string(convert.stderr)
            ])
            try? FileManager.default.removeItem(at: tempDir)
            return (nil, [], ["image_preview_pdf_failed"])
        }

        let pdfURL = URL(fileURLWithPath: "\(outputBase).pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            try? FileManager.default.removeItem(at: tempDir)
            return (nil, [], ["image_preview_pdf_missing"])
        }
        return (pdfURL, [tempDir], [])
    }

    private static func officeConversionEnabled() -> Bool {
        let raw = (Environment.get("ORCHIVISTE_OFFICE_CONVERSION_ENABLED") ?? "1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !(raw == "0" || raw == "false" || raw == "off" || raw == "no")
    }

    private static func commandExists(_ executable: String) -> Bool {
        let result = ShellCommand.run(executable: "which", arguments: [executable])
        return result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func ocrEnabled() -> Bool {
        let raw = (Environment.get("ORCHIVISTE_OCR_ENABLED") ?? "1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !(raw == "0" || raw == "false" || raw == "off" || raw == "no")
    }

    private static func ocrLanguage() -> String {
        let raw = Environment.get("ORCHIVISTE_OCR_LANG") ?? "fra+eng"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "fra+eng" : trimmed
    }

    private static func ocrDPI() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_OCR_DPI") ?? "220") ?? 220
        return max(120, min(600, parsed))
    }

    private static func ocrMaxPages() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_OCR_MAX_PAGES") ?? "12") ?? 12
        return max(1, min(200, parsed))
    }

    private static func ocrMinCharacters() -> Int {
        let parsed = Int(Environment.get("ORCHIVISTE_OCR_MIN_TEXT_CHARS") ?? "140") ?? 140
        return max(20, parsed)
    }

    private static func splitPages(_ raw: String) -> [String] {
        let pages = raw.components(separatedBy: "\u{0C}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return pages
    }

    private static func meaningfulCharacters(in pages: [String]) -> Int {
        pages.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .count
    }

    private static func zipEntryList(fileURL: URL) -> [String] {
        let result = ShellCommand.run(executable: "zipinfo", arguments: ["-1", fileURL.path])
        guard result.exitCode == 0 else {
            return []
        }
        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func zipEntryText(fileURL: URL, entry: String) -> String? {
        let result = ShellCommand.run(executable: "unzip", arguments: ["-p", fileURL.path, entry])
        guard result.exitCode == 0 else {
            return nil
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func xmlToPlainText(_ xml: String) -> String {
        var output = xml
        let replacements: [(String, String)] = [
            (#"</w:p>"#, "\n"),
            (#"</a:p>"#, "\n"),
            (#"</row>"#, "\n"),
            (#"<w:tab/>"#, "\t"),
            (#"<w:br/>"#, "\n"),
            (#"<br\s*/?>"#, "\n")
        ]
        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        output = output.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        output = decodeXMLEntities(output)
        output = output.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func loadXLSXSharedStrings(fileURL: URL) -> [String] {
        guard let xml = zipEntryText(fileURL: fileURL, entry: "xl/sharedStrings.xml") else {
            return []
        }
        let itemPattern = #"<si[^>]*>(.*?)</si>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: xml) else {
                return nil
            }
            let value = xmlToPlainText(String(xml[swiftRange]))
            return value.isEmpty ? nil : value
        }
    }

    private static func xlsxSheetToPlainText(xml: String, sharedStrings: [String]) -> String {
        let rowPattern = #"<row[^>]*>(.*?)</row>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else {
            return xmlToPlainText(xml)
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let rows = rowRegex.matches(in: xml, options: [], range: range)

        var lines: [String] = []
        for row in rows {
            guard let rowRange = Range(row.range(at: 1), in: xml) else {
                continue
            }
            let rowXML = String(xml[rowRange])
            let values = extractXLSXRowValues(xml: rowXML, sharedStrings: sharedStrings)
            if !values.isEmpty {
                lines.append(values.joined(separator: " | "))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func extractXLSXRowValues(xml: String, sharedStrings: [String]) -> [String] {
        let cellPattern = #"<c\b([^>]*)>(.*?)</c>"#
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var values: [String] = []

        for match in cellRegex.matches(in: xml, options: [], range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: xml),
                  let bodyRange = Range(match.range(at: 2), in: xml) else {
                continue
            }
            let attributes = String(xml[attributesRange])
            let body = String(xml[bodyRange])
            let type = firstRegexMatch(in: attributes, pattern: #"t="([^"]+)""#)
            let inlineText = firstRegexMatch(in: body, pattern: #"<t[^>]*>(.*?)</t>"#, dotMatchesLineSeparators: true)
                .map(xmlToPlainText)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let rawValue = firstRegexMatch(in: body, pattern: #"<v[^>]*>(.*?)</v>"#, dotMatchesLineSeparators: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let resolved: String?
            if type == "s", let rawValue, let index = Int(rawValue), sharedStrings.indices.contains(index) {
                resolved = sharedStrings[index]
            } else {
                resolved = inlineText ?? rawValue
            }

            if let resolved = resolved?.trimmingCharacters(in: .whitespacesAndNewlines),
               !resolved.isEmpty {
                values.append(resolved)
            }
        }
        return values
    }

    private static func firstRegexMatch(
        in text: String,
        pattern: String,
        dotMatchesLineSeparators: Bool = false
    ) -> String? {
        let options: NSRegularExpression.Options = dotMatchesLineSeparators ? [.dotMatchesLineSeparators] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private static func decodeXMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#10;", with: "\n")
            .replacingOccurrences(of: "&#13;", with: "\n")
    }
}
