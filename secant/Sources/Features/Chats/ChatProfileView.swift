//
//  ChatProfileView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

struct ChatProfileView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatProfile>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .chatProfileTitle)) {
                    ZappBackButton { store.send(.backToHomeTapped) }
                } right: {
                    EmptyView()
                }

                ScrollView {
                    VStack(spacing: 0) {
                        displayNameGroup

                        if store.hasPublicKey {
                            publicKeyGroup
                        }

                        privacyGroup
                    }
                    .padding(.bottom, ZappNavBar.pushedFloatingMargin)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    private var displayNameGroup: some View {
        ChatProfileGroup(title: String(localizable: .chatProfileDisplayName)) {
            VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                TextField(
                    String(localizable: .chatProfileDisplayName),
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

                Text(String(localizable: .chatProfileDisplayNameHint))
                    .zappFont(.caption, color: ZappColors.textMuted.color(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)

                if store.saveFailed {
                    Text(String(localizable: .chatProfileSaveFailed))
                        .zappFont(.caption, color: ZappColors.danger.color(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ZappButton(
                    title: String(localizable: .chatProfileSave),
                    isEnabled: store.canSave
                ) {
                    store.send(.saveTapped)
                }
            }
            .padding(ChatProfileGroupConstants.contentPadding)
        }
    }

    private var publicKeyGroup: some View {
        ChatProfileGroup(title: String(localizable: .chatProfilePublicKey)) {
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(store.publicKey)
                    .zappFont(.mono, color: ZappColors.text.color(colorScheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing._md)
                    .background(ZappColors.surfaceAlt.color(colorScheme))

                HStack {
                    Spacer()

                    Button {
                        store.send(.copyPublicKeyTapped)
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
            .padding(ChatProfileGroupConstants.contentPadding)
        }
    }

    private var privacyGroup: some View {
        ChatProfileGroup(title: String(localizable: .chatProfilePrivacy)) {
            // `trailing:` is passed in-parens on purpose: a bare trailing closure binds to `action`,
            // which would hand the toggle to the wrong slot and leave a dead row.
            ZappRow(
                title: String(localizable: .chatProfileReadReceipts),
                subtitle: String(localizable: .chatProfileReadReceiptsHint),
                trailing: {
                    ZappToggle(isOn: store.readReceiptsEnabled) {
                        store.send(.readReceiptsToggled)
                    }
                }
            )

            ZappRowDivider()

            ZappRow(
                title: String(localizable: .chatProfilePresence),
                subtitle: String(localizable: .chatProfilePresenceHint),
                trailing: {
                    ZappToggle(isOn: store.presenceVisible) {
                        store.send(.presenceToggled)
                    }
                }
            )
        }
    }
}

/// The You tab's card idiom, repeated here so a screen pushed from it keeps its shape.
/// `SettingsGroup` itself is file-private to `SettingsTabContent`.
private struct ChatProfileGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: title)

            VStack(spacing: 0) {
                content
            }
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, ChatProfileGroupConstants.horizontalInset)

            Spacer()
                .frame(height: Design.Spacing._md)
        }
    }
}

/// Matches `ZappRow`'s own horizontal padding, so free-form card content lines up with the rows.
private enum ChatProfileGroupConstants {
    static let contentPadding: CGFloat = 18
    static let horizontalInset: CGFloat = 14
}

#Preview {
    ChatProfileView(store: ChatProfile.initial)
}
