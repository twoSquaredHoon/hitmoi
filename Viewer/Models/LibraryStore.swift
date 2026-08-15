import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var readingDirection: ReadingDirection {
        didSet { UserDefaults.standard.set(readingDirection.rawValue, forKey: Self.directionKey) }
    }

    private static let directionKey = "readingDirection"
    private var pendingSaveTask: Task<Void, Never>?

    enum ReadingDirection: String, CaseIterable, Identifiable {
        case rtl
        case ltr

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rtl: "Right to left (manga)"
            case .ltr: "Left to right"
            }
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.directionKey) ?? ReadingDirection.rtl.rawValue
        readingDirection = ReadingDirection(rawValue: raw) ?? .rtl
        load()
    }

    func load() {
        let url = BookStorage.libraryFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            books = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            books = try JSONDecoder().decode([Book].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            books = []
        }
    }

    func save() {
        do {
            try BookStorage.ensureBooksRoot()
            let data = try JSONEncoder().encode(books)
            try data.write(to: BookStorage.libraryFileURL, options: [.atomic])
        } catch {
            // Personal app: fail quietly; UI can still show in-memory state.
        }
    }

    /// Writes progress soon, without blocking every page turn on disk I/O.
    func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func flush() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        save()
    }

    func add(_ book: Book) {
        books.insert(book, at: 0)
        save()
    }

    func updateLastPage(bookID: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let clamped = max(0, min(page, max(0, books[index].pageCount - 1)))
        guard books[index].lastPage != clamped else { return }
        books[index].lastPage = clamped
        scheduleSave()
    }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
        save()
        try? FileManager.default.removeItem(at: book.bookDirectoryURL)
    }

    func book(id: UUID) -> Book? {
        books.first { $0.id == id }
    }
}
