//
//  ChatMessagePayloads.swift
//  Zapp
//
//  Wire payloads for the structured chat message types. EVERYTHING in this file is
//  on-the-wire format, mirrored field-for-field from Android:
//
//  * discrimination      — `ChatMessageBubble.kt: resolveContentType(...)`
//  * payment request     — `model/MimeTypes.kt: buildPaymentRequestJson(...)`
//                          read back by `bubbles/PaymentRequestBubble.kt: parsePaymentRequest(...)`
//  * transaction receipt — `common/usecase/SubmitProposalUseCase.kt: notifyChatPeer(...)`
//                          read back by `bubbles/TransactionBubble.kt`
//  * settlement link     — `ChatMessageBubble.kt: paymentRequestId(...)` / `paidRequestIds(...)`
//
//  Android's own comment on `buildPaymentRequestJson` states the field set is wire format and
//  that "iOS parses the same payloads" — this file is that parser. Additive changes only, and
//  never a field Android does not write.
//

import Foundation
import ZappMessaging

// MARK: - Discrimination

/// What a message renders as. The cases are listed in Android's evaluation order
/// (`ChatMessageBubble.kt: MessageContent`) and `ChatMessageKind.of(_:)` preserves it — the
/// order is load-bearing, because an image message carries BOTH an `image/*` type and a
/// `mediaId`, and a file is only "a file" once the media prefixes have missed.
enum ChatMessageKind: Equatable {
    case paymentRequest
    case walletAddress
    case zecTransaction
    case image
    case video
    case file
    /// Plain text, and the deliberate fallback for anything unrecognised — including
    /// `application/location`, which Decision 3 puts out of scope.
    case text

    static func of(_ message: ZMMessage) -> ChatMessageKind {
        let contentType = ChatMessageKind.resolvedContentType(of: message)

        switch contentType {
        case ChatContentType.paymentRequest: return .paymentRequest
        case ChatContentType.walletAddress: return .walletAddress
        case ChatContentType.zecTransaction: return .zecTransaction
        default: break
        }

        if contentType.hasPrefix(ChatContentType.imagePrefix) { return .image }
        if contentType.hasPrefix(ChatContentType.videoPrefix) { return .video }
        if message.mediaId != nil { return .file }

        return .text
    }

    /// Android's `resolveContentType`: the DECLARED content type wins, unless it is missing or
    /// the `text/plain` default — only then may a JSON body name its own `contentType`. That
    /// second chance exists because a peer can post a structured body through the plain
    /// `message.send` path, and dropping it would render a payment request as raw JSON.
    static func resolvedContentType(of message: ZMMessage) -> String {
        let declared = message.contentType

        if !declared.isEmpty, declared != ChatContentType.text {
            return declared
        }

        return ChatMessageJSON.string(message.content, "contentType") ?? ChatContentType.text
    }
}

// MARK: - JSON helpers

/// A tolerant reader over a message body that may or may not be JSON. Android leans on
/// `org.json`'s `optString`/`optDouble`, which never throw and treat an absent key as empty —
/// these helpers reproduce that behaviour so a malformed peer payload degrades instead of
/// failing the whole row.
enum ChatMessageJSON {
    static func object(_ content: String) -> [String: Any]? {
        guard
            let data = content.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    static func string(_ content: String, _ key: String) -> String? {
        string(in: object(content), key)
    }

    /// Empty is absent, exactly like `optString(key, "").takeIf { it.isNotEmpty() }`.
    static func string(in object: [String: Any]?, _ key: String) -> String? {
        guard let value = object?[key] as? String, !value.isEmpty else { return nil }

        return value
    }

    /// `optDouble` coerces a numeric string, so a peer that quoted its amount still parses.
    static func decimal(in object: [String: Any]?, _ key: String) -> Decimal? {
        switch object?[key] {
        case let number as NSNumber: return number.decimalValue
        case let text as String: return Decimal(string: text)
        default: return nil
        }
    }

    static func int(in object: [String: Any]?, _ key: String) -> Int? {
        switch object?[key] {
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text)
        default: return nil
        }
    }

