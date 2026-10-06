//
//  ViewingKeyExportView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// Android's `ViewingKeyExportView`: the account and access-level choices, the irreversibility
/// acknowledgement, and — once authenticated — the key with copy, share and hide.
struct ViewingKeyExportView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let gutter: CGFloat = 18
        static let cardGutter: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let cardSpacing: CGFloat = 12
        static let checkSize: CGFloat = 20
        static let checkboxSize: CGFloat = 24
        static let textSpacing: CGFloat = 4
    }

    @Perception.Bindable var store: StoreOf<ViewingKeyExport>

    @State private var isInfoPresented = false

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .viewingKeyExportTitle),
                    subtitle: String(localizable: .viewingKeyExportSubtitle)
                ) {
                    ZappInfoButton(accessibilityLabel: String(localizable: .viewingKeyExportInfoAccessibility)) {
                        isInfoPresented = true
                    }
                }

                if store.isLoading {
                    ProgressView()
                        .tint(ZappColors.accent.color(colorScheme))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            if store.accounts.count > 1 {
                                accountPicker
                            }

                            accessLevelPicker

                            if let key = store.revealedKey {
                                revealedKeySection(key)
                            } else {
                                acknowledgement
                            }

                            errorMessage
                        }
                        .padding(.bottom, Design.Spacing._xl)
                    }
                }

                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .accessibilityHidden(store.authGate.pinEntry != nil)
            .zappSwipeBack(isEnabled: !store.isAuthenticating) { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .sheet(isPresented: $isInfoPresented) {
                ViewingKeyExportInfoSheet { isInfoPresented = false }
            }
            .overlay { shareSheet }
            .secretAuthGateOverlay(store: store.scope(state: \.authGate, action: \.authGate))
            .secretScreenGuards(isShowingSecret: store.revealedKey != nil) {
                store.send(.hideSensitiveContent)
            }
        }
    }

    // MARK: - Pickers

    private var accountPicker: some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: String(localizable: .viewingKeyExportAccountLabel))

            VStack(spacing: Constants.cardSpacing) {
                ForEach(store.accounts) { account in
                    selectionCard(
                        title: account.title,
                        subtitle: account.accountIndex.map { String(localizable: .viewingKeyExportAccountIndex(Int($0))) },
                        isSelected: account.id == store.selectedAccountId,
                        isEnabled: store.isSelectionEnabled
                    ) {
                        store.send(.accountSelected(account.id))
                    }
                }
            }
            .padding(.horizontal, Constants.cardGutter)
        }
    }

    private var accessLevelPicker: some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: String(localizable: .viewingKeyExportAccessLevelLabel))

            VStack(spacing: Constants.cardSpacing) {
                ForEach(ViewingKeyExport.KeyType.allCases, id: \.self) { keyType in
                    let isAvailable = store.selectedAccount?.availableKeyTypes.contains(keyType) ?? false

                    selectionCard(
                        title: title(for: keyType),
                        subtitle: description(for: keyType),
                        supporting: isAvailable ? nil : String(localizable: .viewingKeyExportUnavailable),
                        isSelected: store.selectedKeyType == keyType,
                        isEnabled: isAvailable && store.isSelectionEnabled
                    ) {
                        store.send(.keyTypeSelected(keyType))
                    }
                }
            }
            .padding(.horizontal, Constants.cardGutter)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func selectionCard(
        title: String,
        subtitle: String?,
        supporting: String? = nil,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Constants.cardSpacing) {
                VStack(alignment: .leading, spacing: Constants.textSpacing) {
                    Text(title)
                        .zappFont(.rowTitle, style: isEnabled ? ZappColors.text : ZappColors.textSubtle)

                    if let subtitle {
                        Text(subtitle)
                            .zappFont(.rowSubtitle, style: ZappColors.textMuted)
                    }

                    if let supporting {
                        Text(supporting)
                            .zappFont(.caption, style: ZappColors.textSubtle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

                if isSelected {
                    Asset.Assets.check.image
                        .zImage(size: Constants.checkSize, style: ZappColors.accentText)
                }
            }
            .padding(Constants.cardPadding)
            .background((isSelected ? ZappColors.accentSoft : ZappColors.surface).color(colorScheme))
            .overlay(
                Rectangle()
                    .strokeBorder((isSelected ? ZappColors.accent : ZappColors.border).color(colorScheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var acknowledgement: some View {
        let isEnabled = store.isSelectedKeyAvailable && !store.isAuthenticating

        return Button { store.send(.acknowledgementToggled) } label: {
            HStack(alignment: .top, spacing: Constants.cardSpacing) {
                ZStack {
                    Rectangle()
                        .fill((store.isAcknowledged ? ZappColors.accentSoft : ZappColors.surface).color(colorScheme))
                    Rectangle()
                        .strokeBorder(
                            (store.isAcknowledged ? ZappColors.accent : ZappColors.border).color(colorScheme),
                            lineWidth: 1
                        )

                    if store.isAcknowledged {
                        Asset.Assets.check.image
                            .zImage(size: Constants.checkSize, style: ZappColors.accentText)
                    }
                }
                .frame(width: Constants.checkboxSize, height: Constants.checkboxSize)

                Text(localizable: .viewingKeyExportAcknowledgement)
                    .zappFont(.body, style: ZappColors.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Constants.gutter)
            .padding(.vertical, Design.Spacing._xl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
        .disabled(!isEnabled)
        .accessibilityAddTraits(store.isAcknowledged ? [.isSelected] : [])
    }

    // MARK: - Revealed key

    private func revealedKeySection(_ key: ViewingKeyExport.RevealedKey) -> some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: String(localizable: .viewingKeyExportRevealedLabel))

            ZappBorderedCard {
                VStack(alignment: .leading, spacing: Constants.cardSpacing) {
                    HStack {
                        Text(title(for: key.keyType).uppercased())
                            .zappFont(.eyebrow, style: ZappColors.accentText)

                        Spacer(minLength: 0)

                        ZappCopyIconButton(
                            isCopied: store.isCopied,
                            accessibilityLabel: String(localizable: .viewingKeyExportCopy)
                        ) {
                            store.send(.copyTapped)
                        }
                    }

                    Text(key.encodedKey.data)
                        .zappFont(.mono, style: ZappColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    ZappButton(
                        title: String(localizable: .viewingKeyExportShare),
                        leadingIcon: Asset.Assets.Icons.share.image
                    ) {
                        store.send(.shareTapped)
                    }

                    ZappButton(
                        title: String(localizable: .viewingKeyExportHide),
                        variant: .ghost,
                        leadingIcon: Asset.Assets.eyeOff.image
                    ) {
                        store.send(.hideTapped)
                    }
                }
            }
            .padding(.horizontal, Constants.cardGutter)
        }
    }

    @ViewBuilder private var errorMessage: some View {
        if let error = store.error {
            Text(message(for: error))
                .zappFont(.body, style: ZappColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Constants.gutter)
                .padding(.vertical, Design.Spacing._md)
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if store.revealedKey == nil {
            ZappBottomActionBar(onBack: { store.send(.backTapped) }, isBackEnabled: !store.isAuthenticating) {
                ZappButton(
                    title: store.isAuthenticating
                        ? String(localizable: .viewingKeyExportAuthenticating)
                        : String(localizable: .viewingKeyExportReveal),
                    isEnabled: store.canReveal,
                    leadingIcon: Asset.Assets.eyeOn.image
                ) {
                    store.send(.revealTapped)
                }
            }
        } else {
            ZappBottomActionBar(onBack: { store.send(.backTapped) })
        }
    }

    @ViewBuilder private var shareSheet: some View {
        if let key = store.sharedKey {
            UIShareDialogView(activityItems: [key.data]) {
                store.send(.shareFinished)
            }
            .frame(width: 0, height: 0)
        }
    }

    // MARK: - Copy

    private func title(for keyType: ViewingKeyExport.KeyType) -> String {
        switch keyType {
        case .ufvk: return String(localizable: .viewingKeyExportUfvkTitle)
        case .uivk: return String(localizable: .viewingKeyExportUivkTitle)
        }
    }

    private func description(for keyType: ViewingKeyExport.KeyType) -> String {
        switch keyType {
        case .ufvk: return String(localizable: .viewingKeyExportUfvkDescription)
        case .uivk: return String(localizable: .viewingKeyExportUivkDescription)
        }
    }

    private func message(for error: ViewingKeyExport.ExportError) -> String {
        switch error {
        case .loadFailed: return String(localizable: .viewingKeyExportLoadFailed)
        case .authenticationFailed: return String(localizable: .viewingKeyExportAuthFailed)
        case .keyUnavailable: return String(localizable: .viewingKeyExportKeyUnavailable)
        case .screenRecording: return String(localizable: .chatProfileSecretScreenRecording)
        }
    }
}

/// Android's `ViewingKeyExportInfoSheet`: the detail the screen deliberately does not carry.
private struct ViewingKeyExportInfoSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localizable: .viewingKeyExportInfoTitle)
                .zappFont(.sectionTitle, style: ZappColors.text)

            Text(localizable: .viewingKeyExportInfoIntro)
                .zappFont(.body, style: ZappColors.textMuted)

            topic(String(localizable: .viewingKeyExportUfvkTitle), String(localizable: .viewingKeyExportInfoUfvkBody))
            topic(String(localizable: .viewingKeyExportUivkTitle), String(localizable: .viewingKeyExportInfoUivkBody))
            topic(
                String(localizable: .viewingKeyExportInfoIrrevocableTitle),
                String(localizable: .viewingKeyExportInfoIrrevocableBody)
            )

            Text(localizable: .viewingKeyExportInfoCompatibility)
                .zappFont(.caption, style: ZappColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .zappInfoSheet(onDismiss: onDismiss)
    }

    private func topic(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .zappFont(.rowTitle, style: ZappColors.text)

            Text(body)
                .zappFont(.body, style: ZappColors.textMuted)
        }
    }
}

#Preview {
    ViewingKeyExportView(store: ViewingKeyExport.initial)
}
