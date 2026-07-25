//
//  SupportChatView.swift
//  Zapp
//
//  Mirrors `screen/chat/support/SupportChatScreen.kt`.
//

import ComposableArchitecture
import PhotosUI
import SwiftUI
import ZappMessaging

struct SupportChatView: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isComposerFocused: Bool

    @Perception.Bindable var store: StoreOf<SupportChat>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                header

                switch store.mode {
                case .loading:
                    loading

                case .selectCategory(let isSubmitting):
                    SupportCategoryPicker(isSubmitting: isSubmitting) { category in
                        store.send(.categorySelected(category))
                    }

                case .chat:
                    messages

                    Rectangle()
                        .fill(ZappColors.border.color(colorScheme))
                        .frame(height: 1)

                    failureBanner

                    composer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack { navigateBack() }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .alert($store.scope(state: \.alert, action: \.alert))
        }
    }

    // MARK: Header

    private var header: some View {
        ZappScreenHeader(title: String(localizable: .supportChatTitle)) {
            ZappBackButton { navigateBack() }
        } right: {
            // Android only offers "Close Support Chat" once a ticket exists; before that there is
            // nothing to close.
            if store.mode == .chat {
                Menu {
                    Button(String(localizable: .supportChatOverflowClose), role: .destructive) {
                        store.send(.leaveTapped)
                    }
                } label: {
                    Asset.Assets.Icons.dotsMenu.image
                        .zImage(
                            width: Constants.overflowIconSize,
                            height: Constants.overflowIconSize,
                            style: ZappColors.text
                        )
                        .frame(width: Constants.overflowTapSize, height: Constants.overflowTapSize)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localizable: .supportChatOverflow))
            } else {
                EmptyView()
            }
        }
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Design.Spacing._md) {
                    ForEach(store.messages) { message in
                        SupportMessageRow(message: message)
                    }
                }
                .padding(.horizontal, Design.Spacing._xl)
                .padding(.vertical, Design.Spacing._md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { isComposerFocused = false }
            .onChange(of: store.messages.count) { _ in
                guard let last = store.messages.last else { return }

                withAnimation(ZappMotion.content) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var failureBanner: some View {
        if store.sendDidFail {
            Text(store.sendFailureMessage ?? String(localizable: .chatRoomSendFailed))
                .zappFont(.caption, style: ZappColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Design.Spacing._xl)
                .padding(.top, Design.Spacing._md)
                .background(ZappColors.surface.color(colorScheme))
        }
    }

    // MARK: Composer

    private var composer: some View {
        SupportComposer(
            draft: $store.draft.sending(\.draftChanged),
            isFocused: $isComposerFocused,
            isSendEnabled: store.isSendEnabled,
            onAttach: {
                isComposerFocused = false
                store.send(.attachTapped)
            },
            onSend: { store.send(.sendTapped) }
        )
        .sheet(
            isPresented: Binding(
                get: { store.showsMediaSheet },
                set: { if !$0 { store.send(.mediaSheetDismissed) } }
            ),
            // A picker can only be presented once the sheet has actually gone.
            onDismiss: { store.send(.mediaSheetClosed) }
        ) {
            ChatMediaAttachmentSheet(
                onChooseMedia: { store.send(.chooseMediaTapped) },
                onAttachFile: { store.send(.attachFileTapped) },
                onTakePhoto: { store.send(.takePhotoTapped) }
            )
            .padding(.horizontal, Design.Spacing._3xl)
            .padding(.bottom, Design.Spacing._3xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, Design.Spacing._xl)
            .background(ZappColors.surface.color(colorScheme))
            .presentationDetents([.height(ChatMediaAttachmentSheet.detentHeight)])
            .presentationDragIndicator(.visible)
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
            allowedContentTypes: [.item]
        ) { result in
            switch result {
            case .success(let url):
                store.send(.fileImported(url))

            case .failure(let error):
                LoggerProxy.error("Support chat file import failed: \(error)")
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

    private var loading: some View {
        ProgressView()
            .tint(ZappColors.accent.color(colorScheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navigateBack() {
        isComposerFocused = false
        store.send(.backTapped, animation: ZappMotion.content)
    }

    private enum Constants {
        static let overflowIconSize: CGFloat = 20
        static let overflowTapSize: CGFloat = 36
    }
}

// MARK: - Topic picker

/// Bottom-anchored so the options sit under the thumb, exactly as Android places them.
private struct SupportCategoryPicker: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let dimmedOpacity: CGFloat = 0.4
        static let bottomInset: CGFloat = 48
    }

    let isSubmitting: Bool
    let onSelected: (SupportCategory) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: Design.Spacing._xl) {
                Spacer()

                Text(String(localizable: .supportChatPickTopic))
                    .zappFont(.sectionTitle, style: ZappColors.text)

                VStack(spacing: Design.Spacing._md) {
                    ForEach(SupportCategory.allCases, id: \.self) { category in
                        ZappButton(
                            title: category.displayName,
                            variant: .secondary,
                            isEnabled: !isSubmitting
                        ) {
                            onSelected(category)
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Spacing._3xl)
            .padding(.bottom, Constants.bottomInset)
            .opacity(isSubmitting ? Constants.dimmedOpacity : 1)

            if isSubmitting {
                ProgressView()
                    .tint(ZappColors.accent.color(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(ZappMotion.state, value: isSubmitting)
    }
}

// MARK: - Bubbles

/// One message. Media and files reuse the ordinary chat bubbles — Android renders them as bare
/// caption text, which leaves an image looking like an empty bubble; iOS shows the attachment
/// itself instead. Everything else is the text bubble, aligned by ORIGIN rather than `isFromMe`,
/// so the `[Zapp]:` greeting the user's own device posted still reads as a system message.
private struct SupportMessageRow: View {
    let message: SupportMessage

    var body: some View {
        switch ChatMessageKind.of(message.message) {
        case .image, .video:
            ChatMediaBubble(message: message.message)

        case .file:
            ChatFileBubble(message: message.message)

        default:
            SupportTextBubble(message: message)
        }
    }
}

private struct SupportTextBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let maxWidthRatio: CGFloat = 0.78
    }

    let message: SupportMessage

    var body: some View {
        HStack {
            if message.isFromLocalUser {
                Spacer(minLength: 0)
            }

            Text(message.content)
                .zappFont(.body, style: message.isFromLocalUser ? ZappColors.onAccent : ZappColors.text)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
                .background(
                    (message.isFromLocalUser ? ZappColors.accent : ZappColors.surface).color(colorScheme)
                )

            if !message.isFromLocalUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Composer

private struct SupportComposer: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let inputHorizontalPadding: CGFloat = 12
        static let inputVerticalPadding: CGFloat = 10
        static let sendHorizontalPadding: CGFloat = 16
        static let sendVerticalPadding: CGFloat = 12
        static let minHeight: CGFloat = 44
        static let glyphSize: CGFloat = 44
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
            Button(action: onAttach) {
                Text(verbatim: "+")
                    .zappFont(.supportAttachGlyph, style: ZappColors.text)
                    .frame(width: Constants.glyphSize, height: Constants.glyphSize)
                    .background(ZappColors.surfaceInput.color(colorScheme))
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .chatRoomAttach))

            TextField(String(localizable: .supportChatInputPlaceholder), text: $draft, axis: .vertical)
                .focused(isFocused)
                .zappFont(.body, style: ZappColors.text)
                .lineLimit(Constants.lineLimit)
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
            ZappColors.surface.color(colorScheme)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

private extension ZappTextStyle {
    static let supportAttachGlyph = ZappTextStyle(weight: .medium, size: 22, lineHeight: 24)
}

#Preview {
    SupportChatView(store: SupportChat.initial)
}
