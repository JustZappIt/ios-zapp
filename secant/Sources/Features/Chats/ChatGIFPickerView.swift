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
        static let iconSize: CGFloat = 16
        static let closeSize: CGFloat = 36
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
        HStack(spacing: Design.Spacing._sm) {
            Asset.Assets.Icons.search.image
                .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.textSubtle)

            TextField(
                String(localizable: .chatGifPickerSearchPlaceholder),
                text: Binding(
                    get: { store.query },
                    set: { store.send(.queryChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)

            if !store.query.isEmpty {
                Button {
                    store.send(.clearQueryTapped)
                } label: {
                    Asset.Assets.Icons.xClose.image
                        .zImage(width: 12, height: 12, style: ZappColors.textSubtle)
                }
                .buttonStyle(.zappPress)
                .accessibilityLabel(String(localizable: .generalClear))
            }
        }
        .padding(.horizontal, Design.Spacing._md)
        .padding(.vertical, Design.Spacing._lg)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        }
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
                }
            }
            .padding(.bottom, Design.Spacing._3xl)
        }
        .scrollDismissesKeyboard(.immediately)
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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var player = ChatDataGIFPlayer()

    let gif: KlipyGIF
    let height: CGFloat

    private var blur: UIImage? {
        gif.blurPreview.flatMap { ChatMediaImage.downsampled(data: $0, maxPixel: Self.blurPixel) }
    }

    private static let blurPixel: CGFloat = 64

    var body: some View {
        ZStack {
            ZappColors.surfaceInput.color(colorScheme)

            if let blur {
                Image(uiImage: blur)
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
        .task(id: gif.id) { await player.play(gif) }
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