    /// Encodes `fields` IN ORDER, which a `Dictionary` cannot do.
    ///
    /// Two reasons the order is not cosmetic. Both platforms read these bodies by key lookup, so
    /// order cannot change what parses — but the chat LIST preview on both platforms sniffs a
    /// cold-loaded body by looking for a marker inside a ~100-character truncation
    /// (`ChatPreviewSentinel.jsonLabel`, Android's `jsonPreview`). Sorted keys would push
    /// `requesterAddress` past that window on a split payload, because a 64-character `debtorId`
    /// sorts ahead of it. Emitting Android's exact insertion order keeps both previews working
    /// and keeps a byte-level diff against an Android-authored message readable.
    ///
    /// Amounts go through `NSDecimalNumber` so they reach the wire with the digits they were
    /// typed with: a `Double` would emit `0.30000000000000004` where Android's `BigDecimal`
    /// emits `0.3`.
    static func encode(_ fields: [(String, Any)]) -> String? {
        let encoded = fields.compactMap { key, value -> String? in
            let boxed = value is Decimal ? NSDecimalNumber(decimal: value as? Decimal ?? .zero) : value

            guard
                let keyJSON = literal(key),
                let valueJSON = literal(boxed)
            else {
                return nil
            }

            return "\(keyJSON):\(valueJSON)"
        }

        guard encoded.count == fields.count else { return nil }

        return "{\(encoded.joined(separator: ","))}"
    }

    /// One JSON value, escaped and formatted by `JSONSerialization` itself — hand-rolling string
    /// escaping is exactly the kind of thing that works until a memo contains a quote.
    private static func literal(_ value: Any) -> String? {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let text = String(data: data, encoding: .utf8),
            text.hasPrefix("["),
            text.hasSuffix("]")
        else {
            return nil
        }

        return String(text.dropFirst().dropLast())
    }
}

// MARK: - Payment request

/// The `application/payment-request` body. Mirrors `buildPaymentRequestJson` exactly:
/// `requesterAddress`, `id`, `amount`, `token`, and the optional `debtorId`, `debtorName`,
/// `splitCount`, `fiatAmount`, `fiatCurrency`, `memo`.
struct ChatPaymentRequest: Equatable {
    /// `MAX_PAYMENT_REQUEST_ZEC` — the whole supply. A request above it is not payable.
    static let maxZec = Decimal(21_000_000)

    /// Android's `paymentRequestToken`: absent means ZEC.
    static let defaultToken = "ZEC"

    var id: String?
    var requesterAddress: String?
    var amount: Decimal
    var token: String
    var memo: String?
    var debtorId: String?
    var debtorName: String?
    var splitCount: Int
    var fiatAmount: Decimal?
    var fiatCurrency: String?

    var isAmountValid: Bool {
        amount > 0 && amount <= ChatPaymentRequest.maxZec
    }

    /// Android renders the split chip only above one, and `sendSplitRequests` writes `1` for a
    /// direct chat.
    var isSplit: Bool { splitCount > 1 }

    static func parse(_ content: String) -> ChatPaymentRequest {
        let object = ChatMessageJSON.object(content)

        return ChatPaymentRequest(
            id: ChatMessageJSON.string(in: object, "id"),
            requesterAddress: ChatMessageJSON.string(in: object, "requesterAddress"),
            amount: ChatMessageJSON.decimal(in: object, "amount") ?? 0,
            token: ChatMessageJSON.string(in: object, "token") ?? ChatPaymentRequest.defaultToken,
            memo: ChatMessageJSON.string(in: object, "memo"),
            debtorId: ChatMessageJSON.string(in: object, "debtorId"),
            debtorName: ChatMessageJSON.string(in: object, "debtorName"),
            splitCount: ChatMessageJSON.int(in: object, "splitCount") ?? 0,
            fiatAmount: ChatMessageJSON.decimal(in: object, "fiatAmount"),
            fiatCurrency: ChatMessageJSON.string(in: object, "fiatCurrency")
        )
    }

    /// The one builder, matching `buildPaymentRequestJson`'s key set and its "omit when absent"
    /// rule for every optional field.
    static func json(
        id: String,
        amount: Decimal,
        requesterAddress: String,
        memo: String?,
        debtorId: String? = nil,
        debtorName: String? = nil,
        splitCount: Int? = nil,
        fiatAmount: Decimal? = nil,
        fiatCurrency: String? = nil
    ) -> String? {
        var fields: [(String, Any)] = [
            ("requesterAddress", requesterAddress),
            ("id", id),
            ("amount", amount),
            ("token", ChatPaymentRequest.defaultToken)
        ]

        if let debtorId { fields.append(("debtorId", debtorId)) }
        if let debtorName { fields.append(("debtorName", debtorName)) }
        if let splitCount { fields.append(("splitCount", splitCount)) }

        if let fiatAmount, let fiatCurrency {
            fields.append(("fiatAmount", fiatAmount))
            fields.append(("fiatCurrency", fiatCurrency))
        }

        if let memo, !memo.isEmpty { fields.append(("memo", memo)) }

        return ChatMessageJSON.encode(fields)
    }
}

// MARK: - Transaction receipt

