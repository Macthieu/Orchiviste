import Foundation
import Vapor

enum SearchablePDFBuilder {
    static func shouldTryBuild(for sourceURL: URL) -> Bool {
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            return false
        }
        return routeSearchablePDFEnabled()
    }

    static func buildIfNeeded(
        sourceURL: URL,
        destinationURL: URL,
        logger: Logger
    ) throws -> Bool {
        guard shouldTryBuild(for: sourceURL) else {
            return false
        }

        let existingTextChars = extractedTextCharacterCount(fileURL: sourceURL)
        if existingTextChars >= routeOCRMinTextChars() {
            logger.info("PDF déjà sélectionnable: OCR de routage ignoré.", metadata: [
                "path": .string(sourceURL.path),
                "chars": .stringConvertible(existingTextChars)
            ])
            return false
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-route-ocr-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Impossible de créer le dossier temporaire OCR routage.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return false
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let imagePrefix = tempDir.appendingPathComponent("page").path
        let convert = runCommand(
            executable: "pdftoppm",
            arguments: [
                "-f", "1",
                "-l", "\(routeOCRMaxPages())",
                "-r", "\(routeOCRDPI())",
                "-png",
                sourceURL.path,
                imagePrefix
            ]
        )
        if convert.exitCode != 0 {
            logger.warning("OCR routage ignoré: conversion PDF -> image en échec.", metadata: [
                "path": .string(sourceURL.path),
                "stderr": .string(convert.stderr)
            ])
            return false
        }

        let imageURLs: [URL]
        do {
            imageURLs = try FileManager.default
                .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            logger.warning("OCR routage ignoré: images temporaires introuvables.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return false
        }

        guard !imageURLs.isEmpty else {
            logger.warning("OCR routage ignoré: aucune image générée.")
            return false
        }

        var pagePDFs: [URL] = []
        for (index, imageURL) in imageURLs.enumerated() {
            let outBase = tempDir.appendingPathComponent(String(format: "ocr-%04d", index + 1)).path
            let ocr = runCommand(
                executable: "tesseract",
                arguments: [
                    imageURL.path,
                    outBase,
                    "-l", routeOCRLanguage(),
                    "--dpi", "\(routeOCRDPI())",
                    "pdf"
                ]
            )
            if ocr.exitCode != 0 {
                logger.warning("OCR routage en échec sur une page.", metadata: [
                    "image": .string(imageURL.lastPathComponent),
                    "stderr": .string(ocr.stderr)
                ])
                continue
            }
            let pagePDF = URL(fileURLWithPath: "\(outBase).pdf")
            if FileManager.default.fileExists(atPath: pagePDF.path) {
                pagePDFs.append(pagePDF)
            }
        }

        guard !pagePDFs.isEmpty else {
            logger.warning("OCR routage ignoré: aucun PDF OCR produit.")
            return false
        }

        let mergedOutput = tempDir.appendingPathComponent("merged-searchable.pdf")
        if pagePDFs.count == 1 {
            do {
                try FileManager.default.copyItem(at: pagePDFs[0], to: mergedOutput)
            } catch {
                logger.warning("Copie PDF OCR page unique échouée.", metadata: [
                    "error": .string(error.localizedDescription)
                ])
                return false
            }
        } else {
            let merge = runCommand(
                executable: "pdfunite",
                arguments: pagePDFs.map(\.path) + [mergedOutput.path]
            )
            if merge.exitCode != 0 {
                logger.warning("Fusion PDF OCR échouée.", metadata: [
                    "stderr": .string(merge.stderr)
                ])
                return false
            }
        }

        guard FileManager.default.fileExists(atPath: mergedOutput.path) else {
            logger.warning("PDF OCR final absent après génération.")
            return false
        }

        let outputChars = extractedTextCharacterCount(fileURL: mergedOutput)
        if outputChars < max(10, routeOCRMinTextChars() / 2) {
            logger.warning("PDF OCR généré mais peu de texte détecté.", metadata: [
                "chars": .stringConvertible(outputChars)
            ])
        }

        do {
            try FileManager.default.moveItem(at: mergedOutput, to: destinationURL)
        } catch {
            logger.warning("Déplacement du PDF OCR final échoué.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return false
        }

        logger.info("PDF sélectionnable généré pour routage.", metadata: [
            "source_path": .string(sourceURL.path),
            "destination_path": .string(destinationURL.path),
            "pages": .stringConvertible(pagePDFs.count),
            "chars": .stringConvertible(outputChars)
        ])
        return true
    }

    private static func routeSearchablePDFEnabled() -> Bool {
        let raw = (Environment.get("ORCHIVISTE_ROUTE_OCR_SEARCHABLE_PDF")
            ?? Environment.get("ORCHIVISTE_OCR_ENABLED")
            ?? "1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !(raw == "0" || raw == "false" || raw == "no" || raw == "off")
    }

    private static func routeOCRMinTextChars() -> Int {
        max(20, Int(
            Environment.get("ORCHIVISTE_ROUTE_OCR_MIN_TEXT_CHARS")
                ?? Environment.get("ORCHIVISTE_OCR_MIN_TEXT_CHARS")
                ?? "140"
        ) ?? 140)
    }

    private static func routeOCRMaxPages() -> Int {
        let parsed = Int(
            Environment.get("ORCHIVISTE_ROUTE_OCR_MAX_PAGES")
                ?? Environment.get("ORCHIVISTE_OCR_MAX_PAGES")
                ?? "12"
        ) ?? 12
        return max(1, min(200, parsed))
    }

    private static func routeOCRDPI() -> Int {
        let parsed = Int(
            Environment.get("ORCHIVISTE_ROUTE_OCR_DPI")
                ?? Environment.get("ORCHIVISTE_OCR_DPI")
                ?? "220"
        ) ?? 220
        return max(120, min(600, parsed))
    }

    private static func routeOCRLanguage() -> String {
        let value = Environment.get("ORCHIVISTE_ROUTE_OCR_LANG")
            ?? Environment.get("ORCHIVISTE_OCR_LANG")
            ?? "fra+eng"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "fra+eng" : trimmed
    }

    private static func extractedTextCharacterCount(fileURL: URL) -> Int {
        let extract = runCommand(
            executable: "pdftotext",
            arguments: ["-enc", "UTF-8", "-layout", fileURL.path, "-"]
        )
        guard extract.exitCode == 0 else {
            return 0
        }
        return extract.stdout
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .count
    }

    private static func runCommand(executable: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ("", "command_failed: \(error.localizedDescription)", 127)
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outString = String(data: outData, encoding: .utf8) ?? ""
        let errString = String(data: errData, encoding: .utf8) ?? ""
        return (outString, errString, process.terminationStatus)
    }
}
