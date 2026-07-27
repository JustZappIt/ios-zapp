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

import ComposableArchitecture
import SwiftUI
import UIKit
import ZappMessaging

struct ChatImageViewer: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let actionIcon: CGFloat = 20
        static let actionTarget: CGFloat = 44
        static let actionSpacing: CGFloat = 8
        /// Fullscreen wants far more pixels than the 280pt bubble; still bounded so a huge
        /// photo cannot pin an unbounded bitmap.
        static let decodeMaxPixel: CGFloat = 2400
        static let dismissDistance: CGFloat = 120
        static let dismissFadeDistance: CGFloat = 400
        static let minBackgroundOpacity: CGFloat = 0.4
        static let confirmationSeconds: UInt64 = 2
    }

    /// What the save button last did, driving both its glyph and the line under it.
    private enum SaveOutcome: Equatable {
        case saving
        case saved
        case failed
    }

    @Dependency(\.photoLibrary) private var photoLibrary

    let message: ZMMessage
    let onDismiss: () -> Void

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var dragOffset: CGSize = .zero
    @State private var zoomScale: CGFloat = 1
    @State private var saveOutcome: SaveOutcome?

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            content
                .offset(dragOffset)

            actionBar
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

    /// Save then close, top-trailing — the same order and the same 44pt targets as Android's
    /// `Row(Alignment.TopEnd)`. Save is offered only when the real file is on disk; a
    /// thumbnail-only message has nothing worth writing to the library, which is exactly the
    /// `mediaLocalPath != null && exists()` condition Android gates its button on.
    private var actionBar: some View {
        VStack(alignment: .trailing, spacing: Design.Spacing._xs) {
            HStack(spacing: Constants.actionSpacing) {
                Spacer()

                if savableFileURL != nil {
                    actionButton(
                        icon: saveOutcome == .saved
                            ? Asset.Assets.Icons.checkSolid.image
                            : Asset.Assets.Icons.save.image,
                        tint: saveOutcome == .saved ? ZappColors.success.color(colorScheme) : .white,
                        label: String(localizable: .chatRoomImageViewerSave),
                        action: save
                    )
                    .disabled(saveOutcome == .saving)
                }

                actionButton(
                    icon: Asset.Assets.Icons.xClose.image,
                    tint: .white,
                    label: String(localizable: .generalClose),
                    action: onDismiss
                )
            }

            if let confirmation {
                Text(confirmation)
                    .zappFont(.caption, style: ZappColors.onAccent)
                    .padding(.horizontal, Design.Spacing._md)
                    .padding(.vertical, Design.Spacing._xs)
                    .background(ZappColors.overlay.color(colorScheme))
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding(Design.Spacing._lg)
        .animation(ZappMotion.content, value: saveOutcome)
    }

    private func actionButton(
        icon: Image,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: Constants.actionIcon, height: Constants.actionIcon)
                .foregroundColor(tint)
                .frame(width: Constants.actionTarget, height: Constants.actionTarget)
        }
        .buttonStyle(.zappPress)
        .accessibilityLabel(label)
    }

    /// The line Android shows as a Toast. It cannot be a `Toast` here: the viewer is a
    /// `fullScreenCover`, and the app's toast overlay lives on `RootView`, underneath it.
    private var confirmation: String? {
        switch saveOutcome {
        case .saved: return String(localizable: .chatRoomImageViewerSaved)
        case .failed: return String(localizable: .chatRoomImageViewerSaveFailed)
        case .saving, .none: return nil
        }
    }

    private var savableFileURL: URL? {
        guard let path = message.mediaLocalPath, FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private func save() {
        guard let url = savableFileURL, saveOutcome != .saving else { return }

        saveOutcome = .saving

        Task {
            do {
                try await photoLibrary.saveImage(url)
                saveOutcome = .saved
            } catch {
                LoggerProxy.error("ChatImageViewer: save to photo library failed")
                saveOutcome = .failed
            }

            try? await Task.sleep(nanoseconds: Constants.confirmationSeconds * 1_000_000_000)
            saveOutcome = nil
        }
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
