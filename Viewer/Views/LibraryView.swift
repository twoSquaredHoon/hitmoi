import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var isImporting = false
    @State private var importError: String?
    @State private var path = NavigationPath()

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else {
                    bookGrid
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Reading direction", selection: $library.readingDirection) {
                            ForEach(LibraryStore.ReadingDirection.allCases) { direction in
                                Text(direction.label).tag(direction)
                            }
                        }
                    } label: {
                        Image(systemName: "text.justify.leading")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Book")
                }
            }
            .navigationDestination(for: UUID.self) { bookID in
                if let book = library.book(id: bookID) {
                    ReaderView(book: book)
                } else {
                    Text("Book not found")
                        .foregroundStyle(.secondary)
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
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No books yet", systemImage: "books.vertical")
        } description: {
            Text("Add a folder of images or a PDF to start reading.")
        } actions: {
            Button("Add Book") { isImporting = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(library.books) { book in
                    Button {
                        path.append(book.id)
                    } label: {
                        BookCoverCell(book: book)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let book = try BookImporter.importItem(from: url)
                library.add(book)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct BookCoverCell: View {
    let book: Book
    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.12))

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
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(book.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("\(book.pageCount) pages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
