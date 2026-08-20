// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Testing
@preconcurrency import ZappOfframp
@testable import zodl_internal

@Suite(.serialized)
struct OnrampDeviceSignalsTests {
    @MainActor
    @Test func timezoneOffsetUsesMinutesWestOfUTC() throws {
        let india = try #require(TimeZone(secondsFromGMT: 5 * 60 * 60 + 30 * 60))
        let record = OnrampDeviceSignals.record(connectionType: "wifi", timeZone: india)

        #expect(record.timezoneOffset == -330)
        #expect(record.online)
        #expect(record.connectionType == "wifi")
        #expect(record.platform == "iOS")
    }

    @MainActor
    @Test func anUnnamedTransportIsStillReportedOnline() {
        let record = OnrampDeviceSignals.record(connectionType: nil, isOnline: true)

        #expect(record.online)
        #expect(record.connectionType == nil)
    }

    @MainActor
    @Test func anUnsatisfiedPathIsReportedOffline() {
        let record = OnrampDeviceSignals.record(connectionType: nil, isOnline: false)

        #expect(!record.online)
    }
}
