//
//  ChatRoomView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI
import ZappMessaging

/// The chat room is the one screen that keeps its back button in the header rather than in a
/// `ZappBottomActionBar`: the composer owns the bottom edge. `ChatRoomView.kt` does the same.
struct ChatRoomView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatRoom>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: store.title, subtitle: store.subtitle) {
                    ZappBackButton {
                        store.send(.backToHomeTapped)
                    }
                } right: {
                    EmptyView()
                }

                messages

                Rectangle()
                    .fill(ZappColors.border.color(colorScheme))
                    .frame(height: 1)

                ChatRoomInputRow(
                    draft: $store.draft.sending(\.draftChanged),
                    isSendEnabled: !store.trimmedDraft.isEmpty
                ) {
                    store.send(.sendTapped)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
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
                            ChatMessageBubble(message: message, senderName: store.state.senderName(for: message))

                        case .separator(_, let label):
                            ChatDateSeparator(label: label)
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing._xl)
                .padding(.bottom, Design.Spacing._md)
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
    let isSendEnabled: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Design.Spacing._md) {
            TextField(String(localizable: .chatRoomInputPlaceholder), text: $draft, axis: .vertical)
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
        .padding(.horizontal, Design.Spacing._xl)
        .padding(.vertical, Design.Spacing._lg)
        .background(ZappColors.surface.color(colorScheme))
        .padding(.bottom, ZappNavBar.pushedFloatingMargin)
    }
}

#Preview {
    ChatRoomView(store: ChatRoom.initial)
}
