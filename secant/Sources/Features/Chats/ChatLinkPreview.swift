//
//  ChatLinkPreview.swift
//  Zapp
//

import Foundation

/// Open Graph metadata for a link found in a message. Mirrors Android's `LinkPreviewMetadata`.
struct ChatLinkPreview: Equatable, Sendable {
    let url: String
    let title: String?
    let description: String?
    let siteName: String
    let imageURL: String?
    var imageData: Data?
}

/// URL detection, SSRF screening, and Open Graph parsing.
///
/// The screening is the important part: a preview fetch is an outbound request driven by text
/// a peer controls, so a bare URL must never be able to point the device at the loopback
/// interface or the local network.
enum ChatLinkPreviewParser {
    static let maxTitleLength = 200
    static let maxDescriptionLength = 400
    static let maxSiteNameLength = 100

    private static let webURLPattern = "https?://[^\\s<>]+"
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}")

    /// A detected link and where it sits in the text, so the bubble can make exactly that
    /// span tappable without searching for the substring again.
    struct DetectedWebURL: Equatable {
        let url: String
        let range: Range<String.Index>
    }

    static func firstWebURL(in text: String) -> String? {
        detectWebURLs(in: text).lazy.compactMap { safePreviewURL($0.url) }.first
    }

    static func detectWebURLs(in text: String) -> [DetectedWebURL] {
        guard let regex = try? NSRegularExpression(pattern: webURLPattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }

            // Sentence punctuation sits inside the match but outside the link.
            let trimmed = String(text[matchRange]).trimmingTrailingCharacters(in: trailingPunctuation)

            guard
                let components = URLComponents(string: trimmed),
                let scheme = components.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                let host = components.host,
                !host.isEmpty,
                let end = text.index(matchRange.lowerBound, offsetBy: trimmed.count, limitedBy: matchRange.upperBound)
            else {
                return nil
            }

            return DetectedWebURL(url: trimmed, range: matchRange.lowerBound..<end)
        }
    }

    /// `nil` for anything the app must not fetch: plaintext, credentials in the URL, a
    /// non-standard port, or a host that resolves somewhere private.
    static func safePreviewURL(_ rawURL: String) -> String? {
        guard
            let components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            let rawHost = components.host
        else {
            return nil
        }

        if let port = components.port, port != 443 {
            return nil
        }

        let host = rawHost
            .trimmingTrailingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        guard !host.isEmpty, !isForbiddenHost(host) else { return nil }

        return components.url?.absoluteString
    }

    static func isForbiddenHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return true
        }

        if host == "::1" || host == "0:0:0:0:0:0:0:1" {
            return true
        }

        if host.contains(":"), host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return true
        }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }

        guard octets.count == 4, octets.allSatisfy({ ($0 ?? -1) >= 0 && ($0 ?? 256) <= 255 }) else {
            return false
        }

        guard let first = octets[0], let second = octets[1] else { return false }

        return first == 0
            || first == 10
            || first == 127
            || first >= 224
            || (first == 100 && (64...127).contains(second))
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
    }

    static func parse(requestedURL: String, html: String) -> ChatLinkPreview? {
        guard let safeURL = safePreviewURL(requestedURL) else { return nil }

        var metadata: [String: String] = [:]

        for tag in matches(pattern: "<meta\\b[^>]*>", in: html) {
            let attributes = parseAttributes(tag)
            guard
                let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                !key.isEmpty,
                let content = attributes["content"]?.cleanedHTMLValue,
                !content.isEmpty,
                metadata[key] == nil
            else {
                continue
            }

            metadata[key] = content
        }

        let title = metadata["og:title"]
            ?? metadata["twitter:title"]
            ?? captureGroup(pattern: "<title\\b[^>]*>(.*?)</title>", in: html)?.cleanedHTMLValue

        let description = metadata["og:description"]
            ?? metadata["twitter:description"]
            ?? metadata["description"]

        let image = (metadata["og:image:secure_url"] ?? metadata["og:image"] ?? metadata["twitter:image"])
            .flatMap { resolveSafeURL(base: safeURL, raw: $0) }

        if (title?.isEmpty ?? true) && (description?.isEmpty ?? true) && image == nil {
            return nil
        }

        let host = URLComponents(string: safeURL)?.host ?? safeURL
        let siteName = metadata["og:site_name"].flatMap { $0.isEmpty ? nil : $0 }
            ?? host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)

        return ChatLinkPreview(
            url: safeURL,
            title: title.map { String($0.prefix(maxTitleLength)) },
            description: description.map { String($0.prefix(maxDescriptionLength)) },
            siteName: String(siteName.prefix(maxSiteNameLength)),
            imageURL: image
        )
    }

    static func resolveSafeURL(base: String, raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let baseURL = URL(string: base), let resolved = URL(string: trimmed, relativeTo: baseURL) else {
            return nil
        }

        return safePreviewURL(resolved.absoluteURL.absoluteString)
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func captureGroup(pattern: String, in text: String) -> String? {
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let groupRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[groupRange])
    }

    private static func parseAttributes(_ tag: String) -> [String: String] {
        let pattern = "([:\\w-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var attributes: [String: String] = [:]

        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }

            let key = String(tag[keyRange]).lowercased()
            let value = (2...4)
                .compactMap { Range(match.range(at: $0), in: tag).map { String(tag[$0]) } }
                .first { !$0.isEmpty } ?? ""

            if attributes[key] == nil {
                attributes[key] = value
            }
        }

        return attributes
    }
}

private extension String {
    var cleanedHTMLValue: String {
        decodingHTMLEntities
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var decodingHTMLEntities: String {
        let pattern = "&(#x[0-9a-f]+|#[0-9]+|amp|quot|apos|lt|gt|nbsp);"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return self
        }

        var result = self
        let matches = regex.matches(in: self, range: NSRange(startIndex..<endIndex, in: self)).reversed()

        for match in matches {
            guard
                let fullRange = Range(match.range, in: result),
                let entityRange = Range(match.range(at: 1), in: result)
            else {
                continue
            }

            result.replaceSubrange(fullRange, with: Self.decodeEntity(String(result[entityRange])))
        }

        return result
    }

    static func decodeEntity(_ entity: String) -> String {
        switch entity.lowercased() {
        case "amp": return "&"
        case "quot": return "\""
        case "apos": return "'"
        case "lt": return "<"
        case "gt": return ">"
        case "nbsp": return " "
        default: break
        }

        let value: Int?

        if entity.lowercased().hasPrefix("#x") {
            value = Int(entity.dropFirst(2), radix: 16)
        } else if entity.hasPrefix("#") {
            value = Int(entity.dropFirst())
        } else {
            value = nil
        }

        guard let value, let scalar = Unicode.Scalar(value) else { return "&\(entity);" }

        return String(Character(scalar))
    }

    func trimmingTrailingCharacters(in set: CharacterSet) -> String {
        var result = self

        while let last = result.unicodeScalars.last, set.contains(last) {
            result.unicodeScalars.removeLast()
        }

        return result
    }
}
