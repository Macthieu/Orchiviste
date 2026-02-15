import Foundation
import Vapor
#if canImport(PDFKit) && canImport(AppKit)
import PDFKit
import AppKit
#endif

enum PreviewRenderer {
    static func makePreview(for job: JobRecord, logger: Logger) -> PreviewRecord {
        #if canImport(PDFKit) && canImport(AppKit)
        guard job.source.kind.lowercased() == "local",
              let localFileURL = resolveLocalFileURL(raw: job.fileURL),
              FileManager.default.fileExists(atPath: localFileURL.path) else {
            return placeholder(jobId: job.id)
        }

        guard localFileURL.pathExtension.lowercased() == "pdf",
              let document = PDFDocument(url: localFileURL) else {
            return placeholder(jobId: job.id)
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

        logger.info("Preview generated.", metadata: ["job_id": .string(job.id.uuidString), "pages": .stringConvertible(pageCount)])
        return PreviewRecord(
            jobId: job.id,
            pages: pageCount,
            textPages: textPages,
            imagesByPage: imagesByPage,
            createdAt: Date()
        )
        #else
        logger.warning("PDF rendering unavailable on this platform. Using placeholder preview.")
        return placeholder(jobId: job.id)
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

    #if canImport(PDFKit) && canImport(AppKit)
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
    #endif
}
