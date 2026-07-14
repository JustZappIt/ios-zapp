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

    private enum Constants {
        static let horizontalPadding: CGFloat = 18
        static let fieldMinHeight: CGFloat = 52
        static let fieldPadding: CGFloat = 14
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

    @ViewBuilder private var content: some View {
        switch store.messagingState.phase {
        case .idle, .initializing:
            ChatIdentityProgress(label: nil)

        case .needsIdentity:
            form

        case .deriving:
            ChatIdentityProgress(label: String(localizable: .chatIdentityDeriving))

        case .ready:
            EmptyView()

        case .failed:
            failure
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            ZappScreenHeader(title: String(localizable: .chatIdentityTitle))

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing._lg) {
                    Text(String(localizable: .chatIdentitySubtitle))
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    nameField

                    Text(String(localizable: .chatIdentityRules))
                        .zappFont(.caption, style: ZappColors.textSubtle)

                    if let errorCode = store.errorCode {
                        ChatIdentityError(code: errorCode)
                    }

                    ZappButton(title: ctaTitle, isEnabled: store.isValid) {
                        store.send(store.errorCode == nil ? .continueTapped : .retryTapped)
                    }
                    .padding(.top, Design.Spacing._md)
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.top, Design.Spacing._2xl)
                .padding(.bottom, ZappNavBar.clearance)
            }
        }
    }

    private var nameField: some View {
        TextField(
            String(localizable: .chatIdentityPlaceholder),
            text: Binding(
                get: { store.displayName },
                set: { store.send(.displayNameChanged($0)) }
            )
        )
        .zappFont(.body, style: ZappColors.text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .padding(.horizontal, Constants.fieldPadding)
        .padding(.vertical, Constants.fieldPadding)
        .frame(maxWidth: .infinity, minHeight: Constants.fieldMinHeight)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay(
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        )
    }

    private var failure: some View {
        VStack(spacing: Design.Spacing._2xl) {
            ChatIdentityError(code: store.errorCode ?? "")

            ZappButton(title: String(localizable: .chatIdentityRetry)) {
                store.send(.retryTapped)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, ZappNavBar.clearance)
    }

    private var ctaTitle: String {
        store.errorCode == nil
            ? String(localizable: .chatIdentityContinue)
            : String(localizable: .chatIdentityRetry)
    }
}

private struct ChatIdentityError: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            Text(String(localizable: .chatIdentityFailed))
                .zappFont(.caption, style: ZappColors.danger)
                .fixedSize(horizontal: false, vertical: true)

            Text(code)
                .zappFont(.mono, style: ZappColors.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
