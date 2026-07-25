//
//  ChatImageViewer.swift
//  Zapp
//
//  Android's `view/ImageViewerOverlay.kt` — a fullscreen viewer with zoom and a dismiss.
//  Android hand-rolls pan/zoom with `detectTransformGestures`; iOS gets the real thing from a
//  `UIScrollView`, which brings rubber-banding, momentum and double-tap-to-zoom for free
//  (Appendix C.3, approved).
//
//  The image degrades the same way the bubble's does: the transferred file, else the wire
//  thumbnail, else nothing.
//

import SwiftUI
import UIKit
import ZappMessaging

struct ChatImageViewer: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let closeIcon: CGFloat = 20
        static let closeTarget: CGFloat = 44
        /// Fullscreen wants far more pixels than the 280pt bubble; still bounded so a huge
        /// photo cannot pin an unbounded bitmap.
        static let decodeMaxPixel: CGFloat = 2400
        static let dismissDistance: CGFloat = 120
        static let dismissFadeDistance: CGFloat = 400
        static let minBackgroundOpacity: CGFloat = 0.4
    }

    let message: ZMMessage
    let onDismiss: () -> Void

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var dragOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            content
                .offset(dragOffset)

            closeButton
        }
        // A drag only dismisses at rest: once zoomed in, the pan belongs to the image.
        .gesture(zoomScale <= 1 ? dismissDrag : nil)
        .task(id: message.id) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            ChatZoomableImage(image: image, zoomScale: $zoomScale)
                .ignoresSafeArea()
        } else if didFail {
            Text(String(localizable: .chatRoomImageFailed))
                .zappFont(.body, style: ZappColors.textMuted)
        } else {
            ProgressView()
                .tint(ZappColors.accent.color(colorScheme))
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()

                Button(action: onDismiss) {
                    Asset.Assets.Icons.xClose.image
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: Constants.closeIcon, height: Constants.closeIcon)
                        .foregroundColor(.white)
                        .frame(width: Constants.closeTarget, height: Constants.closeTarget)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .generalClose))
            }

            Spacer()
        }
        .padding(Design.Spacing._lg)
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                // Vertical only: a horizontal swipe here would fight the room's edge-back.
                dragOffset = CGSize(width: 0, height: value.translation.height)
            }
            .onEnded { value in
                if abs(value.translation.height) > Constants.dismissDistance {
                    onDismiss()
                } else {
                    withAnimation(ZappMotion.content) { dragOffset = .zero }
                }
            }
    }

    /// The backdrop thins out as the photo is dragged away, so the room behind it reads through
    /// before the dismiss commits.
    private var backgroundOpacity: CGFloat {
        let progress = min(abs(dragOffset.height) / Constants.dismissFadeDistance, 1)

        return max(1 - progress, Constants.minBackgroundOpacity)
    }

    private func load() async {
        let path = message.mediaLocalPath
        let thumbnailData = message.thumbnailData
        let maxPixel = Constants.decodeMaxPixel

        let decoded = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let path, let full = ChatMediaImage.downsampled(path: path, maxPixel: maxPixel) {
                return full
            }

            return ChatMediaImage.decodeThumbnail(thumbnailData)
        }
        .value

        image = decoded
        didFail = decoded == nil
    }
}

/// `UIScrollView` purely for its zoom: pinch, double-tap and pan all behave the way they do in
/// Photos, which no reasonable amount of SwiftUI gesture code would match.
private struct ChatZoomableImage: UIViewRepresentable {
    private enum Constants {
        static let maxZoom: CGFloat = 4
        static let doubleTapZoom: CGFloat = 2.5
    }

    let image: UIImage
    @Binding var zoomScale: CGFloat

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = Constants.maxZoom
        scrollView.minimumZoomScale = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.doubleTapZoom = Constants.doubleTapZoom

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var doubleTapZoom: CGFloat = 2.5

        private let zoomScale: Binding<CGFloat>

        init(zoomScale: Binding<CGFloat>) {
            self.zoomScale = zoomScale
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale.wrappedValue = scrollView.zoomScale
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / doubleTapZoom,
                    height: scrollView.bounds.height / doubleTapZoom
                )
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}
