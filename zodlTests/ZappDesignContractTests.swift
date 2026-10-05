//
//  ZappDesignContractTests.swift
//  zodlTests
//

import SwiftUI
import Testing
@testable import zodl_internal

@Suite struct ZappDesignContractTests {
    @Test func androidTypographyContract() {
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
    }

    /// Android's `PinComponents.kt`: 60dp keys, digits in `button` at 20sp Black, 14dp dots that pop
    /// in from 1.35x, and a 180ms release fade. The hero title keeps its own iOS style.
    @Test func pinSizingContract() {
        #expect(ZappTextStyle.pinHero.size == 46)
        #expect(ZappTextStyle.pinHero.lineHeight == 49)
        #expect(ZappTextStyle.pinHero.tracking == -2)
        #expect(ZappPINMetrics.keyHeight == 60)
        #expect(ZappPINMetrics.keyStyle.size == 20)
        #expect(ZappPINMetrics.keyStyle.weight == .black)
        #expect(ZappPINMetrics.dotSize == 14)
        #expect(ZappPINMetrics.dotPopScale == 1.35)
        #expect(ZappPINMetrics.keyReleaseFade == 0.18)
    }

    /// The three tokens iOS lacked until the parity pass, byte-for-byte from `ZappPalette.kt`.
    @Test func androidPaletteAdditions() {
        #expect(ZappPalette.light.accentShade == Color(zappHex: 0xFFE9_7A0A))
        #expect(ZappPalette.dark.accentShade == Color(zappHex: 0xFFE3_7609))
        #expect(ZappPalette.light.accentBorder == .clear)
        #expect(ZappPalette.dark.accentBorder == Color(zappHex: 0xFF2A_2622))
        #expect(ZappPalette.light.onCompletion == Color(zappHex: 0xFF21_1A08))
        #expect(ZappPalette.dark.onCompletion == Color(zappHex: 0xFF21_1A08))
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
