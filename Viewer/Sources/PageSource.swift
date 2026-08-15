import UIKit

protocol PageSource: AnyObject {
    var pageCount: Int { get }
    func image(at index: Int, maxPixelSize: CGFloat) -> UIImage?
}

enum PageSourceFactory {
    static func make(for book: Book) -> PageSource? {
        switch book.kind {
        case .images:
            return ImageFolderSource(directoryURL: book.contentURL)
        case .pdf:
            return PDFSource(url: book.contentURL)
        }
    }
}
