//
//  ChatIdentitySetupView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// Chat identity setup, rendered inside the Chats tab while there is no identity.
///
/// The identity derives from the wallet seed, but the display name is the sole trigger for that
/// derivation — without this screen the subsystem sits in `.needsIdentity` forever.
///
/// Tab content, not a pushed screen: no NavigationStack, no toolbar, and bottom clearance so the
/// floating nav pill never covers the CTA. On `.ready` it renders nothing; Root swaps the tab.
struct ChatIdentitySetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNameFocused: Bool

    private enum Constants {
        static let horizontalPadding: CGFloat = 24
        static let fieldMinHeight: CGFloat = 52
        static let fieldPadding: CGFloat = 14
        static let iconSize: CGFloat = 72
    }

    @Perception.Bindable var store: StoreOf<ChatIdentitySetup>

    var body: some View {
        WithPerceptionTracking {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ZappColors.bg.color(colorScheme))
                .onAppear { store.send(.onAppear) }
                .onDisappear { store.send(.onDisappear) }
        }
    }

    /// Deriving and a failed derive stay on the form, as Android's do: the button carries the
    /// progress and the error sits under it.
    @ViewBuilder private var content: some View {
        switch store.messagingState.phase {
        case .idle, .initializing:
            ChatIdentityProgress(label: nil)

        case .needsIdentity, .deriving, .failed:
            form

        case .ready:
            EmptyView()
        }
    }

    /// Android's `ChatIdentitySetupView`: a centred column under a person icon.
    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                Asset.Assets.Icons.user.image
                    .zImage(width: Constants.iconSize, height: Constants.iconSize, style: ZappColors.accent)

                Text(String(localizable: .chatIdentitySetupTitle))
                    .zappFont(.displaySecondary, style: ZappColors.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._2xl)

                Text(String(localizable: .chatIdentitySetupSubtitle))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Design.Spacing._md)

                nameField
                    .padding(.top, Design.Spacing._2xl)

                submitButton
                    .padding(.top, Design.Spacing._xl)

                errorSection
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.top, Design.Spacing._3xl)
            .padding(.bottom, ZappNavBar.clearance)
            .frame(maxWidth: .infinity)
        }
    }

    private var nameField: some View {
        TextField(
            String(localizable: .chatIdentitySetupDisplayName),
            text: Binding(
                get: { store.displayName },
                set: { store.send(.displayNameChanged($0)) }
            )
        )
        .focused($isNameFocused)
        .zappFont(.body, style: ZappColors.text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { store.send(.continueTapped) }
        .padding(.horizontal, Constants.fieldPadding)
        .padding(.vertical, Constants.fieldPadding)
        .frame(maxWidth: .infinity, minHeight: Constants.fieldMinHeight)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
        .zappFieldTapTarget($isNameFocused)
    }

    private var submitButton: some View {
        ZStack {
            ZappButton(
                title: store.isSubmitting ? "" : String(localizable: .chatIdentitySetupCreate),
                isEnabled: !store.isSubmitting
            ) {
                store.send(.continueTapped)
            }

            if store.isSubmitting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(ZappColors.textSubtle.color(colorScheme))
                    .accessibilityLabel(String(localizable: .chatIdentityDeriving))
            }
        }
    }

    @ViewBuilder private var errorSection: some View {
        if store.showsNameRulesError {
            Text(String(localizable: .chatIdentitySetupNameInvalid))
                .zappFont(.caption, style: ZappColors.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Design.Spacing._md)
        } else if store.errorCode != nil {
            VStack(spacing: Design.Spacing._md) {
                Text(String(localizable: .chatIdentitySetupDeriveFailed))
                    .zappFont(.caption, style: ZappColors.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(localizable: .chatIdentitySetupSupportHint))
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ZappButton(
                    title: String(localizable: .chatIdentitySetupCopyDetails),
                    variant: .secondary
                ) {
                    store.send(.copyErrorDetailsTapped)
                }
            }
            .padding(.top, Design.Spacing._md)
        }
    }
}

private struct ChatIdentityProgress: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String?

    var body: some View {
        VStack(spacing: Design.Spacing._xl) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(ZappColors.accent.color(colorScheme))

            if let label {
                Text(label)
                    .zappFont(.body, style: ZappColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, ZappNavBar.clearance)
    }
}

#Preview {
    ChatIdentitySetupView(
        store: StoreOf<ChatIdentitySetup>(
            initialState: {
                var state = ChatIdentitySetup.State()
                state.messagingState = ZappMessagingState(phase: .needsIdentity)
                return state
            }()
        ) {
            ChatIdentitySetup()
        }
    )
}
