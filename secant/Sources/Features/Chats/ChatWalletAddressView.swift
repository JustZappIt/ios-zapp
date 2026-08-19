//
//  ChatWalletAddressView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// Android's `ChatWalletAddressView`: one card per address, all of them at once, rather than the
/// sub-tabs the profile used to switch between.
struct ChatWalletAddressView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let qrSize: CGFloat = 72
        static let screenInset: CGFloat = 18
    }

    @Perception.Bindable var store: StoreOf<ChatWalletAddress>

    @State private var enlargedAddress: String?

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .chatWalletAddressTitle))

                ScrollView {
                    VStack(spacing: 0) {
                        if store.addresses.isEmpty {
                            addressesUnavailable
                        } else {
                            ForEach(store.addresses) { addressCard($0) }
                        }
                    }
                    .padding(.bottom, Design.Spacing._xl)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .zappSwipeBack(isEnabled: enlargedAddress == nil) { store.send(.backTapped) }
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .zappQRSpotlight(payload: $enlargedAddress) { address, edge in
                ChatIdentityQRCode(payload: address, size: edge)
            } action: { address in
                // The same action the card's copy icon sends, so the pasteboard write and the
                // tick cannot diverge between the two surfaces.
                ZappButton(
                    title: String(localizable: .chatProfileCopyAddress),
                    leadingIcon: Asset.Assets.copy.image
                ) {
                    store.send(.copyAddressTapped(address))
                }
            }
        }
    }

    private func addressCard(_ item: ChatWalletAddress.AddressItem) -> some View {
        VStack(spacing: 0) {
            ZappGroupHeader(text: item.label)

            ZappValueCard(
                value: item.address,
                caption: item.caption,
                leading: {
                    if item.hasQRCode {
                        Button { enlargedAddress = item.address } label: {
                            ChatIdentityQRCode(payload: item.address, size: Constants.qrSize)
                        }
                        .buttonStyle(.zappPress)
                        .accessibilityLabel(String(localizable: .chatWalletAddressQrCode))
                    }
                },
                trailing: {
                    ZappCopyIconButton(
                        isCopied: store.copiedAddress == item.address,
                        accessibilityLabel: String(localizable: .chatProfileCopyAddress)
                    ) {
                        store.send(.copyAddressTapped(item.address))
                    }
                }
            )
        }
    }

    private var addressesUnavailable: some View {
        Text(String(localizable: .chatProfileAddressUnavailable))
            .zappFont(.body, style: ZappColors.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Constants.screenInset)
            .padding(.top, Design.Spacing._3xl)
    }
}

#Preview {
    ChatWalletAddressView(store: ChatWalletAddress.initial)
}
