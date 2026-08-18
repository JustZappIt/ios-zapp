//
//  KeystoneFirmwareUpdateView.swift
//  Zashi
//
//  MOB-1510's firmware gate failure screen; mirrors `PreSendingFailureView`'s structure.
//

import SwiftUI
import ComposableArchitecture

struct KeystoneFirmwareUpdateView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let illustrationSize: CGFloat = 148
    }

    @Perception.Bindable var store: StoreOf<SendConfirmation>

    init(store: StoreOf<SendConfirmation>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                store.failureIlustration
                    .resizable()
                    .frame(width: Constants.illustrationSize, height: Constants.illustrationSize)

                Text(String(localizable: .keystoneFirmwareUpdateTitle))
                    .zappFont(.display, style: ZappColors.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._xl)

                Text(bodyText)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Design.Spacing._md)

                Spacer()

                ZappButton(title: String(localizable: .generalClose)) {
                    store.send(.keystoneFirmwareUpdateCloseTapped)
                }
                .padding(.bottom, Design.Spacing._3xl)
            }
            .padding(.horizontal, Design.Spacing._2xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
        }
        .navigationBarBackButtonHidden()
    }

    private var bodyText: String {
        if let detectedVersion = store.detectedKeystoneFirmware {
            return String(
                localizable: .keystoneFirmwareUpdateBody(
                    detectedVersion.versionString,
                    KeystoneDisplayFirmwareVersion.minimumSupported.versionString
                )
            )
        }
        return String(localizable: .keystoneFirmwareUpdateLegacyBody(KeystoneDisplayFirmwareVersion.minimumSupported.versionString))
    }
}

/// Illustration + title + body for the firmware-update prompt; store-less so other presentations
/// of the gate can reuse it.
struct KeystoneFirmwareUpdateContent: View {
    let illustration: Image
    let detectedVersion: KeystoneDisplayFirmwareVersion?

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .resizable()
                .frame(width: 148, height: 148)

            Text(String(localizable: .keystoneFirmwareUpdateTitle))
                .zFont(.semiBold, size: 28, style: Design.Text.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Text(bodyText)
                .zFont(size: 14, style: Design.Text.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .screenHorizontalPadding()
        }
    }

    private var bodyText: String {
        if let detectedVersion {
            return String(
                localizable: .keystoneFirmwareUpdateBody(
                    detectedVersion.versionString,
                    KeystoneDisplayFirmwareVersion.minimumSupported.versionString
                )
            )
        }
        return String(localizable: .keystoneFirmwareUpdateLegacyBody(KeystoneDisplayFirmwareVersion.minimumSupported.versionString))
    }
}

#Preview {
    NavigationView {
        KeystoneFirmwareUpdateView(store: SendConfirmation.initial)
    }
}
