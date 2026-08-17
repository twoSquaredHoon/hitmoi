import Foundation

enum BookKind: String, Codable, Hashable {
    case images
    case pdf
}

struct LibraryFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct Book: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    let kind: BookKind
    let createdAt: Date
    /// 0-based page index last viewed.
    var lastPage: Int
    /// Relative path under Documents/Books/<id>/…
    let storagePath: String
    var pageCount: Int
    /// nil = unfiled (library root).
    var folderID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        kind: BookKind,
        createdAt: Date = Date(),
        lastPage: Int = 0,
        storagePath: String,
        pageCount: Int,
        folderID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
        self.lastPage = lastPage
        self.storagePath = storagePath
        self.pageCount = pageCount
        self.folderID = folderID
    }

    var bookDirectoryURL: URL {
        BookStorage.booksRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    var contentURL: URL {
        bookDirectoryURL.appendingPathComponent(storagePath)
    }
}

/// On-disk library format. Older installs only stored a bare book array.
struct LibrarySnapshot: Codable {
    var folders: [LibraryFolder]
    var books: [Book]
}

enum BookStorage {
    static var documentsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var booksRoot: URL {
        documentsRoot.appendingPathComponent("Books", isDirectory: true)
    }

    static var libraryFileURL: URL {
        documentsRoot.appendingPathComponent("library.json")
    }

    static func ensureBooksRoot() throws {
        try FileManager.default.createDirectory(at: booksRoot, withIntermediateDirectories: true)
    }
}
