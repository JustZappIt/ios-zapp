//
//  ChatPrivacySettingView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

enum ChatPrivacySetting {
    case readReceipts
    case onlineStatus

    var title: String {
        switch self {
        case .readReceipts: String(localizable: .chatProfileReadReceipts)
        case .onlineStatus: String(localizable: .chatProfilePresence)
        }
    }

    var subtitle: String {
        switch self {
        case .readReceipts: String(localizable: .chatProfileReadReceiptsHint)
        case .onlineStatus: String(localizable: .chatProfilePresenceHint)
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
                    ZappSettingsGroup(title: String(localizable: .chatProfilePrivacy)) {
                        ZappToggleRow(
                            title: setting.title,
                            subtitle: setting.subtitle,
                            icon: setting.icon,
                            iconTint: .accentText,
                            iconBackground: .accentSoft,
                            isOn: draftValue
                        ) {
                            draftValue.toggle()
                        }
                    }
                    .padding(.top, Design.Spacing._lg)
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
