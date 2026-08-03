//
//  ChatGIFPickerView.swift
//  Zapp
//

import ComposableArchitecture
import ImageIO
import SwiftUI

struct ChatGIFPickerView: View {
    private enum Constants {
        static let columns = 2
        static let cellSpacing: CGFloat = 8
        static let cellHeight: CGFloat = 120
        static let closeSize: CGFloat = 36
        /// How far from the end a cell has to appear before the next page is asked for.
        static let prefetchDistance = 4
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @Perception.Bindable var store: StoreOf<ChatGIFPicker>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: Design.Spacing._lg) {
                header
                searchField
                results
                attribution
            }
            .padding(.horizontal, Design.Spacing._xl)
            .background(ZappColors.bg.color(colorScheme))
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear { store.send(.onAppear) }
        }
    }

    private var header: some View {
        HStack {
            Text(String(localizable: .chatGifPickerTitle))
                .zappFont(.sectionTitle, style: ZappColors.text)

            Spacer()

            Button(action: { dismiss() }) {
                Asset.Assets.Icons.xClose.image
                    .zImage(width: 14, height: 14, style: ZappColors.text)
                    .frame(width: Constants.closeSize, height: Constants.closeSize)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .generalClose))
        }
        .padding(.top, Design.Spacing._lg)
    }

    private var searchField: some View {
        ZappSearchField(
            placeholder: String(localizable: .chatGifPickerSearchPlaceholder),
            text: Binding(
                get: { store.query },
                set: { store.send(.queryChanged($0)) }
            ),
            onClear: { store.send(.clearQueryTapped) }
        )
    }

    /// Required by Klipy's API terms, alongside the "Search KLIPY" placeholder.
    private var attribution: some View {
        Text(String(localizable: .chatGifPickerAttribution))
            .zappFont(.caption, style: ZappColors.textSubtle)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Design.Spacing._md)
    }

    @ViewBuilder private var results: some View {
        if store.isLoading && store.results.isEmpty {
            placeholder { ProgressView().tint(ZappColors.accent.color(colorScheme)) }
        } else if store.didFail {
            placeholder {
                Text(String(localizable: .chatGifPickerFailed))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
            }
        } else if store.isEmpty {
            placeholder {
                Text(String(localizable: .chatGifPickerNoResults))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Constants.cellSpacing),
                    count: Constants.columns
                ),
                spacing: Constants.cellSpacing
            ) {
                ForEach(store.results) { gif in
                    Button {
                        store.send(.gifTapped(gif))
                    } label: {
                        ChatGIFPickerCell(gif: gif, height: Constants.cellHeight)
                    }
                    .buttonStyle(.zappPress)
                    .accessibilityLabel(gif.title)
                    .onAppear {
                        guard gif.id == prefetchTriggerId else { return }

                        store.send(.reachedEnd)
                    }
                }
            }

            if store.isLoadingMore {
                ProgressView()
                    .tint(ZappColors.accent.color(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Spacing._lg)
            }

            Color.clear.frame(height: Design.Spacing._3xl)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var prefetchTriggerId: KlipyGIF.ID? {
        store.results.dropLast(Constants.prefetchDistance).last?.id ?? store.results.last?.id
    }

    private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Design.Spacing._xl)
    }
}

private struct ChatGIFPickerCell: View {
    private static let blurPixel: CGFloat = 64

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var player = ChatDataGIFPlayer()
    /// Decoded once rather than per redraw: the animated frame republishes ten times a second,
    /// and a computed decode would run ImageIO that often on the main thread.
    @State private var blur: CGImage?

    let gif: KlipyGIF
    let height: CGFloat

    var body: some View {
        ZStack {
            ZappColors.surfaceInput.color(colorScheme)

            if let blur {
                Image(decorative: blur, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            if let frame = player.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .task(id: gif.id) {
            if let data = gif.blurPreview {
                blur = await ChatDataGIFDecoder.still(data, maxPixel: Self.blurPixel)?.image
            }

            await player.play(gif)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await player.play(gif) }
            } else {
                player.stop()
            }
        }
        .onDisappear { player.stop() }
    }
}

/// Streams one downsampled frame at a time out of an in-memory GIF, the same bounded shape the
/// message bubble uses for files. A grid of fully decoded previews would cost tens of megabytes.
@MainActor
private final class ChatDataGIFPlayer: ObservableObject {
    @Published private(set) var frame: CGImage?

    private var playbackTask: Task<Void, Never>?

    func play(_ gif: KlipyGIF) async {
        stop()

        @Dependency(\.klipyGIF) var klipyGIF

        guard let data = try? await klipyGIF.preview(gif), !Task.isCancelled else { return }

        playbackTask = Task { [weak self] in
            guard let descriptor = await ChatDataGIFDecoder.descriptor(data) else { return }

            var index = 0

            while !Task.isCancelled {
                guard let decoded = await ChatDataGIFDecoder.frame(data, index: index) else { return }
                guard !Task.isCancelled else { return }

                self?.frame = decoded.image

                do {
                    try await Task.sleep(for: .seconds(descriptor.delays[index]))
                } catch {
                    return
                }

                index = (index + 1) % descriptor.delays.count
            }
        }
    }

    /// Unlike the bubble's player this keeps the last frame, so a cell scrolling back into view or
    /// a return from the background resumes on the image rather than flashing the placeholder.
    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
    }
}

private enum ChatDataGIFDecoder {
    struct Descriptor: Sendable {
        let delays: [Double]
    }

    struct Frame: @unchecked Sendable {
        let image: CGImage
    }

    private static let maxFrames = 200
    private static let maxPixel: CGFloat = 320
    private static let defaultDelay = 0.1
    private static let minimumDelay = 0.05
    private static let maximumDelay = 10.0

    static func descriptor(_ data: Data) async -> Descriptor? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, ChatMediaImage.sourceOptions) else {
                    return nil
                }

                let frameCount = CGImageSourceGetCount(source)
                guard frameCount > 0, frameCount <= maxFrames else { return nil }

                var delays: [Double] = []
                delays.reserveCapacity(frameCount)

                for index in 0..<frameCount {
                    guard ChatMediaImage.sourceIsWithinPixelLimit(source, index: index) else { return nil }

                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    let rawDelay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                        ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                        ?? defaultDelay
                    let finiteDelay = rawDelay.isFinite ? rawDelay : defaultDelay

                    delays.append(min(max(finiteDelay, minimumDelay), maximumDelay))
                }

                return Descriptor(delays: delays)
            }
        }
        .value
    }

    static func frame(_ data: Data, index: Int) async -> Frame? {
        await thumbnail(data, index: index, maxPixel: maxPixel)
    }

    static func still(_ data: Data, maxPixel: CGFloat) async -> Frame? {
        await thumbnail(data, index: 0, maxPixel: maxPixel)
    }

    private static func thumbnail(_ data: Data, index: Int, maxPixel: CGFloat) async -> Frame? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard
                    let source = CGImageSourceCreateWithData(data as CFData, ChatMediaImage.sourceOptions),
                    index >= 0,
                    index < CGImageSourceGetCount(source),
                    let image = CGImageSourceCreateThumbnailAtIndex(
                        source,
                        index,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixel
                        ] as CFDictionary
                    )
                else {
                    return nil
                }

                return Frame(image: image)
            }
        }
        .value
    }
}
