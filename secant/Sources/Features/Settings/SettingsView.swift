import SwiftUI
import ComposableArchitecture

struct SettingsView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Constants {
        static let logoSize: CGFloat = 41
        static let wordmarkWidth: CGFloat = 73
        static let wordmarkHeight: CGFloat = 20
    }

    @Perception.Bindable var store: StoreOf<Settings>

    init(store: StoreOf<Settings>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ZappRow(
                                title: String(localizable: .settingsAddressBook),
                                icon: Asset.Assets.Icons.user.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.addressBookAccessCheck)
                            }
                            .accessibilityIdentifier(AccessibilityID.Settings.addressBook)

                            if store.isEnoughFreeSpaceMode {
                                ZappRowDivider(inset: true)

                                ZappRow(
                                    title: String(localizable: .currencyConversionTitle),
                                    icon: Asset.Assets.Icons.currencyDollar.image,
                                    iconTint: .accentText,
                                    iconBackground: .accentSoft
                                ) {
                                    store.send(.currencyConversionTapped)
                                }
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsCoinholderPolling),
                                icon: Asset.Assets.Icons.checkVerified.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.coinholderPollingTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsAdvanced),
                                icon: Asset.Assets.Icons.settings.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.advancedSettingsTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsWhatsNew),
                                icon: Asset.Assets.Icons.magicWand.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.whatsNewTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsAbout),
                                icon: Asset.Assets.infoOutline.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.aboutTapped)
                            }

                            ZappRowDivider(inset: true)

                            ZappRow(
                                title: String(localizable: .settingsFeedback),
                                icon: Asset.Assets.Icons.messageSmile.image,
                                iconTint: .accentText,
                                iconBackground: .accentSoft
                            ) {
                                store.send(.sendUsFeedbackTapped)
                            }
                        }
                        .background(ZappColors.surface.color(colorScheme))
                        .overlay(
                            Rectangle()
                                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                        )
                        .padding(.horizontal, Design.Spacing._lg)
                        .padding(.top, Design.Spacing._3xl)
                    }
                    .onAppear { store.send(.onAppear) }

                    Spacer()

                    footer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ZappColors.bg.color(colorScheme))
                .zashiBack() { store.send(.backToHomeTapped) }
                .screenTitle(String(localizable: .settingsTitle))
            } destination: { store in
                switch store.case {
                case let .about(store):
                    AboutView(store: store)
                case let .accountHWWalletSelection(store):
                    AccountsSelectionView(store: store)
                case let .addKeystoneHWWallet(store):
                    AddKeystoneHWWalletView(store: store)
                case let .addressBook(store):
                    AddressBookView(store: store)
                case let .addressBookContact(store):
                    AddressBookContactView(store: store)
                case let .advancedSettings(store):
                    AdvancedSettingsView(store: store)
                case let .chooseServerSetup(store):
                    ServerSetupView(store: store)
                case let .disconnectHWWallet(store):
                    DisconnectHWWalletView(store: store)
                case let .currencyConversionSetup(store):
                    CurrencyConversionSetupView(store: store)
                case let .exportPrivateData(store):
                    PrivateDataConsentView(store: store)
                case let .exportTransactionHistory(store):
                    ExportTransactionHistoryView(store: store)
                case let .recoveryPhrase(store):
                    RecoveryPhraseDisplayView(store: store)
                case let .resyncEstimateBirthdaysDate(store):
                    WalletBirthdayEstimateDateView(store: store)
                case let .resyncEstimatedBirthday(store):
                    WalletBirthdayEstimatedHeightView(store: store)
                case let .resyncRestoreInfo(store):
                    RestoreInfoView(store: store)
                case let .resyncWallet(store):
                    ResyncWalletView(store: store)
                case let .resyncWalletBirthday(store):
                    WalletBirthdayView(store: store)
                case let .resetZashi(store):
                    DeleteWalletView(store: store)
                case let .scan(store):
                    ScanView(store: store)
                case let .sendUsFeedback(store):
                    SendFeedbackView(store: store)
                case let .torSetup(store):
                    TorSetupView(store: store)
                case let .whatsNew(store):
                    WhatsNewView(store: store)
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .zashiSheet(isPresented: $store.isInRecoverFundsMode) {
                recoverFundsSheetContent()
            }
            .zashiSheet(isPresented: $store.isInEnhanceTransactionMode) {
                enhanceTransactionSheetContent()
            }
            .zashiSheet(isPresented: $store.isResyncHelpSheetPresented) {
                resyncHelpSheetContent()
            }
            .fullScreenCover(
                item: $store.scope(state: \.votingCoordFlow, action: \.votingCoordFlow)
            ) { votingStore in
                // fullScreenCover content is an escaping closure — needs its
                // own WithPerceptionTracking so reads inside the presented
                // store register with TCA's observation system.
                WithPerceptionTracking {
                    VotingCoordFlowView(store: votingStore)
                }
            }
        }
    }

    /// The wordmark is the only affordance for the two hidden debug modes, so it stays.
    private var footer: some View {
        VStack(spacing: 0) {
            Group {
                Asset.Assets.zashiLogo.image
                    .zImage(width: Constants.logoSize, height: Constants.logoSize, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._sm)

                Asset.Assets.zashiTitle.image
                    .zImage(width: Constants.wordmarkWidth, height: Constants.wordmarkHeight, style: ZappColors.text)
                    .padding(.bottom, Design.Spacing._xl)
            }
            .onLongPressGesture {
                store.send(.enableRecoverFundsMode)
            }
            .onTapGesture(count: 3) {
                store.send(.enableEnhanceTransactionMode)
            }

            Text(localizable: .settingsVersion(store.appVersion, store.appBuild))
                .zappFont(.caption, style: ZappColors.textSubtle)
                .padding(.bottom, Design.Spacing._3xl)
        }
    }

    @ViewBuilder private func recoverFundsSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .recoverFundsTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._lg)

            Text(localizable: .recoverFundsMsg)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._3xl)

            sheetField(
                title: String(localizable: .recoverFundsFieldTitle),
                placeholder: String(localizable: .recoverFundsPlaceholder),
                text: $store.addressToRecoverFunds
            )
            .padding(.bottom, Design.Spacing._4xl)

            if !store.isTorOn {
                HStack(alignment: .top, spacing: Design.Spacing._lg) {
                    Asset.Assets.infoOutline.image
                        .zImage(size: 20, style: ZappColors.accentText)

                    Text(localizable: .recoverFundsTor)
                        .zappFont(.caption, style: ZappColors.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Design.Spacing._lg)
            }

            ZappButton(
                title: String(localizable: .recoverFundsBtn),
                isEnabled: !store.addressToRecoverFunds.isEmpty && store.isTorOn
            ) {
                store.send(.checkFundsForAddress(store.addressToRecoverFunds))
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func resyncHelpSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .restoreWalletHelpTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._lg)

            HStack(alignment: .top, spacing: Design.Spacing._md) {
                Asset.Assets.infoCircle.image
                    .zImage(size: 20, style: ZappColors.text)

                if let attrText = try? AttributedString(
                    markdown: String(localizable: .walletBirthdayHelpDesc),
                    including: \.zashiApp
                ) {
                    ZashiText(withAttributedString: attrText, colorScheme: colorScheme)
                        .zappFont(.body, style: ZappColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, Design.Spacing._4xl)

            ZappButton(title: String(localizable: .restoreInfoGotIt)) {
                store.send(.closeResyncHelpSheetTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func enhanceTransactionSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .enhanceTransactionTitle)
                .zappFont(.displaySecondary, style: ZappColors.text)
                .padding(.top, Design.Spacing._3xl)
                .padding(.bottom, Design.Spacing._lg)

            Text(localizable: .enhanceTransactionMsg)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._3xl)

            sheetField(
                title: String(localizable: .enhanceTransactionFieldTitle),
                placeholder: String(localizable: .enhanceTransactionPlaceholder),
                text: $store.txidToEnhance
            )
            .padding(.bottom, Design.Spacing._4xl)

            ZappButton(
                title: String(localizable: .enhanceTransactionBtn),
                isEnabled: !store.txidToEnhance.isEmpty
            ) {
                store.send(.fetchDataForTxid(store.txidToEnhance))
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder private func sheetField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing._xs) {
            ZappSectionLabel(text: title)

            TextField(placeholder, text: text, axis: .vertical)
                .zappFont(.mono, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2, reservesSpace: true)
                .padding(Design.Spacing._lg)
                .background(ZappColors.surfaceInput.color(colorScheme))
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationView {
        SettingsView(store: .placeholder)
    }
}

// MARK: Placeholders

extension Settings.State {
    static var initial: Settings.State { Settings.State() }
}

extension StoreOf<Settings> {
    @MainActor static let placeholder = StoreOf<Settings>(
        initialState: .initial
    ) {
        Settings()
    }
}