/// The `application/zec-transaction` body written by Android's `notifyChatPeer`:
/// `amount`, `token`, and the optional `requestId` / `txId`.
///
/// `signature` is read by Android's `TransactionBubble` but written by no current sender; it is
/// parsed here for the same reason — so a peer that does send one still renders.
struct ChatTransactionReceipt: Equatable {
    var amount: Decimal
    var token: String
    var requestId: String?
    var txId: String?
    var signature: String?

    static func parse(_ content: String) -> ChatTransactionReceipt {
        let object = ChatMessageJSON.object(content)

        return ChatTransactionReceipt(
            amount: ChatMessageJSON.decimal(in: object, "amount") ?? 0,
            token: ChatMessageJSON.string(in: object, "token") ?? ChatPaymentRequest.defaultToken,
            requestId: ChatMessageJSON.string(in: object, "requestId"),
            txId: ChatMessageJSON.string(in: object, "txId"),
            signature: ChatMessageJSON.string(in: object, "signature")
        )
    }

    static func json(amount: Decimal, requestId: String?, txId: String?) -> String? {
        var fields: [(String, Any)] = [
            ("amount", amount),
            ("token", ChatPaymentRequest.defaultToken)
        ]

        if let requestId { fields.append(("requestId", requestId)) }
        if let txId { fields.append(("txId", txId)) }

        return ChatMessageJSON.encode(fields)
    }
}

// MARK: - Settlement

enum ChatPaymentSettlement {
    /// The request id a payment-request message carries (`paymentRequestId`).
    static func requestId(of message: ZMMessage) -> String? {
        guard ChatMessageKind.of(message) == .paymentRequest else { return nil }

        return ChatMessageJSON.string(message.content, "id")
    }

    /// Every request id settled by a `zec-transaction` receipt in `messages` (`paidRequestIds`).
    /// This is the whole cross-platform settlement contract: iOS pays, posts a receipt carrying
    /// the request's `id` as `requestId`, and the requester's bubble — on either platform —
    /// flips to Paid.
    static func paidRequestIds(in messages: [ZMMessage]) -> Set<String> {
        Set(
            messages
                .filter { ChatMessageKind.of($0) == .zecTransaction }
                .compactMap { ChatMessageJSON.string($0.content, "requestId") }
        )
    }
}

// MARK: - Fiat rate

/// The chat-side view of the wallet's exchange rate, mirroring Android's `ZecFiatRate`
/// (`pricePerZec` + currency, `zecToFiat` multiplies, `fiatToZec` divides) so the payment-request
/// bubble and the split sheet convert exactly the way their Android counterparts do.
///
/// A non-positive price is no rate at all — the same `takeIf { it > 0.0 }` guard Android applies
/// before it will construct one.
struct ChatFiatRate: Equatable {
    let pricePerZec: Decimal
    let currency: CurrencyISO4217

    var symbol: String { currency.symbol }

    init?(_ conversion: CurrencyConversion?) {
        guard let conversion, conversion.ratio > 0 else { return nil }

        self.pricePerZec = Decimal(conversion.ratio)
        self.currency = conversion.iso4217
    }

    func zecToFiat(_ zec: Decimal) -> Decimal {
        zec * pricePerZec
    }

    func fiatToZec(_ fiat: Decimal) -> Decimal {
        fiat / pricePerZec
    }
}

// MARK: - Formatting

enum ChatAmountFormat {
    /// Android's `formatZecAmount`: `BigDecimal.stripTrailingZeros().toPlainString()` — the
    /// shortest exact rendering, never scientific notation, never a locale separator.
    static let zecFractionDigits = 8
    static let fiatFractionDigits = 2

    private static func formatter(maximumFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp

        return formatter
    }

    static func zec(_ amount: Decimal) -> String {
        formatter(maximumFractionDigits: zecFractionDigits)
            .string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }

    static func fiat(_ amount: Decimal) -> String {
        let formatter = formatter(maximumFractionDigits: fiatFractionDigits)
        formatter.minimumFractionDigits = fiatFractionDigits

        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }

    /// Rounds to the fiat scale the way Android's `setScale(FIAT_SCALE, HALF_UP)` does before it
    /// puts `fiatAmount` on the wire.
    static func roundedFiat(_ amount: Decimal) -> Decimal {
        var input = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, fiatFractionDigits, .plain)

        return rounded
    }

    /// Rounds to ZEC's 8 decimals, so an equal-split remainder cannot carry digits the protocol
    /// cannot express.
    static func roundedZec(_ amount: Decimal) -> Decimal {
        var input = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, zecFractionDigits, .plain)

        return rounded
    }
}
