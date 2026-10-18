//
//  RequestZecQRActionsView.swift
//  Zapp
//
//  "Save QR to Photos" and "Send in chat" under the Request QR — Android's two `QrActionButton`s in
//  `RequestQrCodeView.kt` — plus the contact picker sheet and the save outcome notice.
//

import ComposableArchitecture
import SwiftUI

struct RequestZecQRActionsView: View {
    @Environment(\.openURL) private var openURL

    @Perception.Bindable var store: StoreOf<RequestZec>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: Design.Spacing._lg) {
                ZappButton(
                    title: String(localizable: .requestZecSummarySaveQR),
                    variant: .secondary,
                    isEnabled: store.encryptedOutput != nil && store.qrSaveOutcome != .saving,
                    leadingIcon: Asset.Assets.Icons.save.image
                ) {
                    store.send(.saveQRTapped)
                }

                ZappButton(
                    title: String(localizable: .requestZecSummarySendInChat),
                    variant: .secondary,
                    leadingIcon: Asset.Assets.Icons.messageChat.image
                ) {
                    store.send(.sendInChatTapped)
                }

                saveNotice
            }
            .zashiSheet(isPresented: isPickerPresented) {
                Group {
                    if let pickerStore = store.scope(state: \.chatPicker, action: \.chatPicker) {
                        RequestChatPickerView(store: pickerStore)
                    }
                }
            }
        }
    }

    /// Dismissal goes through the reducer, which refuses it while a request is in flight.
    private var isPickerPresented: Binding<Bool> {
        Binding(
            get: { store.chatPicker != nil },
            set: { isPresented in
                if !isPresented {
                    store.send(.chatPickerDismissRequested)
                }
            }
        )
    }

    /// Inline rather than a toast: the Request chain is a full-screen cover and the app's toast
    /// overlay lives on `RootView` underneath it — the same reason `ChatImageViewer` does this.
    @ViewBuilder private var saveNotice: some View {
        switch store.qrSaveOutcome {
        case .saved:
            Text(String(localizable: .requestZecSummarySaved))
                .zappFont(.caption, style: ZappColors.success)

        case .failed:
            Text(String(localizable: .requestZecSummarySaveFailed))
                .zappFont(.caption, style: ZappColors.danger)

        // Refusing photo-library access is permanent, so offer the Settings deep link the chat
        // image viewer offers rather than dead-ending on a failure line.
        case .notAuthorized:
            VStack(spacing: Design.Spacing._md) {
                Text(String(localizable: .chatRoomImageViewerSaveNoAccess))
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ZappButton(title: String(localizable: .scanOpenSettings), variant: .ghost) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }

        case .saving, .none:
            EmptyView()
        }
    }
}
