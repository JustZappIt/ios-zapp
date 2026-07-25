//
//  ChatSplitBillStore.swift
//  Zapp
//
//  Split bill / request payment — Android's `ChatRoomVM.onSplitBillClick`, `onCreateSplit` and
//  `sendSplitRequests`, plus the arithmetic `SplitBillSheet.kt` keeps in `remember` state.
//
//  The sheet's field values live in the store rather than in the view (Android keeps them in
//  composition): the share maths IS the feature, and putting it in state makes every branch of
//  it reachable from a `TestStore` instead of only from a simulator.
//
//  Kept beside `ChatRoomStore` for the same reason `ChatRoomAttachments` is — the room's reducer
//  body is at its length budget.
//

import ComposableArchitecture
import Foundation
import ZappMessaging

extension ChatRoom {
    // MARK: - State

    struct SplitParticipant: Equatable, Identifiable {
        let publicKey: String
        let displayName: String

        var id: String { publicKey }
    }

    /// One participant's resolved share, in ZEC — Android's `SplitShareInput`.
    struct SplitShare: Equatable {
        let publicKey: String
        let displayName: String
        let amount: Decimal
    }

    struct SplitBillState: Equatable {
        var isGroup: Bool
        var participants: [SplitParticipant]
        var totalText = ""
        var memoText = ""
        /// publicKey -> the raw text the user typed over the equal split.
        var shareOverrides: [String: String] = [:]
        /// Android defaults to fiat whenever a rate exists, falling back to ZEC when it does not.
        var isFiat = false
        var isSending = false

        /// A group splits between the participants AND the requester; a direct chat does not
        /// split at all, so the peer is asked for the whole total.
        var divisor: Int {
            isGroup ? participants.count + 1 : 1
        }

        var total: Decimal? {
            ChatDecimalInput.parse(totalText)
        }

        var equalShare: Decimal? {
            guard let total, divisor > 0 else { return total }

            return total / Decimal(divisor)
        }

        /// The equal-split value pre-filled into each participant row, in the displayed unit.
        func displayedShare(for participant: SplitParticipant) -> String {
            if let override = shareOverrides[participant.publicKey] { return override }
            guard let equalShare else { return "" }

            return isFiat
                ? ChatAmountFormat.fiat(ChatAmountFormat.roundedFiat(equalShare))
                : ChatAmountFormat.zec(ChatAmountFormat.roundedZec(equalShare))
        }

        /// Android's `computeShares`: an override wins over the equal split, anything not
        /// positive drops out, and a fiat entry is converted to ZEC before it leaves the sheet.
        func shares(rate: ChatFiatRate?) -> [SplitShare] {
            let usesFiat = isFiat && rate != nil

            return participants.compactMap { participant in
                let entered = shareOverrides[participant.publicKey].flatMap(ChatDecimalInput.parse)

                guard let displayed = entered ?? equalShare, displayed > 0 else { return nil }

                let zec = usesFiat && rate != nil
                    ? ChatAmountFormat.roundedZec(rate?.fiatToZec(displayed) ?? displayed)
                    : displayed

                return SplitShare(
                    publicKey: participant.publicKey,
                    displayName: participant.displayName,
                    amount: zec
                )
            }
        }

        func canSend(rate: ChatFiatRate?) -> Bool {
            guard !isSending, let total, total > 0 else { return false }

            return !shares(rate: rate).isEmpty
        }
    }

    // MARK: - Reducer

    // One branch per sheet control, as with `attachmentReduce()`.
    // swiftlint:disable:next cyclomatic_complexity
    func splitBillReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .splitBillTapped:
                state.showsAttachmentSheet = false

                // Android bails with a toast when the conversation has not loaded yet — there is
                // no participant list to split between.
                guard let conversation = state.conversation else {
                    state.sendDidFail = true
                    state.sendFailureMessage = String(localizable: .chatRoomSplitConversationUnavailable)
                    return .none
                }

                let participants = state.splitParticipants(of: conversation)

                guard !participants.isEmpty else { return .none }

                state.sendDidFail = false
                state.sendFailureMessage = nil
                state.splitBill = SplitBillState(
                    isGroup: conversation.type == .group,
                    participants: participants,
                    // Fiat leads when a rate exists, matching `shouldDefaultToFiat`.
                    isFiat: state.chatFiatRate != nil
                )
                return .none

            case .splitSheetDismissed:
                state.splitBill = nil
                return .none

            case .splitTotalChanged(let text):
                state.splitBill?.totalText = text
                return .none

            case .splitMemoChanged(let text):
                state.splitBill?.memoText = text
                return .none

            case let .splitShareChanged(publicKey, text):
                state.splitBill?.shareOverrides[publicKey] = text
                return .none

            // Converting the total keeps the number the user is looking at meaningful; the
            // per-share overrides are cleared because they were typed in the old unit.
            case .splitCurrencyToggled:
                guard let rate = state.chatFiatRate, var split = state.splitBill else { return .none }

