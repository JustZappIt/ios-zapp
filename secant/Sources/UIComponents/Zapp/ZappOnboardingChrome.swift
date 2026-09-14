//
//  ZappOnboardingChrome.swift
//  Zapp
//
//  The chrome every onboarding step shares. Lifted out of `RestoreWalletCoordFlowView` once the
//  username step, which lives in its own file, needed the same pieces.
//

import SwiftUI

extension ZappTextStyle {
    static let onboardingHero = ZappTextStyle(weight: .bold, size: 42, lineHeight: 44, tracking: -1.4)
    static let onboardingGhost = ZappTextStyle(weight: .bold, size: 130, lineHeight: 130, tracking: -5)
    static let onboardingSub = ZappTextStyle(weight: .regular, size: 13, lineHeight: 22)
}

/// The onboarding screen gutter, wider than the 18pt in-app one.
enum ZappOnboarding {
    static let gutter: CGFloat = 28
    static let progressTopPadding: CGFloat = 20
    static let contentTopPadding: CGFloat = 24
}

struct ZappOnboardingPrimaryDock<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .background(ZappColors.surface.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.text.color(colorScheme), lineWidth: 1)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
    }
}

struct ZappOnboardingProgress: View {
    @Environment(\.colorScheme) private var colorScheme

    let step: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { segment in
                Rectangle()
                    .fill(
                        (segment <= step ? ZappColors.accent : ZappColors.border)
                            .color(colorScheme)
                    )
                    .frame(height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .onboardingProgressAccessibility))
    }
}

struct ZappOnboardingGhostNumber: View {
    let number: Int

    var body: some View {
        Text(String(format: "%02d", number))
            .zappFont(.onboardingGhost, style: ZappColors.surfaceAlt)
            .accessibilityHidden(true)
            .offset(x: 6, y: -22)
    }
}

struct ZappOnboardingEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .zappFont(.eyebrow, style: ZappColors.accentText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
