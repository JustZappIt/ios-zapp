//
//  ZappRestoreBirthdayStore.swift
//  Zapp
//
//  Step 2 of the Zapp restore flow (Android's `RestoreStep.BIRTHDAY`, `ZappRestoreFlowVM`'s
//  birthday half): one screen with "Block Height | Month & Year" tabs where the upstream flow had
//  three screens. Estimating from a month writes the height back into the field and switches to
//  the height tab, so the user restores from a value they can see.
//

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

@Reducer
struct ZappRestoreBirthday {
    enum Mode: Equatable {
        case height
        case date
    }

    enum Constants {
        /// The month the Sapling network upgrade activated, the earliest a Zapp-restorable wallet
        /// can be. Android and the upstream date picker start here too.
        static let startYear = 2018
        static let startMonth = 10
    }

    @ObservableState
    struct State: Equatable {
        var errorMessage: String?
        var heightText = ""
        var mode = Mode.height
        var selectedMonth = Constants.startMonth
        var selectedYear = Constants.startYear

        static let initial = State()
    }

    enum Action: Equatable {
        case backTapped
        case heightTextChanged(String)
        case helpTapped
        case modeSelected(Mode)
        case monthSelected(Int)
        case primaryTapped
        /// Delegate: the coordinator starts the restore from this height.
        case restoreRequested(BlockHeight)
        case skipTapped
        case yearSelected(Int)
    }

    @Dependency(\.date) var date
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .heightTextChanged(let text):
                state.heightText = text.filter(\.isNumber)
                state.errorMessage = nil
                return .none

            case .modeSelected(let mode):
                state.mode = mode
                state.errorMessage = nil
                return .none

            case .monthSelected(let month):
                state.selectedMonth = month
                state.errorMessage = nil
                clampSelection(&state)
                return .none

            case .yearSelected(let year):
                state.selectedYear = year
                state.errorMessage = nil
                clampSelection(&state)
                return .none

            case .primaryTapped:
                switch state.mode {
                case .date:
                    estimateFromDate(&state)
                    return .none
                case .height:
                    let saplingActivation = saplingActivationHeight
                    // A blank field scans from Sapling activation: slow, but nothing is missed.
                    guard !state.heightText.isEmpty else {
                        return .send(.restoreRequested(saplingActivation))
                    }
                    guard let height = BlockHeight(state.heightText), height >= saplingActivation else {
                        state.errorMessage = String(localizable: .restoreFlowErrorBirthdayTooLow(String(saplingActivation)))
                        return .none
                    }
                    return .send(.restoreRequested(height))
                }

            case .skipTapped:
                // Android restores from whatever is in the field here; "scan everything" means the
                // whole chain, so a half-typed height is ignored rather than trusted.
                return .send(.restoreRequested(saplingActivationHeight))

            case .backTapped, .helpTapped, .restoreRequested:
                return .none
            }
        }
    }

    private var saplingActivationHeight: BlockHeight {
        zcashSDKEnvironment.network().constants.saplingActivationHeight
    }

    private func estimateFromDate(_ state: inout State) {
        var components = DateComponents()
        components.year = state.selectedYear
        components.month = state.selectedMonth
        components.day = 1
        guard let date = Self.calendar.date(from: components) else {
            state.errorMessage = String(localizable: .restoreFlowErrorEstimationFailed)
            return
        }
        let estimate = sdkSynchronizer.estimateBirthdayHeight(date)
        guard estimate > 0 else {
            state.errorMessage = String(localizable: .restoreFlowErrorEstimationFailed)
            return
        }
        state.heightText = String(max(estimate, saplingActivationHeight))
        state.mode = .height
        state.errorMessage = nil
    }

    /// Keeps the picker inside October 2018 ... this month, the range `months(for:)` offers.
    private func clampSelection(_ state: inout State) {
        let available = Self.months(for: state.selectedYear, now: date.now())
        if let first = available.first, state.selectedMonth < first {
            state.selectedMonth = first
        } else if let last = available.last, state.selectedMonth > last {
            state.selectedMonth = last
        }
    }
}

extension ZappRestoreBirthday {
    /// Always Gregorian, whatever calendar the phone is set to: the years and months on screen and
    /// the date handed to the birthday estimate are Gregorian ones. With the phone's calendar, a
    /// phone set to the Japanese calendar turned "October 2018" into a date centuries ahead, and
    /// the restore started past every transaction.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar
    }()

    static func years(now: Date) -> [Int] {
        Array(Constants.startYear...max(Constants.startYear, calendar.component(.year, from: now)))
    }

    /// The 1-based months selectable in `year`: none before Sapling, none in the future.
    static func months(for year: Int, now: Date) -> [Int] {
        let currentYear = calendar.component(.year, from: now)
        let first = year == Constants.startYear ? Constants.startMonth : 1
        let last = year == currentYear ? calendar.component(.month, from: now) : 12
        return first <= last ? Array(first...last) : []
    }
}
