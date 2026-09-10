// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Where the Reclaim Verifier sends the user when a verification finishes.
///
/// The Verifier hands off to whatever `redirectUrl` the session template carried; sending an empty
/// one leaves the user staring at "you can now return to Zapp" in a browser, with no way back but
/// the home screen. Reclaim validates this field with nothing more than `new URL(...)`, so a
/// private scheme is as acceptable to it as an https link — and a private scheme is the only one
/// that reaches an app rather than a web page. `zcash` is already registered in both Info.plists.
///
/// ☠ The host has to be its own thing, not a bare `zcash://`. `RootDestination` sends an
/// unrecognised `zcash://` URL to the ZIP-321 warning, so a redirect without a host of its own
/// would land returning users there — worse than never coming back at all.
///
/// The URL carries only the session id, platform and corridor. They are untrusted routing hints,
/// never proof: the driver fetches the signed proof from Reclaim and the contract verifies it.
/// Carrying them is what lets a cold-start callback reconstruct the polling session.
enum ReclaimReturnLink {
    static let scheme = "zcash"
    static let host = "reclaim-return"
    /// The same string Android registers, so one return URL serves both platforms.
    static let url = "\(scheme)://\(host)"

    static let sessionIDQuery = "sessionId"
    static let platformQuery = "socialPlatform"
    static let currencyQuery = "currency"

    struct ResumeArgs: Equatable {
        let sessionID: String
        let platformID: String
        let currencyCode: String
    }

    static func resumeArgs(from url: URL) -> ResumeArgs? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        return resumeArgs(
            sessionID: items.first { $0.name == sessionIDQuery }?.value,
            platformID: items.first { $0.name == platformQuery }?.value,
            currencyCode: items.first { $0.name == currencyQuery }?.value
        )
    }

    static func resumeArgs(sessionID: String?, platformID: String?, currencyCode: String?) -> ResumeArgs? {
        guard let session = cleanSessionID(sessionID),
              let platform = SocialPlatformID.match(platformID),
              let currency = ReputationCorridor.match(currencyCode) else { return nil }
        return ResumeArgs(sessionID: session, platformID: platform, currencyCode: currency)
    }

    private static func cleanSessionID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              (1...maxSessionIDCharacters).contains(trimmed.count),
              trimmed.allSatisfy(isSessionIDCharacter) else { return nil }
        return trimmed
    }

    private static func isSessionIDCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }

    private static let maxSessionIDCharacters = 200
}
