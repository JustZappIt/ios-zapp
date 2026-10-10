//
//  ZappRestoreSeedEntryView.swift
//  Zapp
//
//  Android's `RestoreSeedEntryScreen` (view/RestoreFlowViews.kt): onboarding chrome, a 24-field
//  grid, a suggestions row and a back + Next dock.
//

import ComposableArchitecture
import SwiftUI

struct ZappRestoreSeedEntryView: View {
    private enum Constants {
        static let columns = 3
        static let rows = 8
        static let cellSpacing: CGFloat = 6
        static let cellHeight: CGFloat = 40
        static let numberWidth: CGFloat = 18
        static let suggestionSpacing: CGFloat = 6
    }

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Int?

    @Perception.Bindable var store: StoreOf<ZappRestoreSeedEntry>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappOnboardingProgress(step: 1)
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.progressTopPadding)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ZappRestoreHeading(
                                badge: String(localizable: .restoreFlowSeedBadge),
                                title: String(localizable: .restoreFlowSeedTitle),
                                subtitle: String(localizable: .restoreFlowSeedSubtitle),
                                onHelp: { store.send(.helpTapped) }
                            )
                            #if DEBUG
                            .onLongPressGesture { store.send(.debugPasteSeed) }
                            #endif

                            grid
                                .padding(.top, 28)
                        }
                        .padding(.horizontal, ZappOnboarding.gutter)
                        .padding(.top, ZappOnboarding.contentTopPadding)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedField) { index in
                        store.send(.selectedIndex(index))
                        if let index {
                            withAnimation(ZappMotion.content) {
                                proxy.scrollTo(index / Constants.columns, anchor: .center)
                            }
                        }
                    }
                }

                if focusedField != nil && !store.suggestedWords.isEmpty {
                    suggestions
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                    ZappButton(
                        title: String(localizable: .generalNext),
                        isEnabled: store.isValidSeed
                    ) {
                        store.send(.nextTapped)
                    }
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden(true)
            .zappSwipeBack { store.send(.backTapped) }
            .privacySensitive()
            .onChange(of: store.nextIndex) { nextIndex in
                if let nextIndex {
                    focusedField = nextIndex
                }
            }
            .onChange(of: store.isValidSeed) { isValid in
                if isValid {
                    focusedField = nil
                }
            }
        }
    }

    private var grid: some View {
        VStack(spacing: Constants.cellSpacing) {
            ForEach(0..<Constants.rows, id: \.self) { row in
                HStack(spacing: Constants.cellSpacing) {
                    ForEach(0..<Constants.columns, id: \.self) { column in
                        cell(row * Constants.columns + column)
                    }
                }
                .id(row)
            }
        }
    }

    private func cell(_ index: Int) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%02d", index + 1))
                .zappFont(.groupLabel, style: ZappColors.textSubtle)
                .frame(width: Constants.numberWidth, alignment: .leading)
                .accessibilityHidden(true)

            TextField("", text: $store.words[index])
                .zappFont(.rowSubtitle, style: ZappColors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.alphabet)
                .submitLabel(.next)
                .focused($focusedField, equals: index)
                .onSubmit {
                    focusedField = index + 1 < ZappRestoreSeedEntry.wordCount ? index + 1 : 0
                }
                .accessibilityLabel(String(localizable: .restoreFlowSeedWordAccessibility(index + 1)))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: Constants.cellHeight, alignment: .leading)
        .background(ZappColors.surface.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(borderStyle(index).color(colorScheme), lineWidth: focusedField == index ? 2 : 1)
        }
        .animation(ZappMotion.state, value: focusedField == index)
        .zappFieldTapTarget($focusedField, equals: index)
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.suggestionSpacing) {
                ForEach(store.suggestedWords, id: \.self) { word in
                    Button {
                        store.send(.suggestedWordTapped(word))
                    } label: {
                        Text(word)
                            .zappFont(.buttonSmall, style: ZappColors.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay {
                                Rectangle()
                                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.zappPress)
                }
            }
            .padding(.horizontal, ZappOnboarding.gutter)
            .padding(.vertical, 6)
        }
        .background(ZappColors.bg.color(colorScheme))
    }

    private func borderStyle(_ index: Int) -> ZappColors {
        if !store.wordsValidity[index] {
            return .danger
        }
        return focusedField == index ? .text : .border
    }
}

/// The badge, hero and subtitle every Zapp restore step opens with, with the iOS-only help button
/// the upstream restore screens carried.
struct ZappRestoreHeading: View {
    let badge: String
    let title: String
    let subtitle: String
    var onHelp: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                ZappOnboardingEyebrow(text: badge)

                Spacer(minLength: 0)

                if let onHelp {
                    ZappInfoButton(
                        accessibilityLabel: String(localizable: .restoreWalletHelpTitle),
                        action: onHelp
                    )
                }
            }

            Text(title)
                .zappFont(.onboardingHero, style: ZappColors.text)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Text(subtitle)
                .zappFont(.onboardingSub, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        ZappRestoreSeedEntryView(
            store: StoreOf<ZappRestoreSeedEntry>(initialState: .initial) { ZappRestoreSeedEntry() }
        )
    }
}
