//
//  ChatRoomView.swift
//  Zapp
//

import ComposableArchitecture
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZappMessaging

/// The chat room is the one screen that keeps its back button in the header rather than in a
/// `ZappBottomActionBar`: the composer owns the bottom edge. `ChatRoomView.kt` does the same.
struct ChatRoomView: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Not `@FocusState`: nothing in the SwiftUI hierarchy is focusable, so SwiftUI would keep
    /// clearing it and the composer would resign the keyboard on the next keystroke.
    @State private var isComposerFocused = false
    @State private var hasPositioned = false
    @State private var isAtBottom = true

    @Perception.Bindable var store: StoreOf<ChatRoom>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: store.title,
                    subtitle: store.subtitle,
                    // A group's title opens group info; a DM's opens the peer's contact record
                    // (add / edit / block), so both are tappable now.
                    onTitleTap: { store.send(.titleTapped) }
                ) {
                    ZappBackButton {
                        navigateBack()
                    }
                } right: {
                    ChatNetworkStatusChip(
                        state: store.messagingState,
                        context: .room,
                        conversationId: store.conversationId
                    ) {
                        store.send(.networkChipTapped)
                    }
                }

                messages

                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))
                    .frame(height: 1)

                // A GIF can be several megabytes, so the composer says the send is under way
                // rather than looking idle until it lands.
                if store.isSendingMedia {
                    HStack(spacing: Design.Spacing._sm) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ZappColors.textSubtle.color(colorScheme))

                        Text(String(localizable: .chatRoomSendingMedia))
                            .zappFont(.caption, style: ZappColors.textSubtle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing._xl)
                    .padding(.top, Design.Spacing._md)
                    .background(ZappColors.surface.color(colorScheme))
                } else if store.sendDidFail {
                    // Strictly richer than the bare sentence this replaced: a denied camera
                    // permission is recoverable only from Settings, so the banner offers the
                    // same deep link `ScanView` does.
                    ChatSendFailureBanner(message: store.sendFailureMessage)
                }

                if let replyingTo = store.replyingTo {
                    ChatReplyBar(
                        senderName: store.state.replySenderName(for: replyingTo),
                        content: replyingTo.content,
                        onCancel: { store.send(.cancelReplyTapped) }
                    )
                }

                if let preview = store.draftLinkPreview {
                    ChatLinkPreviewCard(
                        preview: preview,
                        onCancel: { store.send(.dismissDraftLinkPreviewTapped) }
                    )
                }

                ChatRoomInputRow(
                    draft: $store.draft.sending(\.draftChanged),
                    isFocused: $isComposerFocused,
                    isSendEnabled: !store.trimmedDraft.isEmpty,
                    isMediaEnabled: !store.isSendingMedia,
                    showsGIFButton: store.isGIFSearchAvailable,
                    onAttach: {
                        isComposerFocused = false
                        store.send(.attachTapped)
                    },
                    onSend: { store.send(.sendTapped) },
                    onGIF: { store.send(.gifButtonTapped) },
                    onMediaPasted: { fileURL, type in
                        store.send(.mediaPasted(fileURL: fileURL, type: type))
                    }
                )
                // Mounted on the composer, not on the screen: SwiftUI honours one `.sheet` per
                // view, and the network-details sheet already owns the screen's slot.
                .sheet(
                    isPresented: Binding(
                        get: { store.showsAttachmentSheet },
                        set: { if !$0 { store.send(.attachmentSheetDismissed) } }
                    ),
                    // Only fires once the sheet is fully gone, which is the earliest a picker
                    // can be presented without iOS dropping it.
                    onDismiss: { store.send(.attachmentSheetClosed) }
                ) {
                    attachmentSheet
                }
                .photosPicker(
                    isPresented: Binding(
                        get: { store.showsPhotosPicker },
                        set: { if !$0 { store.send(.photosPickerDismissed) } }
                    ),
                    selection: $store.pickedItem.sending(\.pickedItemChanged),
                    matching: .images
                )
                .fileImporter(
                    isPresented: Binding(
                        get: { store.showsFileImporter },
                        set: { if !$0 { store.send(.fileImporterDismissed) } }
                    ),
                    // Android's document picker filters on `*/*`; `.item` is the same "anything".
                    allowedContentTypes: [.item]
                ) { result in
                    switch result {
                    case .success(let url):
                        store.send(.fileImported(url))

                    case .failure(let error):
                        LoggerProxy.error("Chat room file import failed: \(error)")
                        store.send(.mediaSendFailed)
                    }
                }
                .fullScreenCover(
                    isPresented: Binding(
                        get: { store.showsCamera },
                        set: { if !$0 { store.send(.cameraDismissed) } }
                    )
                ) {
                    ChatCameraPicker(
                        onCapture: { store.send(.cameraCaptured($0)) },
                        onCancel: { store.send(.cameraDismissed) }
                    )
                    .ignoresSafeArea()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack(action: navigateBack)
            .animation(ZappMotion.content, value: store.replyingTo)
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .sheet(
                isPresented: Binding(
                    get: { store.showsNetworkDetails },
                    set: { if !$0 { store.send(.networkDetailsDismissed) } }
                )
            ) {
                ChatNetworkDetailsView(
                    state: store.messagingState,
                    details: store.connectionDetails,
                    isLoading: store.isLoadingNetworkDetails,
                    onRefresh: { store.send(.networkChipTapped) }
                )
            }
            // Fullscreen rather than a sheet: a photo should own the screen, and the viewer
            // supplies its own dismiss (close button + drag-down).
            .fullScreenCover(
                isPresented: Binding(
                    get: { store.imageViewerMessage != nil },
                    set: { if !$0 { store.send(.imageViewerDismissed) } }
                )
            ) {
                if let message = store.imageViewerMessage {
                    ChatImageViewer(message: message) {
                        store.send(.imageViewerDismissed)
                    }
                }
            }
            .sheet(item: $store.scope(state: \.contactForm, action: \.contactForm)) { formStore in
                WithPerceptionTracking {
                    ChatContactFormView(store: formStore)
                }
            }
            .sheet(item: $store.scope(state: \.gifPicker, action: \.gifPicker)) { pickerStore in
                ChatGIFPickerView(store: pickerStore)
            }
        }
    }

    @ViewBuilder
    private var attachmentSheet: some View {
        Group {
            switch store.attachmentPage {
            case .actions:
                ChatAttachmentSheet(
                    isGroup: store.isGroup,
                    onShareAddress: { store.send(.shareAddressTapped) },
                    onSendZec: { store.send(.sendZecTapped) },
                    onSplitBill: { store.send(.splitBillTapped) },
                    onAttachMedia: { store.send(.attachMediaTapped, animation: ZappMotion.content) }
                )

            case .media:
                ChatMediaAttachmentSheet(
                    onChooseMedia: { store.send(.chooseMediaTapped) },
                    onAttachFile: { store.send(.attachFileTapped) },
                    onTakePhoto: { store.send(.takePhotoTapped) }
                )
            }
        }
        .padding(.horizontal, Design.Spacing._3xl)
        .padding(.bottom, Design.Spacing._3xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Design.Spacing._xl)
        .background(ZappColors.surface.color(colorScheme))
        .presentationDetents([.height(attachmentSheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var attachmentSheetHeight: CGFloat {
        switch store.attachmentPage {
        case .actions: return ChatAttachmentSheet.detentHeight
        case .media: return ChatMediaAttachmentSheet.detentHeight
        }
    }

    private func navigateBack() {
        isComposerFocused = false
        store.send(.backToHomeTapped, animation: ZappMotion.content)
    }

    private var items: [ChatRoomItem] {
        ChatRoomItem.build(
            from: store.visibleMessages,
            unreadSeparatorMessageId: store.unreadSeparatorMessageId
        )
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Design.Spacing._md) {
                    if store.isLoading && store.visibleMessages.isEmpty {
                        ProgressView()
                            .tint(ZappColors.accent.color(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(Design.Spacing._3xl)
                    }

                    ForEach(items) { item in
                        switch item {
                        case .message(let message):
                            ChatRoomBubbleRow(store: store, message: message)

                        case .separator(_, let label):
                            ChatDateSeparator(label: label)

                        case .unread:
                            ChatDateSeparator(label: String(localizable: .chatRoomUnreadMessages))
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ChatRoomItem.bottomId)
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.horizontal, Design.Spacing._xl)
                .padding(.bottom, Design.Spacing._md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isComposerFocused = false
            }
            // Mounted here because the composer's `.sheet` slot is taken by the attachment menu
            // and the screen's by the network details.
            .sheet(
                isPresented: Binding(
                    get: { store.splitBill != nil },
                    set: { if !$0 { store.send(.splitSheetDismissed) } }
                )
            ) {
                if let split = store.splitBill {
                    ChatSplitBillSheet(store: store, split: split)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            .onAppear {
                positionOnEntry(proxy)
            }
            .onChange(of: items.last?.id) { _ in
                positionOnNewMessage(proxy)
            }
            .onChange(of: isComposerFocused) { isFocused in
                guard isFocused, !items.isEmpty else { return }
                scroll(proxy, to: ChatRoomItem.bottomId, animated: true)
            }
        }
    }

    /// Entering lands on the first unread message when there is one — the marker is the point
    /// of the divider, and dropping past it to the newest message hides what was missed.
    private func positionOnEntry(_ proxy: ScrollViewProxy) {
        guard !items.isEmpty, !hasPositioned else { return }

        hasPositioned = true

        guard let unreadAnchorId else {
            scroll(proxy, to: ChatRoomItem.bottomId, animated: false)
            return
        }

        // Anchored to the top so the unread run sits below the divider, not above it.
        scroll(proxy, to: unreadAnchorId, anchor: .top, animated: false)
    }

    /// Following the newest message while the user is reading history yanks them out of it, so
    /// only own sends and an already-pinned view scroll. Mirrors `shouldFollowLatest`.
    private func positionOnNewMessage(_ proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }

        guard hasPositioned else {
            positionOnEntry(proxy)
            return
        }

        guard isAtBottom || store.visibleMessages.last?.isFromMe == true else { return }

        scroll(proxy, to: ChatRoomItem.bottomId, animated: true)
    }

    private var unreadAnchorId: String? {
        for item in items {
            if case .unread(let id) = item { return id }
        }

        return nil
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String, anchor: UnitPoint = .bottom, animated: Bool) {
        Task { @MainActor in
            // Let the lazy stack lay out its newly loaded rows before resolving the anchor.
            // Scrolling during the same update can otherwise leave the room several rows short.
            await Task.yield()

            guard animated else {
                proxy.scrollTo(id, anchor: anchor)
                return
            }

            withAnimation(ZappMotion.content) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }
}

private enum ChatRoomItem: Identifiable, Equatable {
    case message(ZMMessage)
    case separator(id: String, label: String)
    case unread(id: String)

    static let bottomId = "chat_room_bottom"

    var id: String {
        switch self {
        case .message(let message): return "msg_\(message.id)"
        case .separator(let id, _): return id
        case .unread(let id): return id
        }
    }

    /// The separator id carries the index: a duplicate day key must not collide and tear the list.
    static func build(
        from messages: [ZMMessage],
        unreadSeparatorMessageId: String?,
        calendar: Calendar = .current
    ) -> [ChatRoomItem] {
        var items: [ChatRoomItem] = []
        var lastDay: Date?

        for (index, message) in messages.enumerated() {
            let day = calendar.startOfDay(for: message.timestamp)

            if day != lastDay {
                items.append(
                    .separator(
                        id: "sep_\(day.timeIntervalSince1970)_\(index)",
                        label: ChatDateSeparator.label(for: message.timestamp)
                    )
                )
                lastDay = day
            }

            if message.id == unreadSeparatorMessageId {
                items.append(.unread(id: "unread_\(message.id)"))
            }

            items.append(.message(message))
        }

        return items
    }
}

private struct ChatRoomInputRow: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let inputHorizontalPadding: CGFloat = 12
        /// 8, not 10: 28pt of GIF button plus 16 keeps the box on the same 44 as before.
        static let inputVerticalPadding: CGFloat = 8
        static let sendIconSize: CGFloat = 24
        static let minHeight: CGFloat = 44
        static let disabledOpacity: CGFloat = 0.45
        static let maxLines = 5
    }

    @Binding var draft: String
    @Binding var isFocused: Bool
    let isSendEnabled: Bool
    let isMediaEnabled: Bool
    let showsGIFButton: Bool
    /// The "+" opens the attachment sheet rather than mounting a `PhotosPicker` of its own — the
    /// gallery is one option among several there, and the sheet is presented from the store.
    let onAttach: () -> Void
    let onSend: () -> Void
    let onGIF: () -> Void
    let onMediaPasted: (URL, UTType) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Design.Spacing._md) {
            // "+" used to mount a `PhotosPicker` directly; it now opens the attachment sheet,
            // where the gallery is one of several options (Android's `onAttachClick`).
            Button(action: onAttach) {
                ChatAttachGlyph()
            }
            .buttonStyle(.zappPress)
            .disabled(!isMediaEnabled)
            .opacity(isMediaEnabled ? 1 : Constants.disabledOpacity)
            .accessibilityLabel(String(localizable: .chatRoomAttach))

            inputBox

            // An up arrow rather than the word "Send", and dimmed by colour rather than opacity —
            // `ChatRoomInputRow.kt` draws the same square.
            //
            // Android pulses on the send CLICK, not on delivery — the tap is what the user is
            // acknowledging, and a message that fails still surfaces its own failure row.
            Button {
                ZappHaptics.sendConfirm()
                onSend()
            } label: {
                Asset.Assets.Icons.arrowUp.image
                    .zImage(
                        width: Constants.sendIconSize,
                        height: Constants.sendIconSize,
                        style: isSendEnabled ? ZappColors.onAccent : ZappColors.textSubtle
                    )
                    .frame(width: Constants.minHeight, height: Constants.minHeight)
                    .background((isSendEnabled ? ZappColors.accent : ZappColors.surfaceAlt).color(colorScheme))
                    .overlay {
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    }
                    .animation(ZappMotion.state, value: isSendEnabled)
            }
            .buttonStyle(.zappPress)
            .disabled(!isSendEnabled)
            .accessibilityLabel(String(localizable: .chatRoomSend))
        }
        .padding(.horizontal, Design.Spacing._lg)
        .padding(.top, Design.Spacing._md)
        .padding(.bottom, Design.Spacing._xs)
        .background {
            // Keep the composer visually attached to the bottom edge while its controls remain
            // above the home indicator. The keyboard replaces that system inset automatically.
            ZappColors.surface.color(colorScheme)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private var inputBox: some View {
        HStack(alignment: .bottom, spacing: Design.Spacing._sm) {
            // UIKit rather than TextField: a pasted image arrives through
            // paste(itemProviders:), which SwiftUI's field cannot receive.
            ChatComposerTextView(
                text: $draft,
                isFocused: $isFocused,
                placeholder: String(localizable: .chatRoomInputPlaceholder),
                maxLines: Constants.maxLines,
                onMediaPasted: onMediaPasted
            )

            if showsGIFButton {
                Button(action: onGIF) {
                    ChatGIFGlyph()
                }
                .buttonStyle(.zappPress)
                .disabled(!isMediaEnabled)
                .opacity(isMediaEnabled ? 1 : Constants.disabledOpacity)
                .accessibilityLabel(String(localizable: .chatRoomSendGif))
            }
        }
        .padding(.horizontal, Constants.inputHorizontalPadding)
        .padding(.vertical, Constants.inputVerticalPadding)
        .frame(minHeight: Constants.minHeight)
        .background {
            // A tap on the box's padding missed the field entirely and read as an ignored tap.
            ZappColors.surfaceInput.color(colorScheme)
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }
        }
    }
}

private extension ZappTextStyle {
    static let attachGlyph = ZappTextStyle(weight: .medium, size: 22, lineHeight: 24)
    static let gifGlyph = ZappTextStyle(weight: .bold, size: 10, lineHeight: 12, tracking: 0.4)
}

private struct ChatAttachGlyph: View {
    static let size: CGFloat = 44

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: "+")
            .zappFont(.attachGlyph, style: ZappColors.text)
            .frame(width: ChatAttachGlyph.size, height: ChatAttachGlyph.size)
            .background(ZappColors.surfaceInput.color(colorScheme))
    }
}

/// Lettered rather than an icon — the catalogue has no GIF mark. It sits inside the field, so it
/// carries no background of its own.
private struct ChatGIFGlyph: View {
    static let width: CGFloat = 32
    static let height: CGFloat = 28

    var body: some View {
        Text(String(localizable: .chatRoomGif))
            .zappFont(.gifGlyph, style: ZappColors.textSubtle)
            .frame(width: Self.width, height: Self.height)
            .contentShape(Rectangle())
    }
}

#Preview {
    ChatRoomView(store: ChatRoom.initial)
}
