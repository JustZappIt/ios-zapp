//
//  ChatContentType.swift
//  Zapp
//
//  MIME strings used as protocol markers on chat messages. These values are ON THE WIRE:
//  they are the exact literals in Android's `screen/chat/model/MimeTypes.kt`, and a peer
//  discriminates a message purely by matching them. Changing one breaks compatibility with
//  every other client, so this is a mirror — never a place to invent a new type.
//

import Foundation

enum ChatContentType {
    static let text = "text/plain"
    static let imagePrefix = "image/"
    static let videoPrefix = "video/"
    static let imageJPEG = "image/jpeg"
    static let gif = "image/gif"

    /// Body is the sender's unified address, verbatim — NOT JSON. Rendered by
    /// `ChatWalletAddressBubble`, Android's `WalletAddressBubble`.
    static let walletAddress = "application/wallet-address"

    /// Body is a JSON payload. The schemas — and the evidence they match Android's — live in
    /// `ChatMessagePayloads.swift`; build them only through `ChatPaymentRequest.json(...)` /
    /// `ChatTransactionReceipt.json(...)`, never by hand at a call site.
    static let paymentRequest = "application/payment-request"
    static let zecTransaction = "application/zec-transaction"

    /// Out of scope per Decision 3: incoming location messages keep the plain-text fallback
    /// bubble. Listed so the wire vocabulary lives in one place and so `ChatMessageKind` can
    /// name what it is deliberately not rendering.
    static let location = "application/location"
}
