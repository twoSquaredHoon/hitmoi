import UIKit
import PDFKit

final class PDFSource: PageSource {
    private let document: PDFDocument
    private let renderLock = NSLock()

    var pageCount: Int { document.pageCount }

    init?(url: URL) {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        self.document = document
    }

    func image(at index: Int, maxPixelSize: CGFloat) -> UIImage? {
        renderLock.lock()
        defer { renderLock.unlock() }

        guard let page = document.page(at: index) else { return nil }

        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let longest = max(pageRect.width, pageRect.height)
        let scale = min(max(maxPixelSize, 1) / longest, 4)
        let renderSize = CGSize(
            width: (pageRect.width * scale).rounded(.down),
            height: (pageRect.height * scale).rounded(.down)
        )
        guard renderSize.width >= 1, renderSize.height >= 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: renderSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }
}
