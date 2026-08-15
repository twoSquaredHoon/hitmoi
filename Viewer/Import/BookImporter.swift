import Foundation
import PDFKit

enum BookImportError: LocalizedError {
    case unsupported
    case noImagesFound
    case pdfUnreadable
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "Choose a folder of images or a PDF."
        case .noImagesFound:
            return "No JPG/PNG/WebP images found in that folder."
        case .pdfUnreadable:
            return "Could not open that PDF."
        case .copyFailed(let message):
            return "Import failed: \(message)"
        }
    }
}

enum BookImporter {
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]

    static func importItem(from url: URL) throws -> Book {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists else { throw BookImportError.unsupported }

        if isDirectory.boolValue {
            return try importImageFolder(from: url)
        }

        if url.pathExtension.lowercased() == "pdf" {
            return try importPDF(from: url)
        }

        throw BookImportError.unsupported
    }

    private static func importImageFolder(from sourceURL: URL) throws -> Book {
        let images = try listImages(in: sourceURL)
        guard !images.isEmpty else { throw BookImportError.noImagesFound }

        let id = UUID()
        let destination = BookStorage.booksRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let pagesDir = destination.appendingPathComponent("pages", isDirectory: true)

        do {
            try BookStorage.ensureBooksRoot()
            try FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)

            for (index, imageURL) in images.enumerated() {
                let ext = imageURL.pathExtension.lowercased()
                let name = String(format: "%05d.%@", index, ext)
                let dest = pagesDir.appendingPathComponent(name)
                try FileManager.default.copyItem(at: imageURL, to: dest)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw BookImportError.copyFailed(error.localizedDescription)
        }

        return Book(
            id: id,
            title: sourceURL.lastPathComponent,
            kind: .images,
            storagePath: "pages",
            pageCount: images.count
        )
    }

    private static func importPDF(from sourceURL: URL) throws -> Book {
        guard let document = PDFDocument(url: sourceURL), document.pageCount > 0 else {
            throw BookImportError.pdfUnreadable
        }

        let id = UUID()
        let destination = BookStorage.booksRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let destPDF = destination.appendingPathComponent("book.pdf")

        do {
            try BookStorage.ensureBooksRoot()
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destPDF)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw BookImportError.copyFailed(error.localizedDescription)
        }

        return Book(
            id: id,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            kind: .pdf,
            storagePath: "book.pdf",
            pageCount: document.pageCount
        )
    }

    static func listImages(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { url in
                imageExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }
}
