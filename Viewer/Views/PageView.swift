import SwiftUI

/// Pinch-zoom + pan for a single page image.
struct ZoomablePageView: View {
    let image: UIImage
    var onSwipeScreenLeft: (() -> Void)?
    var onSwipeScreenRight: (() -> Void)?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1.01 {
                            resetZoom()
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = lastScale * value
                scale = min(max(next, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 {
                    withAnimation(.easeOut(duration: 0.15)) {
                        resetZoom()
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                if scale > 1.01 {
                    lastOffset = offset
                    return
                }
                let threshold: CGFloat = 60
                if value.translation.width > threshold {
                    onSwipeScreenRight?()
                } else if value.translation.width < -threshold {
                    onSwipeScreenLeft?()
                }
            }
    }
}
