import UIKit

/// Small in-memory page cache so turning pages does not re-decode from disk every time.
final class PageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [Int: UIImage] = [:]
    private var order: [Int] = []
    private let capacity: Int

    init(capacity: Int = 9) {
        self.capacity = max(3, capacity)
    }

    func image(at index: Int) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let image = images[index] else { return nil }
        if let pos = order.firstIndex(of: index) {
            order.remove(at: pos)
            order.append(index)
        }
        return image
    }

    func store(_ image: UIImage, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        if images[index] == nil {
            order.append(index)
        }
        images[index] = image
        while order.count > capacity {
            let evicted = order.removeFirst()
            images.removeValue(forKey: evicted)
        }
    }
}
