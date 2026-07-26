//
//  ChatProfileSecretViews.swift
//  Zapp
//
//  Android's ChatProfileSeedPhraseDialog / ChatProfileP2pKeyDialog / ChatProfilePinVerifyOverlay.
//
//  The lifecycle handlers below are the ones that matter: they are attached to the whole
//  profile screen, not to the dialogs, so they fire even if SwiftUI has already torn a
//  dialog's body down. They are the same four `OnboardingSeedBackup` uses — resign-active
//  (which is what the app switcher snapshot fires first), background, a screen recording
//  starting, and disappearance — each clearing the words and the key out of state.
//

import ComposableArchitecture
import SwiftUI
import UIKit

extension View {
    func chatProfileSecretOverlays(store: StoreOf<ChatProfile>) -> some View {
        modifier(ChatProfileSecretOverlays(store: store))
    }
}

private struct ChatProfileSecretOverlays: ViewModifier {
    @Perception.Bindable var store: StoreOf<ChatProfile>

    func body(content: Content) -> some View {
        WithPerceptionTracking {
            content
                .overlay {
                    if store.showsSeedDialog {
                        ChatProfileSeedDialog(
                            words: store.seedWords,
                            onDismiss: { store.send(.secretDismissed) }
                        )
                    } else if let key = store.p2pKey {
                        ChatProfileP2PKeyDialog(
                            key: key,
                            didCopyAddress: store.didCopyP2PAddress,
                            didCopyKey: store.didCopyP2PKey,
                            onCopyAddress: { store.send(.copyP2PAddressTapped) },
                            onCopyKey: { store.send(.copyP2PKeyTapped) },
                            onDismiss: { store.send(.secretDismissed) }
                        )
                    }
                }
                .fullScreenCover(
                    isPresented: Binding(
                        get: { store.pinEntry != nil },
                        set: { if !$0 { store.send(.pinCancelled) } }
                    )
                ) {
                    WithPerceptionTracking {
                        if let entry = store.pinEntry {
                            AppPINEntryView(
                                title: String(localizable: .appLockPINVerifyTitle),
                                subtitle: String(localizable: .appLockPINVerifySubtitle),
                                errorMessage: entry.errorMessage,
                                digitCount: entry.pin.count,
                                isInputEnabled: !entry.isVerifying && entry.lockoutSeconds == 0,
                                onBack: { store.send(.pinCancelled) },
                                onKey: { store.send(.pinKeyTapped($0)) }
                            )
                        }
                    }
                }
                .privacySensitive(store.isShowingSecret)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    store.send(.hideSensitiveContent)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    store.send(.hideSensitiveContent)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                    if UIScreen.main.isCaptured {
                        store.send(.hideSensitiveContent)
                    }
                }
        }
    }
}

// MARK: - Seed phrase

/// Deliberately has no copy action. Android's seed dialog offers only "Done", and a 24-word
/// recovery phrase on the system pasteboard is readable by every other app on the device.
private struct ChatProfileSeedDialog: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let columnCount = 2
        static let indexWidth: CGFloat = 22
    }

    let words: [RedactableString]
    let onDismiss: () -> Void

    var body: some View {
        ChatProfileDialogShell(
            title: String(localizable: .chatProfileSeedPhraseDialogTitle),
            message: String(localizable: .chatProfileSeedPhraseDialogMessage),
            onDismiss: onDismiss
        ) {
            HStack(alignment: .top, spacing: Design.Spacing._lg) {
                ForEach(0..<Constants.columnCount, id: \.self) { column in
                    VStack(alignment: .leading, spacing: Design.Spacing._xs) {
                        ForEach(indices(for: column), id: \.self) { index in
                            HStack(spacing: Design.Spacing._xs) {
                                Text(String(format: "%02d", index + 1))
                                    .zappFont(.mono, style: ZappColors.textSubtle)
                                    .frame(width: Constants.indexWidth, alignment: .leading)

                                Text(words[index].data)
                                    .zappFont(.rowTitle, style: ZappColors.text)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func indices(for column: Int) -> [Int] {
        let half = (words.count + 1) / 2
        let lower = column * half
        let upper = min(lower + half, words.count)

        return lower < upper ? Array(lower..<upper) : []
    }
}

// MARK: - P2P wallet key

private struct ChatProfileP2PKeyDialog: View {
    let key: OfframpWalletKey
    let didCopyAddress: Bool
    let didCopyKey: Bool
    let onCopyAddress: () -> Void
    let onCopyKey: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ChatProfileDialogShell(
            title: String(localizable: .chatProfileP2pKeyDialogTitle),
            message: String(localizable: .chatProfileP2pKeyDialogMessage),
            onDismiss: onDismiss
        ) {
            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                field(
                    label: String(localizable: .chatProfileP2pKeyAddressLabel),
                    value: key.address,
                    didCopy: didCopyAddress,
                    onCopy: onCopyAddress
                )

                field(
                    label: String(localizable: .chatProfileP2pKeyPrivateLabel),
                    value: key.privateKeyHex.data,
                    didCopy: didCopyKey,
                    onCopy: onCopyKey
                )
            }
        }
    }

    private func field(label: String, value: String, didCopy: Bool, onCopy: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            HStack {
                Text(label)
                    .zappFont(.rowTitle, style: ZappColors.text)

                Spacer()

                Button(action: onCopy) {
                    Text(
                        didCopy
                            ? String(localizable: .newChatCopied)
                            : String(localizable: .chatProfileP2pKeyCopy)
                    )
                    .zappFont(.buttonSmall, style: didCopy ? ZappColors.success : ZappColors.accent)
                }
                .buttonStyle(.zappPress)
            }

            Text(value)
                .zappFont(.mono, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Shell

/// Sharp-rectangle modal panel over a scrim, matching the Android dialogs' geometry while
/// staying inside the profile's own view tree — so the screen-level hide handlers keep running.
private enum ChatProfileDialogConstants {
    static let scrimOpacity: CGFloat = 0.6
    static let horizontalInset: CGFloat = 24
    static let maxHeightFraction: CGFloat = 0.8
}

private struct ChatProfileDialogShell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private typealias Constants = ChatProfileDialogConstants

    let title: String
    let message: String
    let onDismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black
                .opacity(Constants.scrimOpacity)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: Design.Spacing._md) {
                Text(title)
                    .zappFont(.sectionTitle, style: ZappColors.text)

                Text(message)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: onDismiss) {
                    Text(String(localizable: .generalDone))
                        .zappFont(.button, style: ZappColors.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.zappPress)
            }
            .padding(Design.Spacing._lg)
            .frame(maxHeight: UIScreen.main.bounds.height * Constants.maxHeightFraction)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, Constants.horizontalInset)
        }
    }
}
