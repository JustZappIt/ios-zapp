//
//  ZappRestoreBirthdayView.swift
//  Zapp
//
//  Android's `RestoreBirthdayScreen` (view/RestoreFlowViews.kt).
//

import ComposableArchitecture
import SwiftUI

struct ZappRestoreBirthdayView: View {
    private enum Constants {
        /// Matches the upstream date screen's cap: SwiftUI's wheel picker is vertically greedy.
        static let wheelHeight: CGFloat = 180
        static let fieldBorderWidth: CGFloat = 2
    }

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isHeightFocused: Bool

    @Perception.Bindable var store: StoreOf<ZappRestoreBirthday>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappOnboardingProgress(step: 1)
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.progressTopPadding)

                ScrollView {
                    ZStack(alignment: .topTrailing) {
                        ZappOnboardingGhostNumber(number: 1)

                        VStack(alignment: .leading, spacing: 0) {
                            ZappRestoreHeading(
                                badge: String(localizable: .restoreFlowBirthdayBadge),
                                title: String(localizable: .restoreFlowBirthdayTitle),
                                subtitle: String(localizable: .restoreFlowBirthdaySubtitle),
                                onHelp: { store.send(.helpTapped) }
                            )

                            ZappSegmentedSelector(
                                options: [
                                    String(localizable: .restoreFlowBirthdayModeHeight),
                                    String(localizable: .restoreFlowBirthdayModeDate)
                                ],
                                selectedIndex: store.mode == .height ? 0 : 1
                            ) { index in
                                isHeightFocused = false
                                store.send(.modeSelected(index == 0 ? .height : .date), animation: ZappMotion.content)
                            }
                            .padding(.top, 28)

                            Group {
                                switch store.mode {
                                case .height:
                                    heightField
                                case .date:
                                    datePicker
                                }
                            }
                            .padding(.top, 20)

                            if let errorMessage = store.errorMessage {
                                Text(errorMessage)
                                    .zappFont(.caption, style: ZappColors.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 16)
                            }

                            Button {
                                isHeightFocused = false
                                store.send(.skipTapped)
                            } label: {
                                Text(localizable: .restoreFlowBirthdaySkip)
                                    .zappFont(.buttonSmall, style: ZappColors.accentText)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.zappPress)
                            .padding(.top, 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, ZappOnboarding.gutter)
                    .padding(.top, ZappOnboarding.contentTopPadding)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                    ZappButton(
                        title: store.mode == .date
                            ? String(localizable: .restoreWalletBirthdayEstimate)
                            : String(localizable: .importWalletButtonRestoreWallet)
                    ) {
                        isHeightFocused = false
                        store.send(.primaryTapped, animation: ZappMotion.content)
                    }
                }
            }
            .background(ZappColors.bg.color(colorScheme))
            .navigationBarBackButtonHidden(true)
            .zappSwipeBack { store.send(.backTapped) }
        }
    }

    private var heightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizable: .restoreFlowBirthdayFieldLabel)
                .zappFont(.groupLabel, style: ZappColors.textSubtle)

            ZStack(alignment: .leading) {
                if store.heightText.isEmpty {
                    Text(localizable: .restoreFlowBirthdayFieldHint)
                        .zappFont(.birthdayHeight, style: ZappColors.textSubtle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsHitTesting(false)
                }

                TextField(
                    "",
                    text: Binding(
                        get: { store.heightText },
                        set: { store.send(.heightTextChanged($0)) }
                    )
                )
                .focused($isHeightFocused)
                .keyboardType(.numberPad)
                .zappFont(.birthdayHeight, style: ZappColors.text)
                .accessibilityLabel(String(localizable: .restoreFlowBirthdayModeHeight))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .overlay {
                Rectangle()
                    .strokeBorder(
                        (store.heightText.isEmpty ? ZappColors.border : ZappColors.text).color(colorScheme),
                        lineWidth: Constants.fieldBorderWidth
                    )
            }
            .zappFieldTapTarget($isHeightFocused)
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Picker(
                    "",
                    selection: Binding(
                        get: { store.selectedMonth },
                        set: { store.send(.monthSelected($0)) }
                    )
                ) {
                    ForEach(ZappRestoreBirthday.months(for: store.selectedYear, now: Date()), id: \.self) { month in
                        Text(ZappRestoreBirthday.calendar.standaloneMonthSymbols[month - 1].localizedCapitalized)
                            .zappFont(.sectionTitle, style: ZappColors.text)
                    }
                }
                .pickerStyle(.wheel)

                Picker(
                    "",
                    selection: Binding(
                        get: { store.selectedYear },
                        set: { store.send(.yearSelected($0)) }
                    )
                ) {
                    ForEach(ZappRestoreBirthday.years(now: Date()), id: \.self) { year in
                        Text(verbatim: String(year))
                            .zappFont(.sectionTitle, style: ZappColors.text)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(maxHeight: Constants.wheelHeight)

            Text(localizable: .restoreFlowBirthdayDateNote)
                .zappFont(.caption, style: ZappColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension ZappTextStyle {
    static let birthdayHeight = ZappTextStyle(weight: .black, size: 22, lineHeight: 28, tracking: -0.4)
}

#Preview {
    NavigationStack {
        ZappRestoreBirthdayView(
            store: StoreOf<ZappRestoreBirthday>(initialState: .initial) { ZappRestoreBirthday() }
        )
    }
}
