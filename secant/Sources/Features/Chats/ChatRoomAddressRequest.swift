//
//  ChatRoomAddressRequest.swift
//  Zapp
//
//  Send ZEC in a direct chat with no known address: Android's `addressRequestSheet` (PR #87).
//  The room asks "Ask for their address" or "Enter an address" instead of opening an empty form.
//
//  Its own reducer, composed after the attachment menu's: Send ZEC is chosen from the attachment
//  sheet, and the prompt is raised only once that sheet has finished closing (iOS drops a
//  presentation made while another sheet is still on screen).
//

import ComposableArchitecture
import Foundation

extension ChatRoom {
    /// `name` is what the chat header shows, so the prompt never says a key prefix the header has
    /// already replaced with the peer's name.
    struct AddressRequestPrompt: Equatable {
        let name: String?

        var message: String {
            if let name, !name.isEmpty {
                return String(localizable: .chatRoomSendZecNoAddressMessage(name))
            }
            return String(localizable: .chatRoomSendZecNoAddressMessageUnnamed)
        }
    }

    func addressRequestReduce() -> Reduce<ChatRoom.State, ChatRoom.Action> {
        Reduce { state, action in
            switch action {
            // Root waits on `needsPeerAddressRequest` instead of opening the empty form.
            case .sendZecTapped:
                if state.needsPeerAddressRequest {
                    state.isAddressRequestPending = true
                }
                return .none

            case .attachmentSheetClosed:
                guard state.isAddressRequestPending else { return .none }

                state.isAddressRequestPending = false
                state.addressRequest = AddressRequestPrompt(
                    name: state.conversation?.resolvedDisplayName(state.chatContacts)
                )
                return .none

            // Posted only when tapped, so asking stays the user's choice.
            case .addressRequest(.askForAddressTapped):
                state.addressRequest = nil
                return postCannedText(String(localizable: .chatRoomSendZecAddressRequestText), state: &state)

            // Root opens the empty send form.
            case .addressRequest(.enterAddressTapped), .addressRequest(.dismissed):
                state.addressRequest = nil
                return .none

            default:
                return .none
            }
        }
    }
}
