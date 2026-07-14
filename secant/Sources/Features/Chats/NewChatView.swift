//
//  NewChatView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct NewChatView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<NewChat>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .newChatTitle)) {
                    ZappBackButton { store.send(.backToHomeTapped) }
                } right: {
                    EmptyView()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                        peerKeyField
                        nameField
                        startButton
                        myKeyCard
                    }
                    .padding(.horizontal, Design.Spacing._lg)
                    .padding(.top, Design.Spacing._lg)
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    private var peerKeyField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatPeerLabel))

            HStack(spacing: Design.Spacing._sm) {
                TextField(
                    String(localizable: .newChatPeerPlaceholder),
                    text: Binding(
                        get: { store.peerKey },
                        set: { store.send(.peerKeyChanged($0)) }
                    ),
                    axis: .vertical
                )
                .zappFont(.mono, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2, reservesSpace: true)

                Button {
                    store.send(.pasteTapped)
                } label: {
                    Text(String(localizable: .newChatPaste))
                        .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
                }
            }
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))

            if store.showsInvalidKeyHint {
                Text(String(localizable: .newChatInvalidKey))
                    .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatNameLabel))

            TextField(
                String(localizable: .newChatNamePlaceholder),
                text: Binding(
                    get: { store.displayName },
                    set: { store.send(.displayNameChanged($0)) }
                )
            )
            .zappFont(.body, style: ZappColors.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(Design.Spacing._md)
            .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }

    private var startButton: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappButton(
                title: String(localizable: .newChatStart),
                isEnabled: store.isValidKey && !store.isCreating
            ) {
                store.send(.startTapped)
            }
            .frame(maxWidth: .infinity)

            if store.errorCode != nil {
                Text(String(localizable: .newChatFailed))
                    .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
            }
        }
    }

    /// Chat is symmetric: the peer needs our key just as much as we need theirs.
    /// Without this the screen only works for whoever was handed a key first.
    private var myKeyCard: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: String(localizable: .newChatYourKey))

            Text(store.myPublicKey)
                .zappFont(.mono, color: ZappColors.text.color(colorScheme))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Spacing._md)
                .background(ZappColors.surfaceAlt.color(colorScheme))

            HStack {
                Text(String(localizable: .newChatYourKeyHint))
                    .zappFont(.caption, color: ZappColors.textMuted.color(colorScheme))

                Spacer()

                Button {
                    store.send(.copyMyKeyTapped)
                } label: {
                    Text(
                        store.didCopy
                            ? String(localizable: .newChatCopied)
                            : String(localizable: .newChatCopy)
                    )
                    .zappFont(.buttonSmall, color: ZappColors.accent.color(colorScheme))
                }
            }
        }
        .padding(.top, Design.Spacing._lg)
    }
}
