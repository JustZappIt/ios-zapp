// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@testable import zodl_internal

/// The three fields a Reclaim callback carries are untrusted routing hints, never proof. They still
/// have to be validated: an unbounded session id reaches an HTTP path, and an unknown platform or
/// corridor would start a run against a rail that does not exist.
struct ReclaimReturnLinkTests {
    @Test func theHappyPathResumesTheSessionTheCallbackNamed() throws {
        let args = try #require(ReclaimReturnLink.resumeArgs(from: url(
            session: "abc-123_XYZ",
            platform: "LinkedIn",
            currency: "INR"
        )))

        #expect(args.sessionID == "abc-123_XYZ")
        #expect(args.platformID == "LinkedIn")
        #expect(args.currencyCode == "INR")
    }

    /// The link is what a third party sends us, so the platform and corridor come back in the
    /// framework's own spelling rather than the caller's.
    @Test func theRoutingKeysAreNormalisedToWhatTheFrameworkKnows() throws {
        let args = try #require(ReclaimReturnLink.resumeArgs(from: url(
            session: "s1",
            platform: "linkedin",
            currency: "inr"
        )))

        #expect(args.platformID == "LinkedIn")
        #expect(args.currencyCode == "INR")
    }

    @Test func anOverLongSessionIdIsRefused() throws {
        let long = String(repeating: "a", count: 201)
        #expect(ReclaimReturnLink.resumeArgs(from: try url(session: long, platform: "X", currency: "INR")) == nil)
    }

    @Test func aSessionIdAtTheLimitIsAccepted() throws {
        let atLimit = String(repeating: "a", count: 200)
        let args = try #require(
            ReclaimReturnLink.resumeArgs(from: try url(session: atLimit, platform: "X", currency: "INR"))
        )
        #expect(args.sessionID == atLimit)
    }

    @Test(arguments: ["a/b", "a b", "a?b", "../etc", "a%2Fb", ""])
    func aSessionIdOutsideTheAllowedAlphabetIsRefused(session: String) throws {
        #expect(ReclaimReturnLink.resumeArgs(from: try url(session: session, platform: "X", currency: "INR")) == nil)
    }

    @Test func anUnknownPlatformIsRefused() throws {
        #expect(ReclaimReturnLink.resumeArgs(from: try url(session: "s1", platform: "Myspace", currency: "INR")) == nil)
    }

    @Test func anUnknownCurrencyIsRefused() throws {
        #expect(ReclaimReturnLink.resumeArgs(from: try url(session: "s1", platform: "X", currency: "XYZ")) == nil)
    }

    @Test func aCallbackMissingAFieldIsRefusedRatherThanGuessedAt() throws {
        let missing = try #require(URL(string: "\(ReclaimReturnLink.url)?sessionId=s1&socialPlatform=X"))
        #expect(ReclaimReturnLink.resumeArgs(from: missing) == nil)
    }

    /// ☠ The host has to be its own thing: `RootDestination` sends an unrecognised `zcash://` URL
    /// to the ZIP-321 warning, so a redirect without one would land returning users there.
    @Test func theRegisteredReturnUrlCarriesItsOwnHost() {
        #expect(ReclaimReturnLink.url == "zcash://reclaim-return")
        #expect(URL(string: ReclaimReturnLink.url)?.host() == ReclaimReturnLink.host)
    }

    private func url(session: String, platform: String, currency: String) throws -> URL {
        var components = try #require(URLComponents(string: ReclaimReturnLink.url))
        components.queryItems = [
            URLQueryItem(name: ReclaimReturnLink.sessionIDQuery, value: session),
            URLQueryItem(name: ReclaimReturnLink.platformQuery, value: platform),
            URLQueryItem(name: ReclaimReturnLink.currencyQuery, value: currency)
        ]
        return try #require(components.url)
    }
}