                let next = !split.isFiat

                if let total = split.total {
                    let converted = next ? rate.zecToFiat(total) : rate.fiatToZec(total)
                    split.totalText = next
                        ? ChatAmountFormat.fiat(ChatAmountFormat.roundedFiat(converted))
                        : ChatAmountFormat.zec(ChatAmountFormat.roundedZec(converted))
                }

                split.shareOverrides.removeAll()
                split.isFiat = next
                state.splitBill = split
                return .none

            case .splitSendTapped:
                guard
                    let split = state.splitBill,
                    let requesterAddress = state.zashiWalletAccount?.unifiedAddress,
                    !requesterAddress.isEmpty
                else {
                    state.splitBill = nil
                    state.sendDidFail = true
                    state.sendFailureMessage = String(localizable: .chatRoomSplitFailed)
                    return .none
                }

                let rate = state.chatFiatRate
                let shares = split.shares(rate: rate)

                // Android drops the whole batch if ANY share is out of range, rather than
                // sending a partial split the group would have to reconcile by hand.
                let isValid = !shares.isEmpty && shares.allSatisfy {
                    $0.amount > 0 && $0.amount <= ChatPaymentRequest.maxZec
                }

                guard isValid else {
                    state.splitBill = nil
                    return .none
                }

                let payloads = ChatRoom.splitPayloads(
                    shares: shares,
                    memo: split.memoText.trimmingCharacters(in: .whitespacesAndNewlines),
                    requesterAddress: requesterAddress,
                    isGroup: split.isGroup,
                    rate: rate
                )

                state.splitBill = nil
                state.sendDidFail = false
                state.sendFailureMessage = nil
                let conversationId = state.conversationId

                return .run { send in
                    for payload in payloads {
                        let message = try await zappMessaging.sendPaymentRequest(conversationId, payload)
                        await send(.messageReceived(message))
                    }
                } catch: { error, send in
                    LoggerProxy.error("Chat room failed to send split requests: \(error)")
                    await send(.splitSendFailed)
                }

            case .splitSendFailed:
                state.sendDidFail = true
                state.sendFailureMessage = String(localizable: .chatRoomSplitFailed)
                return .none

            default:
                return .none
            }
        }
    }

    /// One payload per share — Android sends N separate payment-request messages, each with its
    /// own id and debtor, linked only by the shared memo and `splitCount`.
    static func splitPayloads(
        shares: [SplitShare],
        memo: String,
        requesterAddress: String,
        isGroup: Bool,
        rate: ChatFiatRate?
    ) -> [String] {
        // `shares.size + 1` in a group: the requester is paying a share too.
        let splitCount = isGroup ? shares.count + 1 : 1

        return shares.compactMap { share in
            let fiatAmount = rate.map { ChatAmountFormat.roundedFiat($0.zecToFiat(share.amount)) }

            return ChatPaymentRequest.json(
                id: UUID().uuidString,
                amount: share.amount,
                requesterAddress: requesterAddress,
                memo: memo.isEmpty ? nil : memo,
                debtorId: share.publicKey,
                debtorName: share.displayName,
                splitCount: splitCount,
                fiatAmount: fiatAmount,
                fiatCurrency: rate?.currency.code
            )
        }
    }
}

// MARK: - Participants

extension ChatRoom.State {
    var chatFiatRate: ChatFiatRate? {
        ChatFiatRate(currencyConversion)
    }

    /// Everyone but us, named the way Android names them: saved contact alias, else the
    /// conversation's own name in a 1:1, else a shortened key.
    func splitParticipants(of conversation: ZMConversation) -> [ChatRoom.SplitParticipant] {
        let ownKey = messagingState.identity.map { PublicKeyRules.sanitize($0.publicKey) }
        let isGroup = conversation.type == .group

        return conversation.participantIds
            .filter { PublicKeyRules.sanitize($0) != ownKey }
            .map { key in
                let alias = chatContacts.contact(for: key)?.name
                let fallback = !isGroup && !conversation.displayName.isEmpty
                    ? conversation.displayName
                    : ChatKeyPreview.short(key)

                return ChatRoom.SplitParticipant(
                    publicKey: key,
                    displayName: alias?.isEmpty == false ? (alias ?? fallback) : fallback
                )
            }
    }
}

/// Android's `shortKey`: keys long enough to elide get a `6…4` preview.
enum ChatKeyPreview {
    static let threshold = 12
    static let prefix = 6
    static let suffix = 4

    static func short(_ key: String) -> String {
        guard key.count > threshold else { return key }

        return "\(key.prefix(prefix))…\(key.suffix(suffix))"
    }
}

/// Decimal entry that accepts what the user's keyboard produces. Android leans on
/// `toBigDecimalLocalized()`; this accepts the current locale's separator and the POSIX dot,
/// because an iOS numeric keypad can emit either depending on the region.
enum ChatDecimalInput {
    static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = trimmed
            .replacingOccurrences(of: separator, with: ".")
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        return value
    }
}
