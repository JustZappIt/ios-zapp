//
//  AppPINEntryView.swift
//  Zashi
//

import SwiftUI

struct AppPINEntryView: View {
    @Environment(\.colorScheme)
    private var colorScheme

    let title: String
    let subtitle: String
    let errorMessage: String?
    let digitCount: Int
    var isInputEnabled = true
    var showsOnboardingProgress = false
    var onBack: (() -> Void)?
    let onKey: (Character) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showsOnboardingProgress {
                onboardingProgress
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .zappFont(.displaySecondary, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(errorMessage ?? subtitle)
                    .zappFont(
                        .body,
                        style: errorMessage == nil ? ZappColors.textMuted : ZappColors.danger
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Spacer(minLength: 24)

                VStack(spacing: 28) {
                    ZappPINDots(filledCount: digitCount, hasError: errorMessage != nil)
                    ZappPINPad(isEnabled: isInputEnabled, onKey: onKey)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)

            if let onBack {
                ZappBottomActionBar(onBack: onBack)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ZappColors.bg.color(colorScheme))
        .navigationBarBackButtonHidden(true)
        .ignoresSafeArea(.keyboard)
    }

    private var onboardingProgress: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { _ in
                Rectangle()
                    .fill(ZappColors.accent.color(colorScheme))
                    .frame(height: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localizable: .onboardingProgressAccessibility))
    }
}
