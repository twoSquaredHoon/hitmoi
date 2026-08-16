import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var currentPage: Int
    @State private var showChrome = true
    @State private var displayedPages: [Int] = []
    @State private var displayedImages: [UIImage] = []
    @State private var isLoadingFirstPage = false
    @State private var source: PageSource?
    @State private var cache = PageCache(capacity: 12)
    @State private var maxPixelSize: CGFloat = 2048
    @State private var loadGeneration = 0
    @State private var isLandscape = false

    init(book: Book) {
        self.book = book
        let initial = min(max(0, book.lastPage), max(0, book.pageCount - 1))
        _currentPage = State(initialValue: initial)
    }

    private var pageCount: Int {
        source?.pageCount ?? book.pageCount
    }

    private var isDualActive: Bool {
        library.dualPageEnabled && isLandscape && pageCount > 1
    }

    private var visiblePages: [Int] {
        displayedPages.isEmpty ? [currentPage] : displayedPages
    }

    private var pageLabel: String {
        guard pageCount > 0 else { return "0 / 0" }
        let pages = visiblePages
        if pages.count > 1, let first = pages.first, let last = pages.last {
            return "\(first + 1)–\(last + 1) / \(pageCount)"
        }
        return "\((pages.first ?? 0) + 1) / \(pageCount)"
    }

    private var pairingLabel: String {
        library.pairOffset == 0 ? "Pairing: 1–2, 3–4" : "Pairing: 2–3, 4–5"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                pageLayer(size: geo.size)

                if showChrome {
                    chromeOverlay
                }
            }
            .onAppear { updateLayout(for: geo.size) }
            .onChange(of: geo.size) { _, newSize in updateLayout(for: newSize) }
        }
        .statusBarHidden(!showChrome)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            source = PageSourceFactory.make(for: book)
            await presentCurrent(isInitial: true)
        }
        .onChange(of: currentPage) { _, newValue in
            library.updateLastPage(bookID: book.id, page: newValue)
            Task { await presentCurrent(isInitial: false) }
        }
        .onChange(of: isDualActive) { _, _ in
            Task { await presentCurrent(isInitial: false) }
        }
        .onChange(of: library.pairOffset) { _, _ in
            Task { await presentCurrent(isInitial: false) }
        }
        .onDisappear {
            library.flush()
        }
    }

    @ViewBuilder
    private func pageLayer(size: CGSize) -> some View {
        Group {
            if !displayedImages.isEmpty {
                ZoomableSpreadView(
                    images: orderedImages,
                    onSwipeScreenLeft: { handleScreenSwipeLeft() },
                    onSwipeScreenRight: { handleScreenSwipeRight() }
                )
                .id(spreadIdentity)
            } else if isLoadingFirstPage {
                ProgressView()
                    .tint(.white)
            } else {
                Text("Unable to load page")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded { event in
                    handleTap(at: event.location, in: size)
                }
        )
    }

    /// Right-to-left books read the earlier page on the right side of the spread.
    private var orderedImages: [UIImage] {
        guard displayedImages.count > 1, library.readingDirection == .rtl else {
            return displayedImages
        }
        return displayedImages.reversed()
    }

    private var spreadIdentity: String {
        visiblePages.map(String.init).joined(separator: "-") + "|\(library.readingDirection.rawValue)"
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Back")

                Spacer()

                VStack(spacing: 2) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(pageLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                readerMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55))

            Spacer()

            if pageCount > 1 {
                Slider(
                    value: Binding(
                        get: { Double(currentPage) },
                        set: { currentPage = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(pageCount - 1, 0)),
                    step: 1
                )
                .tint(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.black.opacity(0.55))
            }
        }
    }

    private var readerMenu: some View {
        Menu {
            Toggle("Two pages in landscape", isOn: $library.dualPageEnabled)

            Button {
                library.pairOffset = library.pairOffset == 0 ? 1 : 0
            } label: {
                Label(pairingLabel, systemImage: "book.pages")
            }
            .disabled(!isDualActive)

            Picker("Reading direction", selection: $library.readingDirection) {
                ForEach(LibraryStore.ReadingDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Reader options")
    }

    private func updateLayout(for size: CGSize) {
        isLandscape = size.width > size.height
        // Screen's longest edge is stable across rotation, so cached pages stay valid.
        let longest = max(size.width, size.height)
        maxPixelSize = min(longest * UIScreen.main.scale * 1.25, 3072)
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        if showChrome {
            let topBand: CGFloat = 88
            let bottomBand: CGFloat = 110
            if location.y < topBand || location.y > size.height - bottomBand {
                return
            }
        }

        let leadingCutoff = size.width * 0.36
        let trailingCutoff = size.width * 0.64

        if location.x < leadingCutoff {
            turn(forward: library.readingDirection == .rtl)
        } else if location.x > trailingCutoff {
            turn(forward: library.readingDirection == .ltr)
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                showChrome.toggle()
            }
        }
    }

    private func handleScreenSwipeLeft() {
        turn(forward: library.readingDirection == .ltr)
    }

    private func handleScreenSwipeRight() {
        turn(forward: library.readingDirection == .rtl)
    }

    /// Pages shown together for a given index, honoring the pairing offset.
    private func spreadPages(for index: Int) -> [Int] {
        guard isDualActive else { return [index] }
        let offset = library.pairOffset
        guard index >= offset else { return [index] }

        let start = offset + ((index - offset) / 2) * 2
        let second = start + 1
        return second < pageCount ? [start, second] : [start]
    }

    private func turn(forward: Bool) {
        let pages = spreadPages(for: currentPage)
        guard let first = pages.first, let last = pages.last else { return }

        if forward {
            let next = last + 1
            guard next < pageCount else { return }
            currentPage = next
        } else {
            let previous = first - 1
            guard previous >= 0 else { return }
            currentPage = spreadPages(for: previous).first ?? previous
        }
        showChrome = false
    }

    private func presentCurrent(isInitial: Bool) async {
        guard let source else {
            displayedImages = []
            return
        }

        let pages = spreadPages(for: currentPage)
        displayedPages = pages

        let cached = pages.compactMap { cache.image(at: $0) }
        if cached.count == pages.count {
            displayedImages = cached
            isLoadingFirstPage = false
            prefetch(around: pages, source: source)
            return
        }

        if isInitial || displayedImages.isEmpty {
            isLoadingFirstPage = true
        }

        loadGeneration += 1
        let generation = loadGeneration
        let pixelSize = maxPixelSize
        let pageCache = cache

        let images = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
            pages.compactMap { index in
                if let hit = pageCache.image(at: index) { return hit }
                guard let image = source.image(at: index, maxPixelSize: pixelSize) else { return nil }
                pageCache.store(image, at: index)
                return image
            }
        }.value

        guard generation == loadGeneration else { return }

        displayedImages = images
        isLoadingFirstPage = false
        prefetch(around: pages, source: source)
    }

    private func prefetch(around pages: [Int], source: PageSource) {
        guard let first = pages.first, let last = pages.last else { return }

        let targets = [last + 1, last + 2, first - 1, first - 2]
            .filter { $0 >= 0 && $0 < pageCount }
        guard !targets.isEmpty else { return }

        let pixelSize = maxPixelSize
        let pageCache = cache

        Task.detached(priority: .utility) {
            for target in targets where pageCache.image(at: target) == nil {
                if let image = source.image(at: target, maxPixelSize: pixelSize) {
                    pageCache.store(image, at: target)
                }
            }
        }
    }
}
