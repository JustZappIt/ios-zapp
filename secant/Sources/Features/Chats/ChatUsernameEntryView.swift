//
//  ChatUsernameEntryView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The username step, between `messagingIntro` and `identityDerivation`, wearing the same part-2
/// onboarding chrome as its neighbours.
struct ChatUsernameEntryView: View {
    private enum Constants {
        /// The messaging half of onboarding, shared with `messagingIntro`.
        static let part = 2
        static let heroTopPadding: CGFloat = 14
        static let subtitleTopPadding: CGFloat = 16
        static let fieldTopPadding: CGFloat = 36
        static let fieldVerticalPadding: CGFloat = 6
        static let ruleHeight: CGFloat = 2
        static let hintTopPadding: CGFloat = 10
        static let hintSpacing: CGFloat = 12
        static let handleSpacing: CGFloat = 4
        static let handleMinimumScale: CGFloat = 0.6
        static let heroMinimumScale: CGFloat = 0.7
    }

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isNameFocused: Bool

    @Perception.Bindable var store: StoreOf<ChatUsernameEntry>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappOnboardingProgress(step: Constants.part)
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.progressTopPadding)

                ScrollView {
                    ZStack(alignment: .topTrailing) {
                        ZappOnboardingGhostNumber(number: Constants.part)

                        heading
                    }
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.contentTopPadding)
                }

                ZappOnboardingPrimaryDock {
                    ZappButton(
                        title: String(localizable: .chatIdentityContinue),
                        isEnabled: store.isValid
                    ) {
                        store.send(.continueTapped)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden()
            .task { isNameFocused = true }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZappOnboardingEyebrow(text: String(localizable: .onboardingMsgIntroBadge))

            Text(localizable: .chatIdentityTitle)
                .zappFont(.onboardingHero, style: ZappColors.text)
                .lineLimit(2)
                .minimumScaleFactor(Constants.heroMinimumScale)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Constants.heroTopPadding)

            Text(localizable: .chatIdentitySubtitle)
                .zappFont(.onboardingSub, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Constants.subtitleTopPadding)

            handleField
                .padding(.top, Constants.fieldTopPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Constants.handleSpacing) {
                Text(verbatim: "@")
                    .zappFont(.usernameHandle, style: ZappColors.textSubtle)

                // Drawn rather than handed to `TextField`, which gives no token control over the
                // placeholder's colour.
                ZStack(alignment: .leading) {
                    if store.displayName.isEmpty {
                        Text(localizable: .chatIdentityPlaceholder)
                            .zappFont(.usernameHandle, style: ZappColors.textSubtle)
                            .allowsHitTesting(false)
                    }

                    TextField(
                        "",
                        text: Binding(
                            get: { store.displayName },
                            set: { store.send(.displayNameChanged($0)) }
                        )
                    )
                    .focused($isNameFocused)
                    .zappFont(.usernameHandle, style: ZappColors.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { store.send(.continueTapped) }
                    .accessibilityLabel(String(localizable: .chatIdentityTitle))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(Constants.handleMinimumScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Constants.fieldVerticalPadding)

            Rectangle()
                .fill(ruleStyle.color(colorScheme))
                .frame(height: Constants.ruleHeight)
                .animation(ZappMotion.state, value: ruleStyle)

            HStack(alignment: .top, spacing: Constants.hintSpacing) {
                Text(localizable: .chatIdentityRules)
                    .zappFont(.caption, style: ZappColors.textSubtle)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(localizable: .chatIdentityCounter(store.displayName.count, UsernameRules.maxLength))
                    .zappFont(.caption, style: isOverLimit ? ZappColors.danger : ZappColors.textSubtle)
                    .monospacedDigit()
                    .accessibilityHidden(true)
            }
            .padding(.top, Constants.hintTopPadding)
        }
        .zappFieldTapTarget($isNameFocused)
    }

    private var isOverLimit: Bool { store.displayName.count > UsernameRules.maxLength }

    private var ruleStyle: ZappColors {
        if isOverLimit {
            return .danger
        }
        if store.isValid {
            return .accent
        }
        return isNameFocused ? .borderStrong : .border
    }
}

private extension ZappTextStyle {
    /// Mono: a fixed advance keeps 20 characters inside the gutters.
    static let usernameHandle = ZappTextStyle(
        family: .robotoMono,
        weight: .medium,
        size: 28,
        lineHeight: 34,
        tracking: -0.5
    )
}

#Preview {
    NavigationStack {
        ChatUsernameEntryView(
            store: StoreOf<ChatUsernameEntry>(initialState: .initial) { ChatUsernameEntry() }
        )
    }
}
