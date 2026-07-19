//
//  ZappDesign.swift
//  Zashi
//
//  Zapp design tokens (spacing, radius, and floating nav-bar metrics)
//  translated 1:1 from the Android reference (Dimensions.kt). dp maps to points.
//

import CoreGraphics

/// Namespaced Zapp design tokens shared across the Zapp UI components.
public enum ZappDesign {
    /// Spacing scale (dp -> points).
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let base: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
    }

    /// Corner-radius scale (dp -> points).
    public enum Radius {
        public static let xs: CGFloat = 4
        public static let small: CGFloat = 8
        public static let base: CGFloat = 12
        public static let medium: CGFloat = 16
        public static let large: CGFloat = 24
    }

    /// Dimensions for the floating pill nav bar.
    public enum NavBar {
        /// Total height reserved for the floating nav bar (pill + bottom padding + nav insets).
        public static let clearance: CGFloat = 80
        /// Bottom padding for the FAB so it sits above the nav bar.
        public static let fabBottomPadding: CGFloat = 72
    }
}
