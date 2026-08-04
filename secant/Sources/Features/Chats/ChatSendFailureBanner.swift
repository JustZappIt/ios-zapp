//
//  ChatSendFailureBanner.swift
//  Zapp
//
//  The strip above the composer that reports why the last attachment or send did not go through.
//  Shared by the room and the support chat, which run the identical attachment reducer branches.
//
//  One failure is recoverable from inside iOS Settings rather than by retrying — a denied camera
//  permission — and `ScanView` already established how this app offers that: a `ZappButton`
//  titled `scan.openSettings` that deep-links into the app's Settings page. The same button is
//  offered here rather than the bare "enable it in Settings" sentence the tile used to end on.
//

import SwiftUI

struct ChatSendFailureBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing._md) {
            Text(message ?? String(localizable: .chatRoomSendFailed))
                .zappFont(.caption, style: ZappColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)

            if ChatSendFailure.offersSettings(message) {
                ZappButton(title: String(localizable: .scanOpenSettings)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
        .padding(.horizontal, Design.Spacing._xl)
        .padding(.top, Design.Spacing._md)
        .background(ZappColors.surface.color(colorScheme))
    }
}

/// The same strip while an attachment is on its way — a multi-megabyte GIF would otherwise leave
/// the composer looking idle for the whole upload.
struct ChatSendingMediaBanner: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Design.Spacing._sm) {
            ProgressView()
                .controlSize(.small)
                .tint(ZappColors.textSubtle.color(colorScheme))

            Text(String(localizable: .chatRoomSendingMedia))
                .zappFont(.caption, style: ZappColors.textSubtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing._xl)
        .padding(.top, Design.Spacing._md)
        .background(ZappColors.surface.color(colorScheme))
    }
}

enum ChatSendFailure {
    /// Derived from the message rather than tracked as its own flag: every path that clears
    /// `sendDidFail` already clears the message with it, so the button cannot be stranded on a
    /// later, unrelated failure.
    static func offersSettings(_ message: String?) -> Bool {
        message == String(localizable: .chatRoomCameraPermissionRequired)
    }
}

#Preview {
    VStack(spacing: 0) {
        ChatSendFailureBanner(message: String(localizable: .chatRoomCameraPermissionRequired))
        ChatSendFailureBanner(message: String(localizable: .chatRoomCameraUnavailable))
    }
    .applyScreenBackground()
}
