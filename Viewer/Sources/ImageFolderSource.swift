import UIKit
import ImageIO

final class ImageFolderSource: PageSource {
    private let imageURLs: [URL]

    var pageCount: Int { imageURLs.count }

    init(directoryURL: URL) {
        let urls = (try? BookImporter.listImages(in: directoryURL)) ?? []
        self.imageURLs = urls
    }

    func image(at index: Int, maxPixelSize: CGFloat) -> UIImage? {
        guard imageURLs.indices.contains(index) else { return nil }
        return Self.downsampledImage(at: imageURLs[index], maxPixelSize: maxPixelSize)
    }

    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return UIImage(contentsOfFile: url.path)
        }

        let size = max(maxPixelSize, 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: size
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(contentsOfFile: url.path)
        }
        return UIImage(cgImage: cgImage)
    }
}
