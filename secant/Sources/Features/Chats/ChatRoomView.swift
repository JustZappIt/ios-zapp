//
//  ChatRoomView.swift
//  Zapp
//

import ComposableArchitecture
import PhotosUI
import SwiftUI
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

    /// Matches the media bubble, so a link card and a photo line up on the same edge.
    private let linkPreviewWidth: CGFloat = 280

    @Perception.Bindable var store: StoreOf<ChatRoom>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: store.title,
                    subtitle: store.subtitle,
                    onTitleTap: store.isGroup ? { store.send(.titleTapped) } : nil
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

                if store.sendDidFail {
                    Text(store.sendFailureMessage ?? String(localizable: .chatRoomSendFailed))
                        .zappFont(.caption, style: ZappColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Design.Spacing._xl)
                        .padding(.top, Design.Spacing._md)
                        .background(ZappColors.surface.color(colorScheme))
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
                    pickedItem: $store.pickedItem.sending(\.pickedItemChanged),
                    isFocused: $isComposerFocused,
                    isSendEnabled: !store.trimmedDraft.isEmpty,
                    isMediaEnabled: !store.isSendingMedia,
                    showsGIFButton: store.isGIFSearchAvailable,
                    onSend: { store.send(.sendTapped) },
                    onGIF: { store.send(.gifButtonTapped) },
                    onMediaPasted: { fileURL, type in
                        store.send(.mediaPasted(fileURL: fileURL, type: type))
                    }
                )
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
            .sheet(item: $store.scope(state: \.gifPicker, action: \.gifPicker)) { pickerStore in
                ChatGIFPickerView(store: pickerStore)
            }
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
                            bubble(for: message)

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

    @ViewBuilder
    private func bubble(for message: ZMMessage) -> some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: Design.Spacing._xxs) {
            if let mediaId = message.mediaId {
                ChatMediaBubble(
                    message: message,
                    senderName: store.state.senderName(for: message),
                    progress: store.mediaProgress[mediaId],
                    readReceiptsEnabled: store.messagingState.readReceiptsEnabled
                )
            } else {
                ChatMessageBubble(
                    message: message,
                    senderName: store.state.senderName(for: message),
                    readReceiptsEnabled: store.messagingState.readReceiptsEnabled
                )

                if let preview = store.messageLinkPreviews[message.id] {
                    ChatLinkPreviewCard(preview: preview)
                        .frame(maxWidth: linkPreviewWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
        .onAppear { store.send(.messageAppeared(message)) }
        .contentShape(Rectangle())
        .onTapGesture {
            if message.isFromMe && message.status == "failed" {
                store.send(.retrySendTapped(message))
            }
        }
        .contextMenu {
            if message.isFromMe && message.status == "failed" {
                Button(String(localizable: .chatRoomRetry)) {
                    store.send(.retrySendTapped(message))
                }
            }
            Button(String(localizable: .chatRoomReply)) {
                store.send(.replyTapped(message))
            }
            if !message.content.isEmpty {
                Button(String(localizable: .chatRoomCopyMessage)) {
                    store.send(.copyMessageTapped(message))
                }
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
        static let inputVerticalPadding: CGFloat = 10
        static let sendHorizontalPadding: CGFloat = 16
        static let sendVerticalPadding: CGFloat = 12
        static let minHeight: CGFloat = 44
        static let disabledOpacity: CGFloat = 0.45
        static let maxLines = 5
    }

    @Binding var draft: String
    @Binding var pickedItem: PhotosPickerItem?
    @Binding var isFocused: Bool
    let isSendEnabled: Bool
    let isMediaEnabled: Bool
    let showsGIFButton: Bool
    let onSend: () -> Void
    let onGIF: () -> Void
    let onMediaPasted: (URL, UTType) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Design.Spacing._md) {
            // PhotosPicker's label closure is @Sendable, and the Zapp font modifiers are
            // MainActor-isolated — so the label has to be its own view rather than built
            // inline.
            PhotosPicker(selection: $pickedItem, matching: .images) {
                ChatAttachGlyph()
            }
            .buttonStyle(.zappPress)
            .disabled(!isMediaEnabled)
            .opacity(isMediaEnabled ? 1 : Constants.disabledOpacity)
            .accessibilityLabel(String(localizable: .chatRoomAttach))

            if showsGIFButton {
                Button(action: onGIF) {
                    ChatGIFGlyph()
                }
                .buttonStyle(.zappPress)
                .disabled(!isMediaEnabled)
                .opacity(isMediaEnabled ? 1 : Constants.disabledOpacity)
                .accessibilityLabel(String(localizable: .chatRoomSendGif))
            }

            // UIKit rather than TextField: a pasted image arrives through
            // paste(itemProviders:), which SwiftUI's field cannot receive.
            ChatComposerTextView(
                text: $draft,
                isFocused: $isFocused,
                placeholder: String(localizable: .chatRoomInputPlaceholder),
                maxLines: Constants.maxLines,
                onMediaPasted: onMediaPasted
            )
            .padding(.horizontal, Constants.inputHorizontalPadding)
            .padding(.vertical, Constants.inputVerticalPadding)
            .frame(minHeight: Constants.minHeight)
            .background(ZappColors.surfaceInput.color(colorScheme))

            Button(action: onSend) {
                Text(String(localizable: .chatRoomSend))
                    .zappFont(.buttonSmall, style: ZappColors.onAccent)
                    .padding(.horizontal, Constants.sendHorizontalPadding)
                    .padding(.vertical, Constants.sendVerticalPadding)
                    .frame(minHeight: Constants.minHeight)
                    .background(ZappColors.accent.color(colorScheme))
                    .opacity(isSendEnabled ? 1 : Constants.disabledOpacity)
                    .animation(ZappMotion.state, value: isSendEnabled)
            }
            .buttonStyle(.zappPress)
            .disabled(!isSendEnabled)
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
}

private extension ZappTextStyle {
    static let attachGlyph = ZappTextStyle(weight: .medium, size: 22, lineHeight: 24)
    static let gifGlyph = ZappTextStyle(weight: .bold, size: 11, lineHeight: 14, tracking: 0.4)
}

/// A lettered glyph rather than an icon: the catalogue has no GIF mark, and the neighbouring
/// attach control is already drawn the same way.
private struct ChatGIFGlyph: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(String(localizable: .chatRoomGif))
            .zappFont(.gifGlyph, style: ZappColors.text)
            .frame(width: ChatAttachGlyph.size, height: ChatAttachGlyph.size)
            .background(ZappColors.surfaceInput.color(colorScheme))
    }
}

#Preview {
    ChatRoomView(store: ChatRoom.initial)
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
