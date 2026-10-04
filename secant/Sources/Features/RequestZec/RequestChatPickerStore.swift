//
//  RequestChatPickerStore.swift
//  Zapp
//
//  "Send in chat" from the Request QR page: pick a chat contact and the same request goes to them
//  as an `application/payment-request` message. Mirrors the "Send in chat" block of Android's
//  `RequestVM.kt` (`onSendInChatClick` … `sendRequestInChat`): get-or-create the DM, build the
//  body with the one shared payload builder, send it, then open the conversation.
//

import ComposableArchitecture
import Foundation
import ZappMessaging

@Reducer
struct RequestChatPicker {
    /// What goes on the wire, captured from the QR page when the picker opens. The requester
    /// address is the address the QR encodes, exactly as Android passes `walletAddress.address`.
    struct Request: Equatable {
        var requesterAddress: String
        var zecAmount: Decimal
        var memo: String
        /// The fiat amount the user typed on the keyboard, or nil when they typed ZEC.
        var typedFiatAmount: Decimal?
    }

    @ObservableState
    struct State: Equatable {
        @Shared(.inMemory(.chatContacts)) var chatContacts: ChatContacts = .empty
        @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil

        var request: Request
        var isSending = false
        var didFail = false

        /// Android lists blocked contacts here too. Sending a request to someone whose replies
        /// are dropped is a dead end, so they are left out, as New chat already does.
        var contacts: [ChatContact] {
            chatContacts.saved.filter { !$0.isBlocked }
        }

        init(request: Request) {
            self.request = request
        }
    }

    enum Action: Equatable {
        case contactTapped(ChatContact)
        case delegate(Delegate)
        case sendFailed

        @CasePathable
        enum Delegate: Equatable {
            case sent(ZMConversation)
        }
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.zappMessaging) var zappMessaging

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .contactTapped(let contact):
                guard !state.isSending else { return .none }

                // Android's `UUID.randomUUID().toString()` is lowercase; the id only has to round-trip
                // verbatim through the payer's receipt, but matching the format keeps wire diffs clean.
                guard let payload = Self.payload(
                    for: state.request,
                    rate: ChatFiatRate(state.currencyConversion),
                    id: uuid().uuidString.lowercased()
                ) else {
                    state.didFail = true
                    return .none
                }

                state.isSending = true
                state.didFail = false

                return .run { send in
                    let conversation = try await zappMessaging.createDirectConversation(contact.publicKey, contact.name)
                    _ = try await zappMessaging.sendPaymentRequest(conversation.id, payload)
                    await send(.delegate(.sent(conversation)))
                } catch: { error, send in
                    LoggerProxy.error("RequestChatPicker: send in chat failed: \(error)")
                    await send(.sendFailed)
                }

            // Android only clears its spinner here; the request silently goes nowhere. Saying so
            // lets the user pick again or fall back to the QR.
            case .sendFailed:
                state.isSending = false
                state.didFail = true
                return .none

            case .delegate:
                return .none
            }
        }
    }

    /// `sendRequestInChat`'s body. Nil when the amount is not positive, which Android also refuses
    /// to send. Fiat rides along only when a rate is known: the amount the user typed if they typed
    /// fiat, otherwise the ZEC amount converted, both at Android's 2-decimal HALF_UP scale.
    static func payload(for request: Request, rate: ChatFiatRate?, id: String) -> String? {
        guard request.zecAmount > 0 else { return nil }

        let fiatAmount = rate.map {
            ChatAmountFormat.roundedFiat(request.typedFiatAmount ?? $0.zecToFiat(request.zecAmount))
        }

        return ChatPaymentRequest.json(
            id: id,
            amount: request.zecAmount,
            requesterAddress: request.requesterAddress,
            memo: request.memo,
            fiatAmount: fiatAmount,
            fiatCurrency: rate?.currency.code
        )
    }
}
