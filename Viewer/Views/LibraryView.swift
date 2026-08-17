import SwiftUI
import UniformTypeIdentifiers

private enum LibraryRoute: Hashable {
    case folder(UUID)
    case book(UUID)
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var isImporting = false
    @State private var importError: String?
    @State private var path = NavigationPath()
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renameTarget: LibraryFolder?
    @State private var renameText = ""
    /// Folder currently open when importing; nil means library root.
    @State private var importDestinationFolderID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            libraryRoot
                .background(Color.black.ignoresSafeArea())
                .navigationTitle("Library")
                .toolbar { rootToolbar }
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let id):
                        FolderDetailView(
                            folderID: id,
                            path: $path,
                            onAddBook: {
                                importDestinationFolderID = id
                                isImporting = true
                            }
                        )
                    case .book(let id):
                        if let book = library.book(id: id) {
                            ReaderView(book: book)
                        } else {
                            Text("Book not found")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.folder, .pdf],
                    allowsMultipleSelection: false
                ) { result in
                    handleImport(result)
                }
                .alert("Import failed", isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )) {
                    Button("OK", role: .cancel) { importError = nil }
                } message: {
                    Text(importError ?? "")
                }
                .alert("New Folder", isPresented: $showNewFolderAlert) {
                    TextField("Name", text: $newFolderName)
                    Button("Cancel", role: .cancel) {
                        newFolderName = ""
                    }
                    Button("Create") {
                        _ = library.createFolder(named: newFolderName)
                        newFolderName = ""
                    }
                } message: {
                    Text("Group books into a location.")
                }
                .alert(
                    "Rename Folder",
                    isPresented: Binding(
                        get: { renameTarget != nil },
                        set: { if !$0 { renameTarget = nil } }
                    )
                ) {
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {
                        renameTarget = nil
                    }
                    Button("Save") {
                        if let folder = renameTarget {
                            library.renameFolder(id: folder.id, to: renameText)
                        }
                        renameTarget = nil
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort books", selection: $library.bookSort) {
                    ForEach(LibraryStore.BookSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                Picker("Reading direction", selection: $library.readingDirection) {
                    ForEach(LibraryStore.ReadingDirection.allCases) { direction in
                        Text(direction.label).tag(direction)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("Library options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    importDestinationFolderID = nil
                    isImporting = true
                } label: {
                    Label("Add Book", systemImage: "plus")
                }
                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add")
        }
    }

    @ViewBuilder
    private var libraryRoot: some View {
        if library.books.isEmpty && library.folders.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if !library.folders.isEmpty {
                        folderSection
                    }
                    bookSection(
                        title: library.folders.isEmpty ? nil : "Unfiled",
                        books: library.books(in: nil)
                    )
                }
                .padding(20)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No books yet", systemImage: "books.vertical")
        } description: {
            Text("Add a folder of images or a PDF, or create a location to sort into.")
        } actions: {
            Button("Add Book") {
                importDestinationFolderID = nil
                isImporting = true
            }
            .buttonStyle(.borderedProminent)
            Button("New Folder") {
                newFolderName = ""
                showNewFolderAlert = true
            }
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(library.folders) { folder in
                    Button {
                        path.append(LibraryRoute.folder(folder.id))
                    } label: {
                        FolderCell(
                            name: folder.name,
                            count: library.bookCount(in: folder.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameText = folder.name
                            renameTarget = folder
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            library.deleteFolder(id: folder.id)
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bookSection(title: String?, books: [Book]) -> some View {
        if books.isEmpty, title != nil {
            EmptyView()
        } else if books.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(books) { book in
                        bookButton(book)
                    }
                }
            }
        }
    }

    private func bookButton(_ book: Book) -> some View {
        Button {
            path.append(LibraryRoute.book(book.id))
        } label: {
            BookCoverCell(book: book)
        }
        .buttonStyle(.plain)
        .contextMenu {
            moveMenu(for: book)
            Button(role: .destructive) {
                library.delete(book)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func moveMenu(for book: Book) -> some View {
        Menu {
            if book.folderID != nil {
                Button {
                    library.moveBook(book, to: nil)
                } label: {
                    Label("Unfiled", systemImage: "tray")
                }
            }
            ForEach(library.folders) { folder in
                Button {
                    library.moveBook(book, to: folder.id)
                } label: {
                    if book.folderID == folder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
        } label: {
            Label("Move to…", systemImage: "folder")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        let destination = importDestinationFolderID
        importDestinationFolderID = nil

        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let book = try BookImporter.importItem(from: url)
                library.add(book, to: destination)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct FolderDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let folderID: UUID
    @Binding var path: NavigationPath
    var onAddBook: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    private var folder: LibraryFolder? {
        library.folder(id: folderID)
    }

    private var books: [Book] {
        library.books(in: folderID)
    }

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("Empty folder", systemImage: "folder")
                } description: {
                    Text("Add a book here, or move one from the library.")
                } actions: {
                    Button("Add Book", action: onAddBook)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(books) { book in
                            Button {
                                path.append(LibraryRoute.book(book.id))
                            } label: {
                                BookCoverCell(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Menu {
                                    Button {
                                        library.moveBook(book, to: nil)
                                    } label: {
                                        Label("Unfiled", systemImage: "tray")
                                    }
                                    ForEach(library.folders) { other in
                                        Button {
                                            library.moveBook(book, to: other.id)
                                        } label: {
                                            if book.folderID == other.id {
                                                Label(other.name, systemImage: "checkmark")
                                            } else {
                                                Text(other.name)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Move to…", systemImage: "folder")
                                }
                                Button(role: .destructive) {
                                    library.delete(book)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(folder?.name ?? "Folder")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onAddBook) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Book")
            }
        }
    }
}

private struct FolderCell: View {
    let name: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }

            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count) book\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

private struct BookCoverCell: View {
    let book: Book
    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A fixed-size backdrop owns the layout so unusually tall or wide
            // covers get cropped instead of stretching the grid cell.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .overlay {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: book.kind == .pdf ? "doc.richtext" : "photo.on.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                // clipShape trims drawing only; clipped() keeps an oversized cover
                // from swallowing taps aimed at neighbouring cells.
                .clipped()

            Text(book.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(book.pageCount) pages")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .task(id: book.id) {
            cover = await loadCover()
        }
    }

    private func loadCover() async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let source = PageSourceFactory.make(for: book) else { return nil }
            return source.image(at: 0, maxPixelSize: 600)
        }.value
    }
}
