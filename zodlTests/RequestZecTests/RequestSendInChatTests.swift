//
//  RequestSendInChatTests.swift
//  zodlTests
//
//  Request ZEC "Send in chat" (Android `RequestVM.kt` `sendRequestInChat`) and "Save QR to Photos"
//  (`RequestQrCodeView.kt`): the payment-request body against Android's `buildPaymentRequestJson`
//  output, the picker flow, and the save outcomes.
//

import ComposableArchitecture
import Foundation
import Testing
import UIKit
import ZappMessaging
@testable import zodl_internal
@testable @preconcurrency import ZcashLightClientKit

@Suite(.serialized) struct RequestSendInChatTests {
    private static let address = "utest1requester"
    private static let peerKey = String(repeating: "b", count: PublicKeyRules.hexLength)
    private static let blockedKey = String(repeating: "c", count: PublicKeyRules.hexLength)

    private static func rate(_ pricePerZec: Double) -> ChatFiatRate? {
        ChatFiatRate(CurrencyConversion(.usd, ratio: pricePerZec, timestamp: 0))
    }

    private static func request(
        zec: String,
        memo: String = "",
        typedFiat: String? = nil
    ) -> RequestChatPicker.Request {
        RequestChatPicker.Request(
            requesterAddress: address,
            zecAmount: Decimal(string: zec) ?? 0,
            memo: memo,
            typedFiatAmount: typedFiat.flatMap { Decimal(string: $0) }
        )
    }

    // MARK: - Wire format

