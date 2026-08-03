//
//  KlipyGIFCatalog.swift
//  Zapp
//

import Foundation

/// Request building and response parsing, kept away from the network actor so it is testable
/// without one.
enum KlipyGIFCatalog {
    static let perPage = 30
    static let previewByteLimit = 1024 * 1024
    static let maxBlurPreviewChars = 8 * 1024
    /// A GIF ships verbatim — it cannot be re-encoded without losing its animation — and travels
    /// in 64 KB chunks the receiver has to ask for, so `md` at 3.7 MB is a long wait on the other
    /// end for a picture a chat bubble renders no better than `sm` at 315 KB. Well under
    /// `maxGIFBytes`, which stays the hard ceiling for a pasted or picked GIF.
    static let sendByteBudget = 1_500_000

    /// `md` before `hd`: Klipy ships both at the same pixel size and `hd` differs only in encoding
    /// quality, so `hd` costs roughly double the bytes over a peer-to-peer transfer for a gain no
    /// one sees in a chat bubble.
    static let sendSizes = ["md", "hd", "sm", "xs"]
    /// `sm` is 220px against a ~320px cell; `xs` is 90px and visibly mushy.
    static let previewSizes = ["sm", "xs", "md", "hd"]

    static var apiKey: String? {
        PartnerKeys.klipyKey.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func endpoint(path: String, query: String?, page: Int, customerId: String, apiKey: String?) throws -> URL {
        guard let apiKey, !apiKey.isEmpty else { throw KlipyGIFError.notConfigured }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.klipy.com"
        components.path = "/api/v1/\(apiKey)/gifs/\(path)"
        components.queryItems = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "customer_id", value: customerId),
            URLQueryItem(name: "content_filter", value: "high"),
            // Each item otherwise carries mp4/webm/webp/jpg renditions at four sizes, none of
            // which this picker can use.
            URLQueryItem(name: "format_filter", value: "gif")
        ]

        if let query {
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        }

        guard let url = components.url else { throw KlipyGIFError.badResponse }

        return url
    }

    static func parse(_ data: Data, maxSendBytes: Int = sendByteBudget) throws -> KlipyGIFPage {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let page = root["data"] as? [String: Any],
            let results = page["data"] as? [[String: Any]]
        else {
            throw KlipyGIFError.badResponse
        }

        return KlipyGIFPage(
            gifs: results.compactMap { result($0, maxSendBytes: maxSendBytes) },
            hasMore: results.count >= perPage
        )
    }

    /// An injected advertisement arrives in the same array as a `content` item carrying markup
    /// instead of a `file` — dropping those is what keeps the grid to actual GIFs.
    private static func result(_ raw: [String: Any], maxSendBytes: Int) -> KlipyGIF? {
        guard
            raw["content"] == nil,
            let identifier = identifier(raw),
            let sizes = raw["file"] as? [String: Any],
            let send = rendition(in: sizes, order: sendSizes, maxBytes: maxSendBytes),
            let preview = rendition(in: sizes, order: previewSizes, maxBytes: previewByteLimit)
        else {
            return nil
        }

        return KlipyGIF(
            id: identifier,
            title: (raw["title"] as? String) ?? "",
            previewURL: preview.url,
            sendURL: send.url,
            width: preview.width,
            height: preview.height,
            blurPreview: blurPreview(raw["blur_preview"] as? String)
        )
    }

    /// A `data:` URI rather than a link, so it is decoded rather than fetched. Bounded because it
    /// arrives from a third party and lands in memory for every cell on screen.
    static func blurPreview(_ raw: String?) -> Data? {
        guard
            let raw,
            raw.count <= maxBlurPreviewChars,
            let comma = raw.firstIndex(of: ","),
            raw[raw.startIndex..<comma].hasPrefix("data:image/")
        else {
            return nil
        }

        return Data(base64Encoded: String(raw[raw.index(after: comma)...]), options: [.ignoreUnknownCharacters])
    }

    private static func identifier(_ raw: [String: Any]) -> String? {
        if let slug = raw["slug"] as? String, !slug.isEmpty { return slug }

        return (raw["id"] as? NSNumber).map { $0.stringValue }
    }

    private struct Rendition {
        let url: String
        let width: Int
        let height: Int
    }

    private static func rendition(in sizes: [String: Any], order: [String], maxBytes: Int) -> Rendition? {
        for name in order {
            guard
                let formats = sizes[name] as? [String: Any],
                let gif = formats["gif"] as? [String: Any],
                let rawURL = gif["url"] as? String,
                let url = ChatLinkPreviewParser.safePreviewURL(rawURL)
            else {
                continue
            }

            // Klipy declares the byte count, so an oversized rendition is skipped before it is
            // ever requested rather than downloaded and thrown away.
            if let size = (gif["size"] as? NSNumber)?.intValue, size > maxBytes {
                continue
            }

            return Rendition(
                url: url,
                width: (gif["width"] as? NSNumber)?.intValue ?? 0,
                height: (gif["height"] as? NSNumber)?.intValue ?? 0
            )
        }

        return nil
    }
}
