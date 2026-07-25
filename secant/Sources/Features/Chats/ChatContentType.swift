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

    /// Body is the sender's unified address, verbatim. Android's `WalletAddressBubble`
    /// renders it; iOS renders the fallback bubble until Phase 6 lands.
    static let walletAddress = "application/wallet-address"

    /// Phase 6 consumes these; listed so the wire vocabulary lives in one place.
    static let paymentRequest = "application/payment-request"
    static let zecTransaction = "application/zec-transaction"
    static let location = "application/location"
}
