//
//  ChatSplitBillTests.swift
//  zodlTests
//
//  Phase 6 — split bill / request payment. The share arithmetic is the feature, so it is pinned
//  here rather than left to a simulator: an equal split that is off by a decimal, or a group
//  `splitCount` that disagrees with Android's, produces requests that look wrong on the peer.
//

import ComposableArchitecture
import Foundation
import Testing
import ZappMessaging
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

// Serialized: the split path reads the process-wide `zashiWalletAccount` and `exchangeRate`
// shared stores.
@Suite(.serialized) struct ChatSplitBillTests {
    private static let unifiedAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    private func zashiAccount() throws -> WalletAccount {
        var account = WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: 0, count: 16)),
                name: "Zodl",
                keySource: nil,
                seedFingerprint: nil,
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
        account.defaultUA = try UnifiedAddress(encoding: Self.unifiedAddress, network: .testnet)

        return account
    }

    private func participants(_ count: Int) -> [ChatRoom.SplitParticipant] {
        (0..<count).map { .init(publicKey: "key\($0)", displayName: "peer\($0)") }
    }

    private func rate(_ pricePerZec: Double) -> ChatFiatRate? {
        ChatFiatRate(CurrencyConversion(.usd, ratio: pricePerZec, timestamp: 0))
    }

    // MARK: - Share arithmetic (`SplitBillSheet.kt: computeShares`)

    /// A GROUP splits between the participants AND the requester, so three peers means a
    /// four-way split — Android's `participants.size + 1`.
    @Test func aGroupSplitsBetweenParticipantsAndTheRequester() {
        var split = ChatRoom.SplitBillState(isGroup: true, participants: participants(3))
        split.totalText = "12"

        #expect(split.divisor == 4)
        #expect(split.equalShare == Decimal(3))

        let shares = split.shares(rate: nil)

        #expect(shares.count == 3)
        #expect(shares.allSatisfy { $0.amount == Decimal(3) })
    }

    /// A DIRECT chat does not split at all: the peer is asked for the whole total.
    @Test func aDirectChatRequestsTheWholeTotal() {
        var split = ChatRoom.SplitBillState(isGroup: false, participants: participants(1))
        split.totalText = "7.5"

        #expect(split.divisor == 1)

        let shares = split.shares(rate: nil)

        #expect(shares.count == 1)
        #expect(shares.first?.amount == Decimal(string: "7.5"))
    }

    @Test func anOverrideWinsOverTheEqualSplit() {
        var split = ChatRoom.SplitBillState(isGroup: true, participants: participants(2))
        split.totalText = "9"
        split.shareOverrides["key0"] = "5"

        let shares = split.shares(rate: nil)

        #expect(shares.first { $0.publicKey == "key0" }?.amount == Decimal(5))
        #expect(shares.first { $0.publicKey == "key1" }?.amount == Decimal(3))
    }

    /// Anything not positive drops out entirely rather than becoming a zero-value request.
    @Test func nonPositiveSharesAreDropped() {
        var split = ChatRoom.SplitBillState(isGroup: true, participants: participants(2))
        split.totalText = "10"
        split.shareOverrides["key0"] = "0"

        let shares = split.shares(rate: nil)

        #expect(shares.count == 1)
        #expect(shares.first?.publicKey == "key1")
    }

    /// A fiat entry is converted to ZEC before it leaves the sheet — the wire only ever carries
    /// ZEC in `amount`.
    @Test func fiatEntriesAreConvertedToZecBeforeSending() throws {
        var split = ChatRoom.SplitBillState(isGroup: false, participants: participants(1))
        split.isFiat = true
        split.totalText = "100"

        let shares = split.shares(rate: rate(50))

        #expect(shares.first?.amount == Decimal(2))
    }

    @Test func canSendRequiresAPositiveTotalAndAtLeastOneShare() {
        var split = ChatRoom.SplitBillState(isGroup: false, participants: participants(1))

        #expect(!split.canSend(rate: nil))

        split.totalText = "0"
        #expect(!split.canSend(rate: nil))

        split.totalText = "1"
        #expect(split.canSend(rate: nil))

        split.isSending = true
        #expect(!split.canSend(rate: nil))
    }

    // MARK: - Payload construction (`ChatRoomVM.kt: sendSplitRequests`)

    /// One message per share, each with its own id and debtor, linked only by the shared memo
    /// and `splitCount` — there is no split-group id on the wire, and inventing one would not
    /// interop.
    @Test func aGroupSplitBuildsOnePayloadPerShareWithSplitCount() throws {
        let shares = [
            ChatRoom.SplitShare(publicKey: "key0", displayName: "peer0", amount: Decimal(3)),
            ChatRoom.SplitShare(publicKey: "key1", displayName: "peer1", amount: Decimal(3)),
            ChatRoom.SplitShare(publicKey: "key2", displayName: "peer2", amount: Decimal(3))
        ]

        let payloads = ChatRoom.splitPayloads(
            shares: shares,
            memo: "Dinner",
            requesterAddress: "utest1abc",
            isGroup: true,
            rate: nil
        )

        #expect(payloads.count == 3)

        let parsed = payloads.map(ChatPaymentRequest.parse)

        // `shares.size + 1`: the requester is paying a share too.
        #expect(parsed.allSatisfy { $0.splitCount == 4 })
        #expect(parsed.allSatisfy { $0.memo == "Dinner" })
        #expect(parsed.allSatisfy { $0.requesterAddress == "utest1abc" })
        #expect(parsed.compactMap(\.debtorId).sorted() == ["key0", "key1", "key2"])
        #expect(parsed.compactMap(\.debtorName).sorted() == ["peer0", "peer1", "peer2"])
        // Each request is independently settleable, so each needs its own id.
        #expect(Set(parsed.compactMap(\.id)).count == 3)
    }

    /// A direct request writes `splitCount = 1`, which is what suppresses Android's split chip.
    @Test func aDirectRequestWritesSplitCountOne() {
        let payloads = ChatRoom.splitPayloads(
            shares: [.init(publicKey: "key0", displayName: "peer0", amount: Decimal(5))],
            memo: "",
            requesterAddress: "utest1abc",
            isGroup: false,
            rate: nil
        )

        let parsed = try? #require(payloads.first).map(ChatPaymentRequest.parse)

        #expect(parsed?.splitCount == 1)
        #expect(parsed?.isSplit == false)
        // An empty memo is omitted rather than sent blank.
        #expect(parsed?.memo == nil)
    }

    /// The embedded fiat amount is scaled to 2 decimals HALF_UP, matching Android's
    /// `setScale(FIAT_SCALE, RoundingMode.HALF_UP)`.
    @Test func embeddedFiatIsScaledToTwoDecimals() {
        let payloads = ChatRoom.splitPayloads(
            shares: [.init(publicKey: "key0", displayName: "peer0", amount: Decimal(1))],
            memo: "",
            requesterAddress: "utest1abc",
            isGroup: false,
            rate: rate(33.333)
        )

        let parsed = ChatPaymentRequest.parse(payloads[0])

        #expect(parsed.fiatAmount == Decimal(string: "33.33"))
        #expect(parsed.fiatCurrency == "USD")
    }

    // MARK: - Reducer

    @MainActor @Test func openingTheSheetBuildsParticipantsExcludingOurself() async {
        var state = ChatRoom.State(conversationId: "conversation")
        state.conversation = ZMConversation(
            id: "conversation",
            type: .group,
            participantIds: ["mykey", "key0", "key1"],
            displayName: "Group"
        )
        state.messagingState = ZappMessagingState(identity: ZMIdentity(publicKey: "mykey", displayName: "me"))

        let store = TestStore(initialState: state) { ChatRoom() }
        store.exhaustivity = .off

        await store.send(.splitBillTapped) {
            $0.showsAttachmentSheet = false
        }

        let split = try? #require(store.state.splitBill)

        #expect(split?.isGroup == true)
        #expect(split?.participants.map(\.publicKey) == ["key0", "key1"])
    }

    /// With no loaded conversation there is no participant list to split between, so the room
    /// reports it rather than opening an empty sheet — Android's toast branch.
    @MainActor @Test func openingTheSheetWithoutAConversationReportsInstead() async {
        let store = TestStore(initialState: ChatRoom.State(conversationId: "conversation")) { ChatRoom() }
        store.exhaustivity = .off

        await store.send(.splitBillTapped)

        #expect(store.state.splitBill == nil)
        #expect(store.state.sendDidFail)
    }

    /// The end-to-end reducer path: sending posts one payment-request message per share, each
    /// through the `application/payment-request` client closure.
    @MainActor @Test func sendingPostsOnePaymentRequestPerShare() async throws {
        var state = ChatRoom.State(conversationId: "conversation")
        state.$zashiWalletAccount.withLock { $0 = try? zashiAccount() }
        state.$currencyConversion.withLock { $0 = nil }
        state.splitBill = ChatRoom.SplitBillState(
            isGroup: true,
            participants: participants(2),
            totalText: "9"
        )

        let sent = LockIsolated<[String]>([])

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendPaymentRequest = { conversationId, payload in
                sent.withValue { $0.append(payload) }

                return ZMMessage(
                    id: UUID().uuidString,
                    conversationId: conversationId,
                    senderId: "me",
                    content: payload,
                    contentType: ChatContentType.paymentRequest,
                    isFromMe: true
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.splitSendTapped) {
            $0.splitBill = nil
        }
        await store.receive(\.messageReceived)
        await store.receive(\.messageReceived)

        let payloads = sent.value

        #expect(payloads.count == 2)

        let parsed = payloads.map(ChatPaymentRequest.parse)

        #expect(parsed.allSatisfy { $0.splitCount == 3 })
        #expect(parsed.allSatisfy { $0.amount == Decimal(3) })
        #expect(parsed.compactMap(\.debtorId).sorted() == ["key0", "key1"])
    }

    /// An out-of-range share kills the WHOLE batch rather than sending a partial split the group
    /// would have to reconcile by hand.
    @MainActor @Test func anOutOfRangeShareCancelsTheEntireSplit() async throws {
        var state = ChatRoom.State(conversationId: "conversation")
        state.$zashiWalletAccount.withLock { $0 = try? zashiAccount() }
        state.splitBill = ChatRoom.SplitBillState(
            isGroup: true,
            participants: participants(2),
            totalText: "100000000",
            shareOverrides: ["key0": "99999999"]
        )

        let sent = LockIsolated(0)

        let store = TestStore(initialState: state) {
            ChatRoom()
        } withDependencies: {
            $0.zappMessaging.sendPaymentRequest = { _, _ in
                sent.withValue { $0 += 1 }
                return ZMMessage(id: "x", conversationId: "c", senderId: "me", content: "", isFromMe: true)
            }
        }
        store.exhaustivity = .off

        await store.send(.splitSendTapped) {
            $0.splitBill = nil
        }

        #expect(sent.value == 0)
    }

    /// Toggling the unit converts the total in place and drops the per-share overrides, which
    /// were typed in the old unit.
    @MainActor @Test func togglingCurrencyConvertsTheTotalAndClearsOverrides() async {
        var state = ChatRoom.State(conversationId: "conversation")
        state.$currencyConversion.withLock { $0 = CurrencyConversion(.usd, ratio: 50, timestamp: 0) }
        state.splitBill = ChatRoom.SplitBillState(
            isGroup: true,
            participants: participants(2),
            totalText: "2",
            shareOverrides: ["key0": "1"],
            isFiat: false
        )

        let store = TestStore(initialState: state) { ChatRoom() }
        store.exhaustivity = .off

        await store.send(.splitCurrencyToggled)

        #expect(store.state.splitBill?.isFiat == true)
        #expect(store.state.splitBill?.totalText == "100.00")
        #expect(store.state.splitBill?.shareOverrides.isEmpty == true)
    }
}
