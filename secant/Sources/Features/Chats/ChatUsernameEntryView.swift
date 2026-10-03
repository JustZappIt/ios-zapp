//
//  ChatUsernameEntryView.swift
//  Zapp
//

import ComposableArchitecture
import SwiftUI

/// The username step, between `messagingIntro` (or the restore flow's seed confirm) and
/// `identityDerivation`, wearing the same part-2 onboarding chrome as its neighbours. Android's
/// `UsernameEntryScreen` (view/MessagingIdentityView.kt).
struct ChatUsernameEntryView: View {
    private enum Constants {
        /// The messaging half of onboarding, shared with `messagingIntro`.
        static let part = 2
        static let heroTopPadding: CGFloat = 14
        static let subtitleTopPadding: CGFloat = 14
        static let fieldTopPadding: CGFloat = 28
        static let fieldPadding: CGFloat = 12
        static let fieldVerticalPadding: CGFloat = 14
        static let fieldBorderWidth: CGFloat = 2
        static let chipsTopPadding: CGFloat = 12
        static let chipSpacing: CGFloat = 14
        static let calloutTopPadding: CGFloat = 20
        static let calloutIconSize: CGFloat = 14
        static let handleSpacing: CGFloat = 2
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
                    .padding(.bottom, 16)
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
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
            .zappSwipeBack { store.send(.backTapped) }
            .task { isNameFocused = true }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZappOnboardingEyebrow(text: String(localizable: .onboardingUsernameBadge))

            Text(localizable: .onboardingUsernameTitle)
                .zappFont(.onboardingHero, style: ZappColors.text)
                .lineLimit(2)
                .minimumScaleFactor(Constants.heroMinimumScale)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Constants.heroTopPadding)

            Text(localizable: .onboardingUsernameSubtitle)
                .zappFont(.onboardingSub, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Constants.subtitleTopPadding)

            handleField
                .padding(.top, Constants.fieldTopPadding)

            HStack(spacing: Constants.chipSpacing) {
                ruleChip(String(localizable: .onboardingUsernameRuleMin), isMet: store.displayName.count >= UsernameRules.minLength)
                ruleChip(String(localizable: .onboardingUsernameRuleMax), isMet: store.displayName.count <= UsernameRules.maxLength)
                // `sanitize` guarantees the character set, so this is met as soon as anything is typed.
                ruleChip(String(localizable: .onboardingUsernameRuleCharset), isMet: !store.displayName.isEmpty)
            }
            .padding(.top, Constants.chipsTopPadding)

            callout
                .padding(.top, Constants.calloutTopPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handleField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.handleSpacing) {
            Text(verbatim: "@")
                .zappFont(.usernameHandle, style: ZappColors.textSubtle)

            // Drawn rather than handed to `TextField`, which gives no token control over the
            // placeholder's colour.
            ZStack(alignment: .leading) {
                if store.displayName.isEmpty {
                    Text(localizable: .onboardingUsernamePlaceholder)
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

            if store.isValid {
                Text(verbatim: "✓")
                    .zappFont(.sectionTitle, style: ZappColors.success)
                    .accessibilityHidden(true)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(Constants.handleMinimumScale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.fieldPadding)
        .padding(.vertical, Constants.fieldVerticalPadding)
        .overlay {
            Rectangle()
                .strokeBorder(
                    (store.displayName.isEmpty ? ZappColors.border : ZappColors.text).color(colorScheme),
                    lineWidth: Constants.fieldBorderWidth
                )
                .animation(ZappMotion.state, value: store.displayName.isEmpty)
        }
        .zappFieldTapTarget($isNameFocused)
    }

    private func ruleChip(_ label: String, isMet: Bool) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: isMet ? "✓" : "✕")
            Text(label)
        }
        .zappFont(.chip, style: isMet ? ZappColors.success : ZappColors.textSubtle)
        .animation(ZappMotion.state, value: isMet)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isMet ? .isSelected : [])
    }

    private var callout: some View {
        HStack(alignment: .top, spacing: 10) {
            Asset.Assets.Icons.shieldTick.image
                .zImage(size: Constants.calloutIconSize, style: ZappColors.accent)
                .padding(.top, 2)

            Text(localizable: .onboardingUsernameInfo)
                .zappFont(.caption, style: ZappColors.textSubtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        }
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
