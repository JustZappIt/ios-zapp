//
//  ChatPrivacySettingView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// One titled explanation paragraph, mirroring the `InfoBlock` composable that both
/// `ReadReceiptsSettingsView.kt` and `OnlineStatusSettingsView.kt` declare.
struct ChatPrivacyInfoBlock: Identifiable {
    let id: Int
    let title: String
    let body: String
}

enum ChatPrivacySetting {
    case readReceipts
    case onlineStatus

    var title: String {
        switch self {
        case .readReceipts: String(localizable: .chatProfileReadReceipts)
        case .onlineStatus: String(localizable: .chatProfilePresence)
        }
    }

    /// The paragraph under the hero icon, above the explanation blocks.
    var intro: String {
        switch self {
        case .readReceipts: String(localizable: .chatPrivacyReadReceiptsIntro)
        case .onlineStatus: String(localizable: .chatPrivacyOnlineStatusIntro)
        }
    }

    var toggleTitle: String {
        switch self {
        case .readReceipts: String(localizable: .chatPrivacyReadReceiptsToggleTitle)
        case .onlineStatus: String(localizable: .chatPrivacyOnlineStatusToggleTitle)
        }
    }

    var toggleSubtitle: String {
        switch self {
        case .readReceipts: String(localizable: .chatPrivacyReadReceiptsToggleSubtitle)
        case .onlineStatus: String(localizable: .chatPrivacyOnlineStatusToggleSubtitle)
        }
    }

    /// Android shows all three blocks unconditionally — the "on"/"off" titles describe what the
    /// setting does in each position, they are not a rendering of the current value.
    var infoBlocks: [ChatPrivacyInfoBlock] {
        switch self {
        case .readReceipts:
            [
                ChatPrivacyInfoBlock(
                    id: 0,
                    title: String(localizable: .chatPrivacyReadReceiptsOnTitle),
                    body: String(localizable: .chatPrivacyReadReceiptsOnBody)
                ),
                ChatPrivacyInfoBlock(
                    id: 1,
                    title: String(localizable: .chatPrivacyReadReceiptsOffTitle),
                    body: String(localizable: .chatPrivacyReadReceiptsOffBody)
                ),
                ChatPrivacyInfoBlock(
                    id: 2,
                    title: String(localizable: .chatPrivacyReadReceiptsBothSidesTitle),
                    body: String(localizable: .chatPrivacyReadReceiptsBothSidesBody)
                )
            ]
        case .onlineStatus:
            [
                ChatPrivacyInfoBlock(
                    id: 0,
                    title: String(localizable: .chatPrivacyOnlineStatusOnTitle),
                    body: String(localizable: .chatPrivacyOnlineStatusOnBody)
                ),
                ChatPrivacyInfoBlock(
                    id: 1,
                    title: String(localizable: .chatPrivacyOnlineStatusOffTitle),
                    body: String(localizable: .chatPrivacyOnlineStatusOffBody)
                ),
                ChatPrivacyInfoBlock(
                    id: 2,
                    title: String(localizable: .chatPrivacyOnlineStatusReciprocalTitle),
                    body: String(localizable: .chatPrivacyOnlineStatusReciprocalBody)
                )
            ]
        }
    }

    var icon: Image {
        switch self {
        case .readReceipts: Asset.Assets.Icons.checkSolid.image
        case .onlineStatus: Asset.Assets.Icons.user.image
        }
    }
}

/// Android-style staged privacy setting: Back discards the draft and Save applies it.
struct ChatPrivacySettingView: View {
    private typealias Constants = ChatPrivacySettingConstants

    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<ChatProfile>
    let setting: ChatPrivacySetting
    let onBack: () -> Void

    @State private var draftValue: Bool

    init(
        store: StoreOf<ChatProfile>,
        setting: ChatPrivacySetting,
        initialValue: Bool,
        onBack: @escaping () -> Void
    ) {
        self.store = store
        self.setting = setting
        self.onBack = onBack
        _draftValue = State(initialValue: initialValue)
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: setting.title)

                ScrollView {
                    VStack(spacing: 0) {
                        explanation

                        ZappSettingsGroup(title: String(localizable: .chatPrivacySectionControl)) {
                            ZappToggleRow(
                                title: setting.toggleTitle,
                                subtitle: setting.toggleSubtitle,
                                icon: setting.icon,
                                iconTint: .accentText,
                                iconBackground: .accentSoft,
                                isOn: draftValue
                            ) {
                                draftValue.toggle()
                            }
                        }
                    }
                    .padding(.bottom, Design.Spacing._xl)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zashiBack(
                primaryAction: {
                    ZappButton(
                        title: String(localizable: .chatProfileSave),
                        isEnabled: draftValue != currentValue && !isBusy
                    ) {
                        save()
                    }
                },
                customDismiss: onBack
            )
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 0) {
            setting.icon
                .zImage(width: Constants.heroIconSize, height: Constants.heroIconSize, style: ZappColors.accentText)
                .frame(width: Constants.heroBoxSize, height: Constants.heroBoxSize)
                .background(ZappColors.accentSoft.color(colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: Design.Spacing._xl)

            Text(setting.intro)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: Design.Spacing._3xl)

            ForEach(setting.infoBlocks) { block in
                Text(block.title)
                    .zappFont(.sectionTitle, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: Design.Spacing._sm)

                Text(block.body)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: Constants.infoBlockSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Design.Spacing._xl)
    }

    private var currentValue: Bool {
        switch setting {
        case .readReceipts: store.readReceiptsEnabled
        case .onlineStatus: store.presenceVisible
        }
    }

    private var isBusy: Bool {
        switch setting {
        case .readReceipts: store.isReadReceiptsBusy
        case .onlineStatus: store.isPresenceBusy
        }
    }

    private func save() {
        guard draftValue != currentValue, !isBusy else { return }

        switch setting {
        case .readReceipts:
            store.send(.readReceiptsToggled)
        case .onlineStatus:
            store.send(.presenceToggled)
        }

        onBack()
    }
}

private enum ChatPrivacySettingConstants {
    static let horizontalPadding: CGFloat = 18
    static let infoBlockSpacing: CGFloat = 18
    static let heroBoxSize: CGFloat = 64
    static let heroIconSize: CGFloat = 32
}
