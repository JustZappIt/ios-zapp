// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
import ZappOfframp
@testable import zodl_internal

struct LivenessReturnLinkTests {
    @Test func aSuccessfulReturnCarriesTheCodeAndTheCorridorInState() throws {
        let ret = try #require(LivenessReturnLink.returnModel(from: try url(code: "abc-123_XYZ", state: "0f1e2d3c.INR")))

        #expect(ret.code == "abc-123_XYZ")
        #expect(ret.error == nil)
        #expect(ret.state == "0f1e2d3c.INR")
        #expect(ret.currencyCode == "INR")
    }

    @Test func aFailedReturnCarriesTheErrorAndNoCorridor() throws {
        let ret = try #require(LivenessReturnLink.returnModel(from: try url(error: "duplicate_person", state: "nonce.BRL")))

        #expect(ret.code == nil)
        #expect(ret.error == "duplicate_person")
        #expect(ret.currencyCode == "BRL")
    }

    @Test func aReturnWithNeitherACodeNorAnErrorIsNothing() throws {
        #expect(LivenessReturnLink.returnModel(from: try url(state: "0f1e2d3c.INR")) == nil)
        #expect(LivenessReturnLink.returnModel(code: "   ", error: nil, state: nil) == nil)
    }

    @Test func fieldsAreBoundedAndCharacterChecked() throws {
        let long = String(repeating: "a", count: 129)
        #expect(LivenessReturnLink.returnModel(from: try url(code: long)) == nil)
        // A dot is legal in state — it separates the nonce from the corridor — but not in a code.
        #expect(LivenessReturnLink.returnModel(from: try url(code: "a.b")) == nil)
        #expect(LivenessReturnLink.returnModel(from: try url(code: "ok", state: "not a state")) == nil)
    }

    @Test func theCorridorIsReadBackThroughTheFrameworksOwnState() throws {
        let state = IdentityReturn.companion.state(nonce: "0f1e2d3c", currency: CurrencyCode.brl)
        let ret = try #require(LivenessReturnLink.returnModel(from: try url(code: "ok", state: state)))

        #expect(ret.currencyCode == CurrencyCode.brl.code)
        #expect(LivenessReturnModel(code: "ok", error: nil, state: "0f1e2d3c.XXX").currencyCode == nil)
    }

    @Test func theHostIsItsOwnThing() {
        #expect(LivenessReturnLink.url == "zcash://liveness-return")
        #expect(LivenessReturnLink.host != ReclaimReturnLink.host)
    }

    @Test(arguments: [
        "https://liveness-return?code=ok&state=nonce.BRL",
        "zcash://liveness-return/path?code=ok&state=nonce.BRL",
        "zcash://liveness-return?code=ok&code=other&state=nonce.BRL",
        "zcash://liveness-return?code=ok&error=cancelled&state=nonce.BRL",
        "zcash://liveness-return?code=ok",
        "zcash://liveness-return?error=cancelled",
        "zcash://user@liveness-return?code=ok&state=nonce.BRL"
    ]) func ambiguousOrUnboundCallbacksAreRejected(_ raw: String) throws {
        #expect(LivenessReturnLink.returnModel(from: try #require(URL(string: raw))) == nil)
    }

    @Test func passportCallbackRetainsItsCheckType() throws {
        let url = try #require(URL(string: "zcash://passport-return?code=passport-code&state=nonce.INR"))
        let result = try #require(LivenessReturnLink.returnModel(from: url))
        #expect(result.check == .passport)
        #expect(result.currencyCode == "INR")
        #expect(result.code == "passport-code")
    }

    private func url(code: String? = nil, error: String? = nil, state: String? = nil) throws -> URL {
        var components = try #require(URLComponents(string: LivenessReturnLink.url))
        components.queryItems = [
            code.map { URLQueryItem(name: LivenessReturnLink.codeQuery, value: $0) },
            error.map { URLQueryItem(name: LivenessReturnLink.errorQuery, value: $0) },
            state.map { URLQueryItem(name: LivenessReturnLink.stateQuery, value: $0) }
        ].compactMap { $0 }
        return try #require(components.url)
    }
}
