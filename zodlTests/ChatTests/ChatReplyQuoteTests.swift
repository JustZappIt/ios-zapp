//
//  ChatReplyQuoteTests.swift
//  zodlTests
//
//  The reply summary is wire format: Android's `ChatReplyQuote.kt` derives the same
//  `replyToContent` and `replyToContentType` from the same message, and both clients read them
//  back through the same kind table. A drift here shows up as a quote that names a photo as text
//  on the peer, which nothing else would report.
//

import Foundation
import Testing
import ZappMessaging
@testable import zodl_internal

@Suite struct ChatReplyQuoteTests {
    private func message(
        content: String,
        contentType: String = ChatContentType.text,
        mediaId: String? = nil
    ) -> ZMMessage {
        ZMMessage(
            id: "m",
            conversationId: "c",
            senderId: "peer",
            content: content,
            contentType: contentType,
            timestamp: Date(timeIntervalSince1970: 100),
            isFromMe: false,
            mediaId: mediaId
        )
    }

    // MARK: - What ships on the wire (`replyWireContent` / `replyWireContentType`)

    @Test func aTextQuoteKeepsItsTextAndStaysAText() {
        let original = message(content: "see you at 8")

        #expect(ChatReplyPreview.wireContent(for: original) == "see you at 8")
        #expect(ChatReplyPreview.wireContentType(for: original) == ChatContentType.text)
        #expect(ChatReplyQuoteKind(contentType: ChatReplyPreview.wireContentType(for: original)) == .text)
    }

    @Test func theWireSummaryIsCappedLikeTheSDKPreview() {
        let long = String(repeating: "x", count: ChatReplyPreview.maxLength + 40)

        #expect(ChatReplyPreview.wireContent(for: message(content: long)).count == ChatReplyPreview.maxLength)
    }

    @Test func aPhotoQuoteCarriesItsCaptionAndItsImageType() {
        let captioned = message(content: "beach", contentType: ChatContentType.imageJPEG, mediaId: "ab")
        let bare = message(content: "", contentType: ChatContentType.imageJPEG, mediaId: "ab")

        #expect(ChatReplyPreview.wireContent(for: captioned) == "beach")
        #expect(ChatReplyPreview.wireContent(for: bare) == "")
        #expect(ChatReplyPreview.wireContentType(for: bare) == ChatContentType.imageJPEG)
    }

    @Test func aFileQuoteKeepsItsFilenameAndIsNeverReadAsText() {
        let pdf = message(content: "report.pdf", contentType: "application/pdf", mediaId: "ab")
        let txt = message(content: "notes.txt", contentType: ChatContentType.text, mediaId: "ab")

        #expect(ChatReplyPreview.wireContent(for: pdf) == "report.pdf")
        #expect(ChatReplyQuoteKind(contentType: ChatReplyPreview.wireContentType(for: pdf)) == .file)
        #expect(ChatReplyPreview.wireContentType(for: txt) == "application/octet-stream")
        #expect(ChatReplyQuoteKind(contentType: ChatReplyPreview.wireContentType(for: txt)) == .file)
    }

    @Test func aWalletAddressQuoteKeepsTheAddress() {
        let original = message(content: "u1abcdef", contentType: ChatContentType.walletAddress)

        #expect(ChatReplyPreview.wireContent(for: original) == "u1abcdef")
        #expect(ChatReplyQuoteKind(contentType: ChatReplyPreview.wireContentType(for: original)) == .walletAddress)
    }

