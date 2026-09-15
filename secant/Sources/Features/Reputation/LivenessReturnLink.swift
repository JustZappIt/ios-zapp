// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
@preconcurrency import ZappOfframp

/// Where the liveness widget sends the user when it is done. The `redirect_uri` is exact-matched
/// against the tenant's allowlist, so it carries nothing of ours: the corridor rides in `state`.
///
/// ☠ Same host rule as `ReclaimReturnLink`: a bare `zcash://` lands on the ZIP-321 warning.
enum LivenessReturnLink {
    static let scheme = "zcash"
    static let host = "liveness-return"
    static let url = "\(scheme)://\(host)"

    static let codeQuery = LivenessReturn.companion.CODE_QUERY
    static let errorQuery = LivenessReturn.companion.ERROR_QUERY
    static let stateQuery = LivenessReturn.companion.STATE_QUERY

    static func returnModel(from url: URL) -> LivenessReturnModel? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        return returnModel(
            code: items.first { $0.name == codeQuery }?.value,
            error: items.first { $0.name == errorQuery }?.value,
            state: items.first { $0.name == stateQuery }?.value
        )
    }

    static func returnModel(code: String?, error: String?, state: String?) -> LivenessReturnModel? {
        let cleanCode = clean(code, maxCharacters: maxCodeCharacters, allowing: isTokenCharacter)
        let cleanError = clean(error, maxCharacters: maxCodeCharacters, allowing: isTokenCharacter)
        let cleanState = clean(state, maxCharacters: maxStateCharacters, allowing: isStateCharacter)
        guard cleanCode != nil || cleanError != nil else { return nil }
        return LivenessReturnModel(code: cleanCode, error: cleanError, state: cleanState)
    }

    private static func clean(
        _ raw: String?,
        maxCharacters: Int,
        allowing isAllowed: (Character) -> Bool
    ) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              (1...maxCharacters).contains(trimmed.count),
              trimmed.allSatisfy(isAllowed) else { return nil }
        return trimmed
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }

    private static func isStateCharacter(_ character: Character) -> Bool {
        isTokenCharacter(character) || character == "."
    }

    private static let maxCodeCharacters = 128
    private static let maxStateCharacters = 256
}
