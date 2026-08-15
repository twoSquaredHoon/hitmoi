import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var currentPage: Int
    @State private var showChrome = true
    @State private var pageImage: UIImage?
    @State private var isLoadingFirstPage = false
    @State private var source: PageSource?
    @State private var cache = PageCache(capacity: 9)
    @State private var maxPixelSize: CGFloat = 2048
    @State private var loadGeneration = 0

    init(book: Book) {
        self.book = book
        let initial = min(max(0, book.lastPage), max(0, book.pageCount - 1))
        _currentPage = State(initialValue: initial)
    }

    private var pageCount: Int {
        source?.pageCount ?? book.pageCount
    }

    private var pageLabel: String {
        guard pageCount > 0 else { return "0 / 0" }
        return "\(currentPage + 1) / \(pageCount)"
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
            .onAppear {
                // Fit screen pixels (+ a little headroom for light zoom), capped for speed.
                let longest = max(geo.size.width, geo.size.height)
                maxPixelSize = min(longest * UIScreen.main.scale * 1.25, 3072)
            }
        }
        .statusBarHidden(!showChrome)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            source = PageSourceFactory.make(for: book)
            await presentPage(currentPage, isInitial: true)
        }
        .onChange(of: currentPage) { _, newValue in
            library.updateLastPage(bookID: book.id, page: newValue)
            Task { await presentPage(newValue, isInitial: false) }
        }
        .onDisappear {
            library.flush()
        }
    }

    @ViewBuilder
    private func pageLayer(size: CGSize) -> some View {
        Group {
            if let pageImage {
                ZoomablePageView(
                    image: pageImage,
                    onSwipeScreenLeft: { handleScreenSwipeLeft() },
                    onSwipeScreenRight: { handleScreenSwipeRight() }
                )
                .id(currentPage)
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

                Color.clear.frame(width: 36, height: 36)
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
            switch library.readingDirection {
            case .rtl: turnPage(+1)
            case .ltr: turnPage(-1)
            }
        } else if location.x > trailingCutoff {
            switch library.readingDirection {
            case .rtl: turnPage(-1)
            case .ltr: turnPage(+1)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                showChrome.toggle()
            }
        }
    }

    private func handleScreenSwipeLeft() {
        switch library.readingDirection {
        case .ltr: turnPage(+1)
        case .rtl: turnPage(-1)
        }
    }

    private func handleScreenSwipeRight() {
        switch library.readingDirection {
        case .ltr: turnPage(-1)
        case .rtl: turnPage(+1)
        }
    }

    private func turnPage(_ delta: Int) {
        let next = currentPage + delta
        guard next >= 0, next < pageCount else { return }
        currentPage = next
        showChrome = false
    }

    private func presentPage(_ index: Int, isInitial: Bool) async {
        guard let source else {
            pageImage = nil
            return
        }

        if let cached = cache.image(at: index) {
            pageImage = cached
            isLoadingFirstPage = false
            prefetchAround(index, source: source)
            return
        }

        if isInitial || pageImage == nil {
            isLoadingFirstPage = true
        }

        loadGeneration += 1
        let generation = loadGeneration
        let pixelSize = maxPixelSize

        let image = await Task.detached(priority: .userInitiated) {
            source.image(at: index, maxPixelSize: pixelSize)
        }.value

        guard generation == loadGeneration, index == currentPage else { return }

        if let image {
            cache.store(image, at: index)
            pageImage = image
        } else if pageImage == nil {
            pageImage = nil
        }
        isLoadingFirstPage = false
        prefetchAround(index, source: source)
    }

    private func prefetchAround(_ index: Int, source: PageSource) {
        let neighbors = [index - 1, index + 1, index + 2].filter { $0 >= 0 && $0 < pageCount }
        let pixelSize = maxPixelSize
        let cache = cache

        Task.detached(priority: .utility) {
            for neighbor in neighbors {
                if cache.image(at: neighbor) != nil { continue }
                if let image = source.image(at: neighbor, maxPixelSize: pixelSize) {
                    cache.store(image, at: neighbor)
                }
            }
        }
    }
}
