//
//  ZappDesignContractTests.swift
//  zodlTests
//

import SwiftUI
import Testing
@testable import zodl_internal

@Suite struct ZappDesignContractTests {
    @Test func androidTypographyContract() {
        #expect(ZappTextStyle.pinHero.size == 42)
        #expect(ZappTextStyle.pinHero.lineHeight == 44)
        #expect(ZappTextStyle.pinHero.tracking == -1.8)

        #expect(ZappTextStyle.display.size == 32)
        #expect(ZappTextStyle.display.lineHeight == 36)
        #expect(ZappTextStyle.display.tracking == -1)

        #expect(ZappTextStyle.screenTitle.size == 22)
        #expect(ZappTextStyle.screenTitle.lineHeight == 28)
        #expect(ZappTextStyle.screenTitle.tracking == -0.5)

        #expect(ZappTextStyle.eyebrow.size == 11)
        #expect(ZappTextStyle.eyebrow.lineHeight == 14)
        #expect(ZappTextStyle.eyebrow.tracking == 1)

        #expect(ZappTextStyle.body.size == 14)
        #expect(ZappTextStyle.body.lineHeight == 20)
        #expect(ZappTextStyle.button.tracking == 0)

        #expect(ZappTextStyle.pinKey.size == 20)
        #expect(ZappTextStyle.pinKey.lineHeight == 24)
    }

    @Test func navigationClearanceContract() {
        #expect(ZappNavBar.clearance == 80)
        #expect(ZappNavBar.fabBottomPadding == 80)
        #expect(ZappNavBar.pushedFloatingMargin == 24)
    }

    @Test func speedDialIdentityIsStable() {
        let first = ZappSpeedDialAction(icon: Image(systemName: "plus"), label: "Send") { }
        let second = ZappSpeedDialAction(icon: Image(systemName: "plus"), label: "Send") { }
        let explicit = ZappSpeedDialAction(id: "receive", icon: Image(systemName: "plus"), label: "Receive") { }

        #expect(first.id == second.id)
        #expect(first.id == "Send")
        #expect(explicit.id == "receive")
    }
}