    /// Android, for the same inputs: `{"requesterAddress":…,"id":…,"amount":1.5,"token":"ZEC",
    /// "fiatAmount":60,"fiatCurrency":"USD","memo":"Dinner"}` (org.json prints a whole BigDecimal
    /// without a fraction). Key order is Android's insertion order.
    @Test func payloadMatchesAndroidFieldSetWithFiatAndMemo() {
        let payload = RequestChatPicker.payload(
            for: Self.request(zec: "1.5", memo: "Dinner"),
            rate: Self.rate(40),
            id: "req-1"
        )

        #expect(
            payload
                == #"{"requesterAddress":"utest1requester","id":"req-1","amount":1.5,"token":"ZEC","fiatAmount":60,"fiatCurrency":"USD","memo":"Dinner"}"#
        )
    }

    /// No rate: no fiat fields at all. Empty memo: no `memo` key, as `memo?.takeIf { it.isNotEmpty() }`.
    @Test func payloadOmitsFiatWithoutRateAndMemoWhenEmpty() {
        let payload = RequestChatPicker.payload(for: Self.request(zec: "2"), rate: nil, id: "req-2")

        #expect(payload == #"{"requesterAddress":"utest1requester","id":"req-2","amount":2,"token":"ZEC"}"#)
    }

    /// A fiat-typed request sends the typed amount (scale 2, HALF_UP), not the ZEC converted back.
    @Test func payloadUsesTheTypedFiatAmountWhenTheUserTypedFiat() throws {
        let payload = try #require(
            RequestChatPicker.payload(
                for: Self.request(zec: "0.24691358", typedFiat: "12.345"),
                rate: Self.rate(50),
                id: "req-3"
            )
        )
        let parsed = ChatPaymentRequest.parse(payload)

        #expect(parsed.fiatAmount == Decimal(string: "12.35"))
        #expect(parsed.fiatCurrency == "USD")
        #expect(parsed.amount == Decimal(string: "0.24691358"))
        #expect(parsed.requesterAddress == Self.address)
        #expect(parsed.memo == nil)
        #expect(parsed.isAmountValid)
    }

    /// Android returns without sending when the amount is not positive.
    @Test func payloadRefusesAZeroAmount() {
        #expect(RequestChatPicker.payload(for: Self.request(zec: "0"), rate: Self.rate(40), id: "x") == nil)
    }

    // MARK: - Picker

    @MainActor @Test func pickerListsSavedUnblockedContactsOnly() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            let state = RequestChatPicker.State(request: Self.request(zec: "1"))
            state.$chatContacts.withLock { $0 = Self.contacts() }

            #expect(state.contacts.map(\.name) == ["Alice"])

            let empty = RequestChatPicker.State(request: Self.request(zec: "1"))
            empty.$chatContacts.withLock { $0 = .empty }
            #expect(empty.contacts.isEmpty)
        }
    }

    @MainActor @Test func sendInChatOpensThePickerWithTheQRRequest() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            let store = TestStore(initialState: Self.summaryState()) { RequestZec() }
            store.exhaustivity = .off

            await store.send(.sendInChatTapped)

            let picker = store.state.chatPicker
            #expect(picker?.request.requesterAddress == Self.address)
            #expect(picker?.request.zecAmount == Decimal(string: "1.25"))
            #expect(picker?.request.memo == "Rent")
            #expect(picker?.request.typedFiatAmount == Decimal(25))
            #expect(picker?.isSending == false)
        }
    }

    @MainActor @Test func selectingAContactSendsTheRequestAndOpensTheConversation() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            let created = LockIsolated<[String]>([])
            let sent = LockIsolated<[(String, String)]>([])
            let conversation = ZMConversation(
                id: "dm-1",
                type: .direct,
                participantIds: [Self.peerKey],
                displayName: "Alice"
            )

            var state = Self.summaryState()
            state.chatPicker = RequestChatPicker.State(request: Self.request(zec: "1.25", memo: "Rent"))
            state.chatPicker?.$chatContacts.withLock { $0 = Self.contacts() }
            state.chatPicker?.$currencyConversion.withLock { $0 = nil }

            let store = TestStore(initialState: state) {
                RequestZec()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.zappMessaging.createDirectConversation = { key, _ in
                    created.withValue { $0.append(key) }
                    return conversation
                }
                $0.zappMessaging.sendPaymentRequest = { conversationId, payload in
                    sent.withValue { $0.append((conversationId, payload)) }
                    return ZMMessage(id: "m", conversationId: conversationId, senderId: "me", content: payload, isFromMe: true)
                }
            }
            store.exhaustivity = .off

            let alice = Self.contacts().contacts[0]

            await store.send(.chatPicker(.contactTapped(alice))) {
                $0.chatPicker?.isSending = true
            }
            await store.receive(\.chatPicker.delegate.sent) {
                $0.chatPicker = nil
            }
            await store.receive(\.sentInChat, conversation)

            #expect(created.value == [Self.peerKey])
            #expect(sent.value.count == 1)
            #expect(sent.value.first?.0 == "dm-1")
            #expect(
                sent.value.first?.1
                    == #"{"requesterAddress":"utest1requester","id":"00000000-0000-0000-0000-000000000000","amount":1.25,"token":"ZEC","memo":"Rent"}"#
            )
        }
    }

    @MainActor @Test func aFailedSendKeepsThePickerOpenAndSaysSo() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            var state = Self.summaryState()
            state.chatPicker = RequestChatPicker.State(request: Self.request(zec: "1"))

            let store = TestStore(initialState: state) {
                RequestZec()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.zappMessaging.sendPaymentRequest = { _, _ in throw ZMError.notInitialized }
            }
            store.exhaustivity = .off

            await store.send(.chatPicker(.contactTapped(Self.contacts().contacts[0])))
            await store.receive(\.chatPicker.sendFailed)

            #expect(store.state.chatPicker?.isSending == false)
            #expect(store.state.chatPicker?.didFail == true)
        }
    }

    /// Android's `dismissChatPicker`: ignored while sending, closes otherwise.
    @MainActor @Test func dismissIsIgnoredWhileSending() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            var state = Self.summaryState()
            state.chatPicker = RequestChatPicker.State(request: Self.request(zec: "1"))
            state.chatPicker?.isSending = true

            let store = TestStore(initialState: state) { RequestZec() }

            // Exhaustive store: no state change is asserted, so the picker must still be there.
            await store.send(.chatPickerDismissRequested)
            #expect(store.state.chatPicker?.isSending == true)
        }
    }

    @MainActor @Test func dismissClosesAnIdlePicker() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            var state = Self.summaryState()
            state.chatPicker = RequestChatPicker.State(request: Self.request(zec: "1"))

            let store = TestStore(initialState: state) { RequestZec() }

            await store.send(.chatPickerDismissRequested) {
                $0.chatPicker = nil
            }
        }
    }

    // MARK: - Save QR to Photos

    @MainActor @Test func savingTheQRWritesAPNGAndConfirms() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            let saved = LockIsolated<[Data]>([])
            let store = TestStore(initialState: Self.summaryState()) {
                RequestZec()
            } withDependencies: {
                $0.continuousClock = ImmediateClock()
                $0.photoLibrary.saveImageData = { data in saved.withValue { $0.append(data) } }
            }

            await store.send(.saveQRTapped) {
                $0.qrSaveOutcome = .saving
            }
            await store.receive(\.qrSaveFinished, .saved) {
                $0.qrSaveOutcome = .saved
            }
            await store.receive(\.qrSaveNoticeExpired) {
                $0.qrSaveOutcome = nil
            }

            // PNG signature: the image Photos receives is an encoded PNG, not raw pixels.
            #expect(saved.value.count == 1)
            #expect(saved.value.first?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        }
    }

    /// A refused permission stays on screen (with the Settings link) rather than timing out.
    /// A saved QR stands on its own, so it gets a white quiet zone the in-app card does not need.
    @Test func theSavedQRHasAWhiteQuietZone() throws {
        let code = try #require(QRCodeGenerator.generateCode(from: "zcash:u1test?amount=1.5", maxPrivacy: false, vendor: .zashi, color: .black))
        let padded = try #require(RequestZec.withQuietZone(code).cgImage)
        let inset = (padded.width - code.width) / 2

        #expect(padded.width > code.width)
        #expect(Double(inset) >= Double(code.width) * 0.07)

        let rgba = try #require(padded.dataProvider?.data as Data?)
        let bytesPerPixel = padded.bitsPerPixel / 8
        let cornerAndEdge = [0, (inset - 1) * padded.bytesPerRow + (inset - 1) * bytesPerPixel]
        for offset in cornerAndEdge {
            #expect(rgba[offset] > 240 && rgba[offset + 1] > 240 && rgba[offset + 2] > 240)
        }
    }

    @MainActor @Test func aRefusedPermissionStaysUntilTheNextTap() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            let store = TestStore(initialState: Self.summaryState()) {
                RequestZec()
            } withDependencies: {
                $0.continuousClock = ImmediateClock()
                $0.photoLibrary.saveImageData = { _ in throw PhotoLibraryError.notAuthorized }
            }

            await store.send(.saveQRTapped) {
                $0.qrSaveOutcome = .saving
            }
            await store.receive(\.qrSaveFinished, .notAuthorized) {
                $0.qrSaveOutcome = .notAuthorized
            }
        }
    }

    @MainActor @Test func aFailedWriteReportsFailureThenClears() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            let store = TestStore(initialState: Self.summaryState()) {
                RequestZec()
            } withDependencies: {
                $0.continuousClock = ImmediateClock()
                $0.photoLibrary.saveImageData = { _ in throw PhotoLibraryError.saveFailed }
            }

            await store.send(.saveQRTapped) {
                $0.qrSaveOutcome = .saving
            }
            await store.receive(\.qrSaveFinished, .failed) {
                $0.qrSaveOutcome = .failed
            }
            await store.receive(\.qrSaveNoticeExpired) {
                $0.qrSaveOutcome = nil
            }
        }
    }

    @MainActor @Test func saveDoesNothingBeforeTheQRExists() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            var state = Self.summaryState()
            state.encryptedOutput = nil

            let store = TestStore(initialState: state) { RequestZec() }

            await store.send(.saveQRTapped)
            #expect(store.state.qrSaveOutcome == nil)
        }
    }

    // MARK: - Routing and flow wiring

    /// Android's `navigationRouter.forward(ChatRoomArgs(conversationId))`: the user lands in the
    /// conversation the request went to, and the Request cover is closed.
    @Test func sentInChatOpensTheConversationAndClosesTheRequestCover() {
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            let conversation = ZMConversation(id: "dm-9", type: .direct, participantIds: [Self.peerKey], displayName: "Alice")
            var state = Root.State.initial
            state.path = .receive
            state.receiveState.requestFlow = ReceiveRequestFlow.State(address: Self.address.redacted, maxPrivacy: true)

            _ = Root().coordinatorReduce()._reduce(
                into: &state,
                action: .receive(.requestFlow(.presented(.path(.element(
                    id: 0,
                    action: .requestZecSummary(.sentInChat(conversation))
                )))))
            )

            #expect(state.path == .chatRoom)
            #expect(state.chatRoomState.conversationId == "dm-9")
            #expect(state.chatRoomState.conversation == conversation)
            #expect(state.receiveState.requestFlow == nil)
        }
    }

    /// A fiat-typed amount reaches the QR page so "Send in chat" can put it on the wire.
    @MainActor @Test func theTypedFiatAmountIsCarriedToTheRequest() async {
        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: { @MainActor in
            var state = ReceiveRequestFlow.State(address: Self.address.redacted, maxPrivacy: true)
            state.zecKeyboardState.isInputInZec = false
            state.zecKeyboardState.currencyValue = 25

            let store = TestStore(initialState: state) { ReceiveRequestFlow() }
            store.exhaustivity = .off

            await store.send(.zecKeyboard(.nextTapped))
            #expect(store.state.requestZecState.requestedFiat == Decimal(25))

            var zecState = ReceiveRequestFlow.State(address: Self.address.redacted, maxPrivacy: true)
            zecState.zecKeyboardState.isInputInZec = true
            zecState.zecKeyboardState.currencyValue = 25

            let zecStore = TestStore(initialState: zecState) { ReceiveRequestFlow() }
            zecStore.exhaustivity = .off

            await zecStore.send(.zecKeyboard(.nextTapped))
            #expect(zecStore.state.requestZecState.requestedFiat == nil)
        }
    }

    // MARK: - Fixtures

    private static func summaryState() -> RequestZec.State {
        var state = RequestZec.State()
        state.address = address.redacted
        state.requestedZec = Zatoshi(125_000_000)
        state.requestedFiat = Decimal(25)
        state.memoState.text = "Rent"
        state.maxPrivacy = true
        state.encryptedOutput = "zcash:\(address)?amount=1.25"
        return state
    }

    private static func contacts() -> ChatContacts {
        ChatContacts(
            lastUpdated: .distantPast,
            version: ChatContacts.Constants.version,
            contacts: [
                ChatContact(publicKey: peerKey, name: "Alice"),
                ChatContact(publicKey: blockedKey, name: "Blocked", isBlocked: true),
                ChatContact(
                    publicKey: String(repeating: "d", count: PublicKeyRules.hexLength),
                    name: "Block-only",
                    isBlocked: true,
                    isSaved: false
                )
            ]
        )
    }
}
