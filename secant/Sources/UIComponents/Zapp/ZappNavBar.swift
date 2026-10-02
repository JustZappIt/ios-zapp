//
//  ZappNavBar.swift
//  Zapp
//

import SwiftUI

/// Clearances for the floating pill nav bar, mirroring `ZappNavBar` in `ZappPalette.kt`.
///
/// iOS resolves the system inset through the safe area, so unlike Android these are the pill's own
/// height and margins only — do not add a navigation-bar inset on top.
enum ZappNavBar {
    /// Bottom clearance for scrollable content so the pill never covers the last row.
    static let clearance: CGFloat = 80

    /// Bottom padding for FABs anchored above the pill.
    static let fabBottomPadding: CGFloat = 80

    /// Extra bottom clearance for a list scrolling under a FAB: the 56pt FAB plus a 16pt gap. Add it
    /// to `fabBottomPadding` so the last row can scroll clear of the button.
    static let fabListClearance: CGFloat = 72

    /// Bottom margin for floating buttons on pushed sub-screens, where the pill is absent and
    /// `fabBottomPadding` would strand them well above the thumb zone.
    static let pushedFloatingMargin: CGFloat = 24
}
