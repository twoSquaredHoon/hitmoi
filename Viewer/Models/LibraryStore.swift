import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var folders: [LibraryFolder] = []
    @Published var readingDirection: ReadingDirection {
        didSet { UserDefaults.standard.set(readingDirection.rawValue, forKey: Self.directionKey) }
    }
    /// Show two pages side by side when the device is in landscape.
    @Published var dualPageEnabled: Bool {
        didSet { UserDefaults.standard.set(dualPageEnabled, forKey: Self.dualPageKey) }
    }
    /// 0 pairs (1,2)(3,4); 1 leaves page 1 alone and pairs (2,3)(4,5).
    @Published var pairOffset: Int {
        didSet { UserDefaults.standard.set(pairOffset, forKey: Self.pairOffsetKey) }
    }
    @Published var bookSort: BookSort {
        didSet { UserDefaults.standard.set(bookSort.rawValue, forKey: Self.bookSortKey) }
    }
    /// Seconds between auto page turns. Default 3.
    @Published var autoFlipSeconds: Int {
        didSet { UserDefaults.standard.set(autoFlipSeconds, forKey: Self.autoFlipSecondsKey) }
    }

    private static let directionKey = "readingDirection"
    private static let dualPageKey = "dualPageEnabled"
    private static let pairOffsetKey = "pairOffset"
    private static let bookSortKey = "bookSort"
    private static let autoFlipSecondsKey = "autoFlipSeconds"
    static let autoFlipChoices = [2, 3, 4, 5, 8, 10]
    private var pendingSaveTask: Task<Void, Never>?

    enum BookSort: String, CaseIterable, Identifiable {
        case recent
        case name

        var id: String { rawValue }

        var label: String {
            switch self {
            case .recent: "Recently added"
            case .name: "Name A–Z"
            }
        }
    }

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
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: Self.directionKey) ?? ReadingDirection.rtl.rawValue
        readingDirection = ReadingDirection(rawValue: raw) ?? .rtl
        dualPageEnabled = defaults.object(forKey: Self.dualPageKey) as? Bool ?? true
        pairOffset = defaults.integer(forKey: Self.pairOffsetKey) == 1 ? 1 : 0
        let sortRaw = defaults.string(forKey: Self.bookSortKey) ?? BookSort.recent.rawValue
        bookSort = BookSort(rawValue: sortRaw) ?? .recent
        let storedInterval = defaults.object(forKey: Self.autoFlipSecondsKey) as? Int ?? 3
        autoFlipSeconds = Self.autoFlipChoices.contains(storedInterval) ? storedInterval : 3
        // Ensure Documents/Books exists so Files app can show the Viewer folder.
        try? BookStorage.ensureBooksRoot()
        load()
    }

    func load() {
        let url = BookStorage.libraryFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            books = []
            folders = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            if let snapshot = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
                folders = snapshot.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                books = sortedBooks(snapshot.books)
            } else {
                // Backward compatible: older libraries were a bare [Book] array.
                folders = []
                books = sortedBooks(try JSONDecoder().decode([Book].self, from: data))
            }
        } catch {
            books = []
            folders = []
        }
    }

    func save() {
        do {
            try BookStorage.ensureBooksRoot()
            let snapshot = LibrarySnapshot(folders: folders, books: books)
            let data = try JSONEncoder().encode(snapshot)
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

    func add(_ book: Book, to folderID: UUID? = nil) {
        var stored = book
        stored.folderID = folderID
        books.insert(stored, at: 0)
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

    func folder(id: UUID) -> LibraryFolder? {
        folders.first { $0.id == id }
    }

    func books(in folderID: UUID?) -> [Book] {
        sortedBooks(books.filter { $0.folderID == folderID })
    }

    func bookCount(in folderID: UUID) -> Int {
        books.filter { $0.folderID == folderID }.count
    }

    private func sortedBooks(_ books: [Book]) -> [Book] {
        switch bookSort {
        case .recent:
            return books.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    @discardableResult
    func createFolder(named name: String) -> LibraryFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = LibraryFolder(name: trimmed)
        folders.append(folder)
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save()
        return folder
    }

    func renameFolder(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        save()
    }

    func deleteFolder(id: UUID) {
        for index in books.indices where books[index].folderID == id {
            books[index].folderID = nil
        }
        folders.removeAll { $0.id == id }
        save()
    }

    func moveBook(_ book: Book, to folderID: UUID?) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        guard books[index].folderID != folderID else { return }
        books[index].folderID = folderID
        save()
    }
}
