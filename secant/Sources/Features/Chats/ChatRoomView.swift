//
//  ChatRoomView.swift
//  Zapp
//

import ComposableArchitecture
import PhotosUI
import SwiftUI
import UIKit
import ZappMessaging

/// The chat room is the one screen that keeps its back button in the header rather than in a
/// `ZappBottomActionBar`: the composer owns the bottom edge. `ChatRoomView.kt` does the same.
struct ChatRoomView: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isComposerFocused: Bool

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

                ChatRoomInputRow(
                    draft: $store.draft.sending(\.draftChanged),
                    isFocused: $isComposerFocused,
                    isSendEnabled: !store.trimmedDraft.isEmpty,
                    onAttach: {
                        isComposerFocused = false
                        store.send(.attachTapped)
                    },
                    onSend: { store.send(.sendTapped) }
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
        ChatRoomItem.build(from: store.visibleMessages)
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
                        }
                    }
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
            .onChange(of: items.count) { _ in
                guard let last = items.last else { return }

                withAnimation(ZappMotion.content) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private enum ChatRoomItem: Identifiable, Equatable {
    case message(ZMMessage)
    case separator(id: String, label: String)

    var id: String {
        switch self {
        case .message(let message): return "msg_\(message.id)"
        case .separator(let id, _): return id
        }
    }

    /// The separator id carries the index: a duplicate day key must not collide and tear the list.
    static func build(from messages: [ZMMessage], calendar: Calendar = .current) -> [ChatRoomItem] {
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
        static let lineLimit = 1...5
    }

    @Binding var draft: String
    let isFocused: FocusState<Bool>.Binding
    let isSendEnabled: Bool
    let onAttach: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Design.Spacing._md) {
            // "+" used to mount a `PhotosPicker` directly; it now opens the attachment sheet,
            // where the gallery is one of several options (Android's `onAttachClick`).
            Button(action: onAttach) {
                ChatAttachGlyph()
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .chatRoomAttach))

            TextField(String(localizable: .chatRoomInputPlaceholder), text: $draft, axis: .vertical)
                .focused(isFocused)
                .zappFont(.body, style: ZappColors.text)
                .lineLimit(Constants.lineLimit)
                .padding(.horizontal, Constants.inputHorizontalPadding)
                .padding(.vertical, Constants.inputVerticalPadding)
                .frame(minHeight: Constants.minHeight)
                .background(ZappColors.surfaceInput.color(colorScheme))

            // Android pulses on the send CLICK, not on delivery — the tap is what the user is
            // acknowledging, and a message that fails still surfaces its own failure row.
            Button {
                ZappHaptics.sendConfirm()
                onSend()
            } label: {
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
