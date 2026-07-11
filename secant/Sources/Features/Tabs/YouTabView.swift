//
//  YouTabView.swift
//  Zapp
//
//  Zapp fork: iOS analog of android-zapp's `SettingsTabContent` - the
//  decluttered You tab. Renders ZODL's Settings feature as tab content in the
//  Zapp grouped-rows arrangement; the Settings reducer, its navigation path,
//  and every pushed screen stay upstream-identical. The chat profile card and
//  People/chat rows arrive with the messaging phase (seam documented in
//  docs/zapp-phase2-shell.md).
//
//  Destination and sheet wiring below mirrors upstream SettingsView, which is
//  no longer mounted - when upstream adds a Settings.Path case, mirror it here
//  (sync review hotspot).
//

import SwiftUI
import ComposableArchitecture

struct YouTabView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<Settings>

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                VStack(spacing: 0) {
                    ZappScreenHeader(title: String(localizable: .zappTabYou))

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            group(String(localizable: .zappYouGroupPeople)) {
                                ZappRow(
                                    title: String(localizable: .settingsAddressBook),
                                    icon: Asset.Assets.Icons.user.image
                                ) {
                                    store.send(.addressBookAccessCheck)
                                }
                            }

                            group(String(localizable: .zappYouGroupWallet)) {
                                if store.isEnoughFreeSpaceMode {
                                    ZappRow(
                                        title: String(localizable: .currencyConversionTitle),
                                        icon: Asset.Assets.Icons.currencyDollar.image
                                    ) {
                                        store.send(.currencyConversionTapped)
                                    }

                                    ZappRowDivider(inset: true)
                                }

                                ZappRow(
                                    title: String(localizable: .settingsCoinholderPolling),
                                    icon: Asset.Assets.Icons.checkVerified.image
                                ) {
                                    store.send(.coinholderPollingTapped)
                                }

                                ZappRowDivider(inset: true)

                                ZappRow(
                                    title: String(localizable: .settingsAdvanced),
                                    subtitle: String(localizable: .zappYouAdvancedSubtitle),
                                    icon: Asset.Assets.Icons.settings.image
                                ) {
                                    store.send(.advancedSettingsTapped)
                                }
                            }

                            group(String(localizable: .zappYouGroupSupport)) {
                                ZappRow(
                                    title: String(localizable: .settingsWhatsNew),
                                    icon: Asset.Assets.Icons.magicWand.image
                                ) {
                                    store.send(.whatsNewTapped)
                                }

                                ZappRowDivider(inset: true)

                                ZappRow(
                                    title: String(localizable: .settingsAbout),
                                    icon: Asset.Assets.infoOutline.image
                                ) {
                                    store.send(.aboutTapped)
                                }

                                ZappRowDivider(inset: true)

                                ZappRow(
                                    title: String(localizable: .settingsFeedback),
                                    icon: Asset.Assets.Icons.messageSmile.image
                                ) {
                                    store.send(.sendUsFeedbackTapped)
                                }
                            }

                            versionFooter()
                        }
                        .padding(.bottom, ZappNavBar.clearance)
                    }
                }
                .background(ZappColor.bg(colorScheme))
                .onAppear { store.send(.onAppear) }
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
                WithPerceptionTracking {
                    VotingCoordFlowView(store: votingStore)
                }
            }
        }
    }
}

// MARK: - Grouped card (Android SettingsGroup + ZappGroupHeader)

private extension YouTabView {
    @ViewBuilder func group(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        ZappSectionLabel(text: title)
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 8)

        VStack(spacing: 0) {
            content()
        }
        .background(ZappColor.surface(colorScheme))
        .overlay {
            Rectangle()
                .stroke(ZappColor.border(colorScheme), lineWidth: 1)
        }
        .padding(.horizontal, 14)
    }

    // MARK: Version footer (keeps upstream's hidden diagnostics gestures)

    @ViewBuilder func versionFooter() -> some View {
        VStack(spacing: 6) {
            Asset.Assets.zashiLogo.image
                .zImage(width: 32, height: 32, color: ZappColor.textSubtle(colorScheme))
                .onLongPressGesture {
                    store.send(.enableRecoverFundsMode)
                }
                .onTapGesture(count: 3) {
                    store.send(.enableEnhanceTransactionMode)
                }

            Text(localizable: .settingsVersion(store.appVersion, store.appBuild))
                .zFont(size: 12, color: ZappColor.textSubtle(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }

    // MARK: Sheets (mirrored from upstream SettingsView)

    @ViewBuilder func recoverFundsSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .recoverFundsTitle)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(localizable: .recoverFundsMsg)
                .zFont(size: 14, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            ZashiTextField(
                addressFont: true,
                text: $store.addressToRecoverFunds,
                placeholder: String(localizable: .recoverFundsPlaceholder),
                title: String(localizable: .recoverFundsFieldTitle)
            )
            .padding(.bottom, 32)

            if !store.isTorOn {
                HStack(alignment: .top, spacing: 0) {
                    Asset.Assets.infoOutline.image
                        .zImage(size: 20, style: Design.Utility.WarningYellow._500)
                        .padding(.trailing, 12)

                    Text(localizable: .recoverFundsTor)
                        .zFont(size: 12, style: Design.Utility.WarningYellow._700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 12)
            }

            ZashiButton(String(localizable: .recoverFundsBtn)) {
                store.send(.checkFundsForAddress(store.addressToRecoverFunds))
            }
            .disabled(store.addressToRecoverFunds.isEmpty || !store.isTorOn)
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder func resyncHelpSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .restoreWalletHelpTitle)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .padding(.top, 24)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 8) {
                Asset.Assets.infoCircle.image
                    .zImage(size: 20, style: Design.Text.primary)

                if let attrText = try? AttributedString(
                    markdown: String(localizable: .walletBirthdayHelpDesc),
                    including: \.zashiApp
                ) {
                    ZashiText(withAttributedString: attrText, colorScheme: colorScheme)
                        .zFont(size: 14, style: Design.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 32)

            ZashiButton(String(localizable: .restoreInfoGotIt)) {
                store.send(.closeResyncHelpSheetTapped)
            }
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }

    @ViewBuilder func enhanceTransactionSheetContent() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .enhanceTransactionTitle)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text(localizable: .enhanceTransactionMsg)
                .zFont(size: 14, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            ZashiTextField(
                addressFont: true,
                text: $store.txidToEnhance,
                placeholder: String(localizable: .enhanceTransactionPlaceholder),
                title: String(localizable: .enhanceTransactionFieldTitle)
            )
            .padding(.bottom, 32)

            ZashiButton(String(localizable: .enhanceTransactionBtn)) {
                store.send(.fetchDataForTxid(store.txidToEnhance))
            }
            .disabled(store.txidToEnhance.isEmpty)
            .padding(.bottom, Design.Spacing.sheetBottomSpace)
        }
    }
}