    /// The JSON body never ships as the quote: an older peer would render it verbatim.
    @Test func aPaymentRequestQuoteBecomesItsAmountAndMemo() throws {
        let half = try #require(Decimal(string: "0.5"))
        let quarter = try #require(Decimal(string: "1.25"))
        let withMemo = try #require(
            ChatPaymentRequest.json(id: "r1", amount: half, requesterAddress: "u1abc", memo: "Dinner")
        )
        let bare = try #require(
            ChatPaymentRequest.json(id: "r2", amount: quarter, requesterAddress: "u1abc", memo: nil)
        )

        #expect(
            ChatReplyPreview.wireContent(for: message(content: withMemo, contentType: ChatContentType.paymentRequest))
                == "0.5 ZEC · Dinner"
        )
        #expect(
            ChatReplyPreview.wireContent(for: message(content: bare, contentType: ChatContentType.paymentRequest))
                == "1.25 ZEC"
        )
        #expect(ChatReplyPreview.wireContentType(for: message(content: bare, contentType: ChatContentType.paymentRequest))
            == ChatContentType.paymentRequest)
    }

    @Test func aTransactionQuoteBecomesItsAmount() throws {
        let receipt = try #require(ChatTransactionReceipt.json(amount: 2, requestId: "r1", txId: "t1"))
        let original = message(content: receipt, contentType: ChatContentType.zecTransaction)

        #expect(ChatReplyPreview.wireContent(for: original) == "2 ZEC")
        #expect(ChatReplyQuoteKind(contentType: ChatReplyPreview.wireContentType(for: original)) == .transaction)
    }

    /// Android's `LocationBubble` prints `%.6f, %.6f`; the quote says the same.
    @Test func aLocationQuoteBecomesItsCoordinates() {
        let body = #"{"latitude":48.858844,"longitude":2.294351,"accuracy":10.0}"#
        let original = message(content: body, contentType: ChatContentType.location)

        #expect(ChatReplyPreview.wireContent(for: original) == "48.858844, 2.294351")
        #expect(ChatReplyQuoteKind(contentType: ChatReplyPreview.wireContentType(for: original)) == .location)
    }

    /// A structured body posted through the plain send path names its own type; the quote's
    /// type follows the same resolution the bubble does.
    @Test func aBodyNamedTypeResolvesLikeTheBubble() throws {
        let wrapped = try #require(
            ChatMessageJSON.encode([("contentType", ChatContentType.zecTransaction), ("amount", 1), ("token", "ZEC")])
        )

        #expect(ChatReplyPreview.wireContentType(for: message(content: wrapped)) == ChatContentType.zecTransaction)
    }

    // MARK: - Reading a quote back (`replyQuoteKind` / `replyQuoteLine`)

    @Test func kindsMapFromTheirWireTypes() {
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.imageJPEG) == .photo)
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.gif) == .gif)
        #expect(ChatReplyQuoteKind(contentType: "video/mp4") == .video)
        #expect(ChatReplyQuoteKind(contentType: "application/pdf") == .file)
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.paymentRequest) == .paymentRequest)
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.zecTransaction) == .transaction)
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.walletAddress) == .walletAddress)
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.location) == .location)
    }

    @Test func aReplyFromAClientWithoutTheFieldReadsAsAText() {
        #expect(ChatReplyQuoteKind(contentType: nil) == .text)
        #expect(ChatReplyQuoteKind(contentType: "") == .text)
        #expect(ChatReplyQuoteKind(contentType: ChatContentType.text) == .text)
    }

    @Test func onlyPicturesShowAThumbnail() {
        #expect(ChatReplyQuoteKind.photo.showsThumbnail)
        #expect(ChatReplyQuoteKind.gif.showsThumbnail)
        #expect(ChatReplyQuoteKind.video.showsThumbnail)
        #expect(!ChatReplyQuoteKind.file.showsThumbnail)
        #expect(!ChatReplyQuoteKind.text.showsThumbnail)
    }

    @Test func theQuoteLineJoinsLabelAndContent() {
        #expect(ChatReplyPreview.line(kind: .text, content: "hello") == "hello")
        #expect(ChatReplyPreview.line(kind: .photo, content: "") == ChatReplyQuoteKind.photo.label)
        #expect(ChatReplyPreview.line(kind: .photo, content: nil) == ChatReplyQuoteKind.photo.label)
        let fileLabel = ChatReplyQuoteKind.file.label ?? ""

        #expect(ChatReplyPreview.line(kind: .file, content: "report.pdf") == "\(fileLabel) · report.pdf")
    }
}
