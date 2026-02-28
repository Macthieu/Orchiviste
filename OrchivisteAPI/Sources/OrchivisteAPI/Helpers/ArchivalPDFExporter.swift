import Foundation
import Vapor

struct ArchivalPDFExportResult {
    let converted: Bool
    let warnings: [String]
}

enum ArchivalPDFExporter {
    static func preferredFormat(preset: Preset?) -> String? {
        if let presetFormat = preset?.export?.preferred_pdf?.format,
           !presetFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return presetFormat
        }
        if let envFormat = Environment.get("ORCHIVISTE_EXPORT_PREFERRED_PDF_FORMAT"),
           !envFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envFormat
        }
        return nil
    }

    static func shouldAttemptPDFA(preset: Preset?) -> Bool {
        let enabledByPreset = preset?.export?.preferred_pdf?.enabled ?? false
        let enabledByEnv = parseBoolean(Environment.get("ORCHIVISTE_EXPORT_PDFA_ENABLED"))
        let format = preferredFormat(preset: preset)?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        let wantsPDFA = format == "PDF/A-2B" || format == "PDFA-2B" || format == "PDF/A2B"
        return wantsPDFA && (enabledByPreset || enabledByEnv)
    }

    static func convertIfNeeded(
        sourceURL: URL,
        destinationURL: URL,
        preset: Preset?,
        logger: Logger
    ) -> ArchivalPDFExportResult {
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            return ArchivalPDFExportResult(converted: false, warnings: [])
        }
        guard shouldAttemptPDFA(preset: preset) else {
            return ArchivalPDFExportResult(converted: false, warnings: [])
        }
        guard commandExists("gs") else {
            logger.warning("Ghostscript indisponible: fallback PDF normal.")
            return ArchivalPDFExportResult(
                converted: false,
                warnings: ["pdfa_requested_but_ghostscript_missing"]
            )
        }

        let tempOutput = destinationURL.deletingLastPathComponent()
            .appendingPathComponent("pdfa-\(UUID().uuidString).pdf")
        let convert = ShellCommand.run(
            executable: "gs",
            arguments: [
                "-dBATCH",
                "-dNOPAUSE",
                "-dNOSAFER",
                "-sDEVICE=pdfwrite",
                "-dPDFA=2",
                "-dPDFACompatibilityPolicy=1",
                "-dAutoRotatePages=/None",
                "-sColorConversionStrategy=UseDeviceIndependentColor",
                "-sProcessColorModel=DeviceRGB",
                "-sOutputFile=\(tempOutput.path)",
                sourceURL.path
            ]
        )

        guard convert.exitCode == 0, FileManager.default.fileExists(atPath: tempOutput.path) else {
            logger.warning("Conversion PDF/A en echec, fallback PDF normal.", metadata: [
                "source_path": .string(sourceURL.path),
                "stderr": .string(convert.stderr)
            ])
            try? FileManager.default.removeItem(at: tempOutput)
            return ArchivalPDFExportResult(
                converted: false,
                warnings: ["pdfa_conversion_failed"]
            )
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempOutput, to: destinationURL)
            logger.info("Export PDF/A-2b genere.", metadata: [
                "source_path": .string(sourceURL.path),
                "destination_path": .string(destinationURL.path)
            ])
            return ArchivalPDFExportResult(converted: true, warnings: [])
        } catch {
            logger.warning("Deplacement du PDF/A final en echec.", metadata: [
                "error": .string(error.localizedDescription),
                "destination_path": .string(destinationURL.path)
            ])
            try? FileManager.default.removeItem(at: tempOutput)
            return ArchivalPDFExportResult(
                converted: false,
                warnings: ["pdfa_move_failed"]
            )
        }
    }

    private static func parseBoolean(_ raw: String?) -> Bool {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return false
        }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }

    private static func commandExists(_ executable: String) -> Bool {
        let result = ShellCommand.run(executable: "which", arguments: [executable])
        return result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
