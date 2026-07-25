//
//  ChatRichBubbleWireTests.swift
//  zodlTests
//
//  Phase 6 — the wire-format half. These are the assertions that matter most in this phase: a
//  payment request or transaction receipt that does not match Android BYTE-FOR-BYTE renders as a
//  raw-JSON text bubble on the peer, and nothing in either app would report it. Every expectation
//  here is pinned to a named Android symbol.
//

import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite struct ChatRichBubbleWireTests {
    private func message(
        content: String,
        contentType: String,
        isFromMe: Bool = false,
        mediaId: String? = nil
    ) -> ZMMessage {
        ZMMessage(
            id: UUID().uuidString,
            conversationId: "conversation",
            senderId: isFromMe ? "me" : "peer",
            content: content,
            contentType: contentType,
            timestamp: Date(timeIntervalSince1970: 100),
            isFromMe: isFromMe,
            mediaId: mediaId
        )
    }

    private func json(_ raw: String) throws -> [String: Any] {
        let data = try #require(raw.data(using: .utf8))

        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Discrimination (`ChatMessageBubble.kt: resolveContentType`)

    @Test func aDeclaredContentTypeWins() {
        let payment = message(content: "{}", contentType: ChatContentType.paymentRequest)

        #expect(ChatMessageKind.of(payment) == .paymentRequest)
        #expect(ChatMessageKind.of(message(content: "", contentType: ChatContentType.walletAddress)) == .walletAddress)
        #expect(ChatMessageKind.of(message(content: "{}", contentType: ChatContentType.zecTransaction)) == .zecTransaction)
    }

    /// Android falls back to a `contentType` named INSIDE the body when the declared type is
    /// absent or the `text/plain` default, so a peer posting a structured payload through the
    /// plain send path still renders as a bubble instead of raw JSON.
    @Test func aTextPlainBodyMayNameItsOwnContentType() throws {
        let body = try #require(
            ChatPaymentRequest.json(id: "r1", amount: 1, requesterAddress: "utest1abc", memo: nil)
        )
        let wrapped = try #require(
            ChatMessageJSON.encode([
                ("contentType", ChatContentType.paymentRequest),
                ("amount", Decimal(1))
            ])
        )
        _ = body

        #expect(ChatMessageKind.of(message(content: wrapped, contentType: ChatContentType.text)) == .paymentRequest)
        #expect(ChatMessageKind.of(message(content: wrapped, contentType: "")) == .paymentRequest)
    }

    /// The order in `MessageContent` is load-bearing: an image carries BOTH an `image/*` type and
    /// a `mediaId`, so a file is only a file once the media prefixes have missed.
    @Test func mediaIsClassifiedBeforeFile() {
        #expect(ChatMessageKind.of(message(content: "", contentType: "image/jpeg", mediaId: "m")) == .image)
        #expect(ChatMessageKind.of(message(content: "", contentType: "video/mp4", mediaId: "m")) == .video)
        #expect(ChatMessageKind.of(message(content: "notes.pdf", contentType: "application/pdf", mediaId: "m")) == .file)
    }

    /// Decision 3 keeps location out of scope, and every other unknown type degrades the same
    /// way — the text bubble, never a crash and never raw JSON pretending to be a bubble.
    @Test func unknownTypesIncludingLocationFallBackToText() {
        #expect(ChatMessageKind.of(message(content: "{}", contentType: ChatContentType.location)) == .text)
        #expect(ChatMessageKind.of(message(content: "hi", contentType: "application/something-new")) == .text)
        #expect(ChatMessageKind.of(message(content: "hi", contentType: ChatContentType.text)) == .text)
    }

    // MARK: - Payment request (`MimeTypes.kt: buildPaymentRequestJson`)

    /// The full field set Android writes, with Android's exact key spellings.
    @Test func aPaymentRequestCarriesAndroidsExactFieldSet() throws {
        let raw = try #require(
            ChatPaymentRequest.json(
                id: "req-1",
                amount: Decimal(string: "0.125") ?? 0,
                requesterAddress: "utest1abc",
                memo: "Dinner",
                debtorId: "peerkey",
                debtorName: "satoshi",
                splitCount: 3,
                fiatAmount: Decimal(string: "12.34") ?? 0,
                fiatCurrency: "USD"
            )
        )
        let object = try json(raw)

        #expect(object["requesterAddress"] as? String == "utest1abc")
        #expect(object["id"] as? String == "req-1")
        #expect(object["token"] as? String == "ZEC")
        #expect(object["memo"] as? String == "Dinner")
        #expect(object["debtorId"] as? String == "peerkey")
        #expect(object["debtorName"] as? String == "satoshi")
        #expect(object["splitCount"] as? Int == 3)
        #expect(object["fiatCurrency"] as? String == "USD")
        #expect((object["amount"] as? NSNumber)?.decimalValue == Decimal(string: "0.125"))
        #expect((object["fiatAmount"] as? NSNumber)?.decimalValue == Decimal(string: "12.34"))
    }

    /// `amount` is a bare JSON NUMBER on Android (`JSONObject.put` with a `BigDecimal`), not a
    /// string — and it must not pick up binary-floating-point noise on the way out.
    @Test func amountsAreExactJsonNumbers() throws {
        let raw = try #require(
            ChatPaymentRequest.json(
                id: "r",
                amount: Decimal(string: "0.1") ?? 0,
                requesterAddress: "a",
                memo: nil
            )
        )

        #expect(raw.contains("\"amount\":0.1"))
        #expect(!raw.contains("\"amount\":\"0.1\""))
        #expect(!raw.contains("0.10000000"))
    }

    /// Android omits every optional it was not given, rather than writing an empty value.
    @Test func absentOptionalsAreOmittedEntirely() throws {
        let raw = try #require(
            ChatPaymentRequest.json(id: "r", amount: 1, requesterAddress: "a", memo: nil)
        )
        let object = try json(raw)

        #expect(object["memo"] == nil)
        #expect(object["debtorId"] == nil)
        #expect(object["debtorName"] == nil)
        #expect(object["splitCount"] == nil)
        #expect(object["fiatAmount"] == nil)
        #expect(object["fiatCurrency"] == nil)
        // An empty memo is the same as no memo — `memo?.takeIf { it.isNotEmpty() }`.
        let empty = try #require(ChatPaymentRequest.json(id: "r", amount: 1, requesterAddress: "a", memo: ""))
        #expect(try json(empty)["memo"] == nil)
    }

    /// Android writes its keys in `buildPaymentRequestJson`'s insertion order, and both platforms'
    /// chat-list previews sniff a cold-loaded body inside a ~100-character truncation. Sorted keys
    /// would push `requesterAddress` out of that window on a split payload (a 64-character
    /// `debtorId` sorts ahead of it) and the row would mislabel.
    @Test func fieldOrderMatchesAndroidsBuilder() throws {
        let raw = try #require(
            ChatPaymentRequest.json(
                id: "req-1",
                amount: 1,
                requesterAddress: "utest1abc",
                memo: "Dinner",
                debtorId: String(repeating: "a", count: 64),
                debtorName: "satoshi",
                splitCount: 3,
                fiatAmount: Decimal(string: "12.34") ?? 0,
                fiatCurrency: "USD"
            )
        )

        #expect(raw.hasPrefix("{\"requesterAddress\":"))

        let order = ["requesterAddress", "id", "amount", "token", "debtorId", "debtorName", "splitCount", "fiatAmount", "fiatCurrency", "memo"]
        let positions = order.compactMap { raw.range(of: "\"\($0)\":")?.lowerBound }

        #expect(positions.count == order.count)
        #expect(positions == positions.sorted())
        // The preview marker still lands inside the truncation window both platforms sniff.
        let marker = try #require(raw.range(of: "\"requesterAddress\"")?.lowerBound)
        #expect(raw.distance(from: raw.startIndex, to: marker) < 100)
    }

    /// A memo is user text, so it has to survive characters that would break hand-rolled escaping.
    @Test func aMemoWithQuotesAndUnicodeSurvivesTheRoundTrip() throws {
        let memo = "He said \"hi\" — 100% \\ done ✅\n"
        let raw = try #require(
            ChatPaymentRequest.json(id: "r", amount: 1, requesterAddress: "a", memo: memo)
        )

        #expect(ChatPaymentRequest.parse(raw).memo == memo)
        #expect(try json(raw)["memo"] as? String == memo)
    }

    @Test func aPaymentRequestRoundTripsThroughItsOwnParser() throws {
        let raw = try #require(
            ChatPaymentRequest.json(
                id: "req-1",
                amount: Decimal(string: "2.5") ?? 0,
                requesterAddress: "utest1abc",
                memo: "Taxi",
                debtorId: "peerkey",
                debtorName: "satoshi",
                splitCount: 4,
                fiatAmount: Decimal(string: "80.00") ?? 0,
                fiatCurrency: "EUR"
            )
        )
        let parsed = ChatPaymentRequest.parse(raw)

        #expect(parsed.id == "req-1")
        #expect(parsed.amount == Decimal(string: "2.5"))
        #expect(parsed.token == "ZEC")
        #expect(parsed.requesterAddress == "utest1abc")
        #expect(parsed.memo == "Taxi")
        #expect(parsed.debtorId == "peerkey")
        #expect(parsed.debtorName == "satoshi")
        #expect(parsed.splitCount == 4)
        #expect(parsed.isSplit)
        #expect(parsed.fiatCurrency == "EUR")
        #expect(parsed.isAmountValid)
    }

    /// `MAX_PAYMENT_REQUEST_ZEC` — above the whole supply, or at/below zero, is not payable.
    @Test func amountValidityMatchesAndroidsBounds() {
        #expect(!ChatPaymentRequest.parse("{\"amount\":0}").isAmountValid)
        #expect(!ChatPaymentRequest.parse("{\"amount\":-1}").isAmountValid)
        #expect(ChatPaymentRequest.parse("{\"amount\":21000000}").isAmountValid)
        #expect(!ChatPaymentRequest.parse("{\"amount\":21000001}").isAmountValid)
    }

    /// A hostile or merely old peer must degrade, not crash: `org.json`'s `optString`/`optDouble`
    /// never throw, and neither does this.
    @Test func aMalformedBodyDegradesInsteadOfFailing() {
        let parsed = ChatPaymentRequest.parse("not json at all")

        #expect(parsed.amount == 0)
        #expect(parsed.id == nil)
        #expect(parsed.token == "ZEC")
        #expect(!parsed.isAmountValid)
        #expect(parsed.splitCount == 0)
    }

    // MARK: - Transaction receipt (`SubmitProposalUseCase.kt: notifyChatPeer`)

    @Test func aReceiptCarriesAndroidsExactFieldSet() throws {
        let raw = try #require(
            ChatTransactionReceipt.json(
                amount: Decimal(string: "0.42") ?? 0,
                requestId: "req-1",
                txId: "abc123"
            )
        )
        let object = try json(raw)

        #expect((object["amount"] as? NSNumber)?.decimalValue == Decimal(string: "0.42"))
        #expect(object["token"] as? String == "ZEC")
        #expect(object["requestId"] as? String == "req-1")
        #expect(object["txId"] as? String == "abc123")
    }

    /// A multi-transaction proposal omits `txId` rather than naming the wrong one, and a send
    /// that settles nothing omits `requestId`. Both are optional on Android too.
    @Test func aReceiptOmitsTheOptionalsItWasNotGiven() throws {
        let raw = try #require(
            ChatTransactionReceipt.json(amount: 1, requestId: nil, txId: nil)
        )
        let object = try json(raw)

        #expect(object["requestId"] == nil)
        #expect(object["txId"] == nil)
        #expect(object["amount"] as? NSNumber == 1)
    }

    // MARK: - Settlement (`ChatMessageBubble.kt: paidRequestIds`)

    /// The whole cross-platform settlement contract in one test: a receipt quoting a request's
    /// `id` as `requestId` is what flips that request's bubble to Paid, on either platform.
    @Test func aReceiptSettlesTheRequestItQuotes() throws {
        let requestBody = try #require(
            ChatPaymentRequest.json(id: "req-1", amount: 1, requesterAddress: "a", memo: nil)
        )
        let receiptBody = try #require(
            ChatTransactionReceipt.json(amount: 1, requestId: "req-1", txId: "tx")
        )
        let unrelatedReceipt = try #require(
            ChatTransactionReceipt.json(amount: 2, requestId: nil, txId: "tx2")
        )

        let request = message(content: requestBody, contentType: ChatContentType.paymentRequest)
        let messages = [
            request,
            message(content: receiptBody, contentType: ChatContentType.zecTransaction, isFromMe: true),
            message(content: unrelatedReceipt, contentType: ChatContentType.zecTransaction, isFromMe: true)
        ]

        let paid = ChatPaymentSettlement.paidRequestIds(in: messages)

        #expect(paid == ["req-1"])
        #expect(ChatPaymentSettlement.requestId(of: request) == "req-1")
        #expect(paid.contains(try #require(ChatPaymentSettlement.requestId(of: request))))
    }

    /// A `requestId` on a message that is not a receipt must not settle anything — the filter is
    /// on content type first.
    @Test func onlyTransactionReceiptsSettleRequests() {
        let decoy = message(content: "{\"requestId\":\"req-1\"}", contentType: ChatContentType.text)

        #expect(ChatPaymentSettlement.paidRequestIds(in: [decoy]).isEmpty)
    }

    // MARK: - Formatting (`BubbleFormatting.kt: formatZecAmount`)

    /// `BigDecimal.stripTrailingZeros().toPlainString()`: shortest exact form, never scientific
    /// notation, never a locale separator.
    @Test func zecFormattingMatchesAndroid() {
        #expect(ChatAmountFormat.zec(Decimal(string: "0.10000000") ?? 0) == "0.1")
        #expect(ChatAmountFormat.zec(Decimal(1)) == "1")
        #expect(ChatAmountFormat.zec(Decimal(21_000_000)) == "21000000")
        #expect(ChatAmountFormat.zec(Decimal(string: "0.00000001") ?? 0) == "0.00000001")
    }
}
