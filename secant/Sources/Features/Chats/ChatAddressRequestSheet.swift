//
//  ChatAddressRequestSheet.swift
//  Zapp
//
//  Android's `addressRequestSheet`: Send ZEC in a direct chat with no known address. A bottom
//  sheet, so Ask and Enter sit within thumb reach, stacked like the app's other confirmation
//  sheets.
//

import ComposableArchitecture
import SwiftUI

struct ChatAddressRequestSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Constants {
        static let title = ZappTextStyle(weight: .black, size: 18, lineHeight: 24, tracking: -0.3)
    }

    let prompt: ChatRoom.AddressRequestPrompt
    let onAsk: () -> Void
    let onEnter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localizable: .chatRoomSendZecNoAddressTitle)
                .zappFont(Constants.title, style: ZappColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._xs)

            Text(prompt.message)
                .zappFont(.body, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Design.Spacing._2xl)

            ZappButton(title: String(localizable: .chatRoomSendZecAskForAddress), action: onAsk)
                .padding(.bottom, Design.Spacing._md)

            ZappButton(
                title: String(localizable: .chatRoomSendZecEnterAddress),
                variant: .secondary,
                action: onEnter
            )
        }
        .padding(.horizontal, Design.Spacing._3xl)
        .padding(.top, Design.Spacing._3xl)
        .padding(.bottom, Design.Spacing._lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(ZappColors.surface.color(colorScheme))
    }
}

extension View {
    /// Presents `ChatRoom.State.addressRequest` as `ChatAddressRequestSheet`. Kept out of the room
    /// view's body, whose modifier chain is already at the type checker's limit.
    func chatAddressRequestSheet(store: StoreOf<ChatRoom>) -> some View {
        zashiSheet(
            isPresented: Binding(
                get: { store.addressRequest != nil },
                set: { if !$0 { store.send(.addressRequest(.dismissed)) } }
            ),
            horizontalPadding: 0
        ) {
            Group {
                if let prompt = store.addressRequest {
                    ChatAddressRequestSheet(
                        prompt: prompt,
                        onAsk: { store.send(.addressRequest(.askForAddressTapped)) },
                        onEnter: { store.send(.addressRequest(.enterAddressTapped)) }
                    )
                }
            }
        }
    }
}
