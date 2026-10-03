//
//  RestoreWalletCoordFlowStore.swift
//  Zashi
//
//  Created by Lukáš Korba on 27-03-2025.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

@preconcurrency import MnemonicSwift

@Reducer
struct RestoreWalletCoordFlow {
    enum LandingStep: Equatable {
        case welcome
        case walletIntro
        case walletChoice
        case creatingWallet
    }

    enum WalletProvisioningMode: Equatable {
        case created
        case restored
    }

    /// The phrase and birthday a restore runs with, kept until it succeeds so Retry can rerun it.
    struct RestoreRequest: Equatable {
        var seedPhrase: String
        var birthday: BlockHeight
    }

    @Reducer
    enum Path {
        case appLockSetup(AppLockSetup)
        case chatUsername(ChatUsernameEntry)
        case done(OnboardingDone)
        case identityDerivation(OnboardingIdentityDerivation)
        case keepOpen(ZappKeepOpen)
        case messagingIntro(OnboardingMessagingIntro)
        case restoreBirthday(ZappRestoreBirthday)
        case restoreSeedEntry(ZappRestoreSeedEntry)
        case restoring(ZappRestoreProgress)
        case seedBackup(OnboardingSeedBackup)
    }
    
    @ObservableState
    struct State {
        @Presents var alert: AlertState<Action>?
        var isHelpSheetPresented = false
        var isKeyboardVisible = false
        var isValidSeed = false
        var landingForward = true
        var landingStep = LandingStep.welcome
        var walletCreationError: String?
        var nextIndex: Int?
        var path = StackState<Path.State>()
        /// A saved wallet the SDK has not prepared yet. A new wallet is prepared only once its
        /// seed is backed up, so the seed backup step provisions it on continue.
        var pendingProvisioning: WalletProvisioningMode?
        var restoreRequest: RestoreRequest?
        var prevWords: [String] = Array(repeating: "", count: 24)
        var selectedIndex: Int?
        var suggestedWords: [String] = []
        var words: [String] = Array(repeating: "", count: 24)
        var wordsValidity: [Bool] = Array(repeating: true, count: 24)

        /// The restore flow ends on Keep open instead of Done. A resumed restore starts on the
        /// seed confirm step, so that marks it as well as the seed entry does.
        var isImportingWallet: Bool {
            path.contains { element in
                if element.is(\.restoreSeedEntry) {
                    return true
                }
                if case let .seedBackup(seedBackup) = element {
                    return seedBackup.kind == .confirm
                }
                return false
            }
        }
        
        init() { }
    }

    enum Action: BindableAction {
        case alert(PresentationAction<Action>)
        case binding(BindingAction<RestoreWalletCoordFlow.State>)
        case chatIdentityAvailable
        case evaluateSeedValidity
        case helpSheetRequested
        case landingBackTapped
        case landingContinueTapped
        case landingGetStartedTapped
        case nextTapped
        case path(StackActionOf<Path>)
        case restoreFailed(ZcashError)
        /// Keep open's "Enter Zapp": Root takes the restored wallet home.
        case restoreFlowCompleted(keepsScreenOn: Bool)
        case restoreSucceeded
        /// Launch found a saved wallet whose onboarding never finished.
        case resume(OnboardingResumePlan)
        case selectedIndex(Int?)
        case suggestedWordTapped(String)
        case suggestionsRequested(Int, Bool)
        case updateKeyboardFlag(Bool)
        case walletProvisioned(WalletProvisioningMode)
        #if DEBUG
        case debugPasteSeed
        #endif
        
        // Onboarding
        case createNewWalletTapped
        case createNewWalletRequested
        case createNewWalletRetryTapped
        case createNewWalletFailed(ZcashError)
        case dismissDestination
        case importExistingWallet
        case newWalletPersisted
        case newWalletSuccessfullyCreated
    }

    @Dependency(\.appSecurity) var appSecurity
    @Dependency(\.mnemonic) var mnemonic
    @Dependency(\.continuousClock) var continuousClock
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.userDefaults) var userDefaults
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    init() { }

    var body: some Reducer<State, Action> {
        coordinatorReduce()

        BindingReducer()

        Reduce { state, action in
            switch action {
            case .alert(.presented(let action)):
                return .send(action)
                
            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .binding(\.words):
                let changedIndices = state.words.indices.filter { state.words[$0] != state.prevWords[$0] }
                state.prevWords = state.words

                if let index = changedIndices.first {
                    let word = state.words[index]
                    if word.hasSuffix(" ") {
                        state.words[index] = word.trimmingCharacters(in: .whitespaces)
                        state.prevWords = state.words
                        return .send(.suggestedWordTapped(state.words[index]))
                    }
                    
                    return .send(.suggestionsRequested(index, false))
                }
                
                return .none
                
            case .selectedIndex(let index):
                state.selectedIndex = index
                state.nextIndex = state.selectedIndex
                if let index {
                    return .send(.suggestionsRequested(index, true))
                }
                return .none
                
            case let .suggestionsRequested(index, hasIndexChanged):
                let prefix = state.words[index]
                if prefix.isEmpty {
                    state.suggestedWords = []
                } else {
                    state.suggestedWords = mnemonic.suggestWords(prefix)
                    state.wordsValidity[index] = !state.suggestedWords.isEmpty
                }
                if hasIndexChanged {
                    if let first = state.suggestedWords.first, first == prefix && !state.isValidSeed && state.suggestedWords.count == 1 {
                        return .none
                    }
                }
                return .send(.evaluateSeedValidity)

            case .suggestedWordTapped(let word):
                if let index = state.selectedIndex {
                    state.words[index] = word
                    if !state.isValidSeed && state.selectedIndex != 23 {
                        state.prevWords = state.words
                        state.nextIndex = index + 1 < 24 ? index + 1 : 0
                    }
                    return .send(.evaluateSeedValidity)
                }
                return .none
                
            case .helpSheetRequested:
                state.isHelpSheetPresented.toggle()
                return .none

            case .evaluateSeedValidity:
                do {
                    try mnemonic.isValid(state.words.joined(separator: " "))
                    state.isValidSeed = true
                    state.isKeyboardVisible = false
                } catch {
                    state.isValidSeed = false
                    if let index = state.selectedIndex {
                        let prefix = state.words[index]
                        if let first = state.suggestedWords.first, first == prefix && !state.isValidSeed && state.suggestedWords.count == 1 {
                            state.prevWords = state.words
                            state.nextIndex = index + 1 < 24 ? index + 1 : 0
                        }
                    }
                }
                return .none
                
            case .updateKeyboardFlag(let value):
                state.isKeyboardVisible = value
                return .none
                
#if DEBUG
            case .debugPasteSeed:
                do {
                    var testSeed = ""
                    if let testSeedPK = PartnerKeys.testSeed {
                        testSeed = testSeedPK
                    }
                    let seedToPaste = pasteboard.getString()?.data ?? testSeed
                    try mnemonic.isValid(seedToPaste)
                    state.isValidSeed = true
                    state.isKeyboardVisible = false
                    state.words = seedToPaste.components(separatedBy: " ")
                } catch {
                    state.isValidSeed = false
                    if let testSeedPK = PartnerKeys.testSeed {
                        state.isValidSeed = true
                        state.isKeyboardVisible = false
                        state.words = testSeedPK.components(separatedBy: " ")
                    }
                }
                return .none
#endif

            default: return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

@Reducer
struct OnboardingIdentityDerivation {
    @ObservableState
    struct State: Equatable {
        var hasReportedReady = false
        var messagingCancelId = UUID()
        var messagingState = ZappMessagingState(phase: .initializing)

        var errorCode: String? {
            if case let .failed(code) = messagingState.phase {
                return code
            }
            return messagingState.identityErrorCode
        }

        static let initial = State()
    }

    enum Action: Equatable {
        case identityReady
        case messagingStateChanged(ZappMessagingState)
        case onAppear
        case onDisappear
        case retryTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.zappMessaging) var zappMessaging

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .merge(
                    .send(.messagingStateChanged(zappMessaging.latestState())),
                    .publisher {
                        zappMessaging.stateStream()
                            .throttle(for: .seconds(0.2), scheduler: mainQueue, latest: true)
                            .map(Action.messagingStateChanged)
                    }
                    .cancellable(id: state.messagingCancelId, cancelInFlight: true)
                )

            case .onDisappear:
                return .cancel(id: state.messagingCancelId)

            case let .messagingStateChanged(messagingState):
                state.messagingState = messagingState
                guard
                    !state.hasReportedReady,
                    messagingState.phase == .ready,
                    messagingState.identity != nil
                else {
                    return .none
                }
                state.hasReportedReady = true
                return .send(.identityReady)

            case .identityReady:
                return .none

            case .retryTapped:
                zappMessaging.retryIdentityDerivation()
                return .none
            }
        }
    }
}

@Reducer
struct OnboardingSeedBackup {
    enum Kind: Equatable {
        /// Create path: back up the phrase of the wallet just made.
        case backup
        /// Restore path: Android's `SEED_CONFIRM`, the phrase just entered shown back.
        case confirm
    }

    @ObservableState
    struct State: Equatable {
        var kind = Kind.backup
        var errorMessage: String?
        var isConfirmed = false
        var isLoading = false
        var isRevealed = false
        var words: [RedactableString] = []

        /// The reveal was refused because the screen was ALREADY being recorded when it was
        /// asked for — the case `capturedDidChange` cannot see, since it only fires on a change.
        var isBlockedByScreenCapture = false

        static let initial = State()
        static let confirm = State(kind: .confirm)
    }

    enum Action: Equatable {
        case confirmationTapped
        case continueTapped
        case hideSensitiveContent
        case revealTapped
        case seedLoadFailed(ZcashError)
        case seedLoaded([RedactableString])
    }

    @Dependency(\.screenCapture) var screenCapture
    @Dependency(\.walletStorage) var walletStorage

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .confirmationTapped:
                guard state.isRevealed else { return .none }
                state.isConfirmed.toggle()
                return .none

            case .continueTapped:
                guard state.isRevealed, state.isConfirmed else { return .none }
                state.words.removeAll(keepingCapacity: false)
                state.isRevealed = false
                state.isConfirmed = false
                return .none

            case .hideSensitiveContent:
                state.words.removeAll(keepingCapacity: false)
                state.isRevealed = false
                state.isConfirmed = false
                state.isLoading = false
                return .none

            case .revealTapped:
                state.errorMessage = nil
                state.isBlockedByScreenCapture = false

                // A recording already in flight produces no `capturedDidChange`, so the phrase
                // has to be refused here rather than hidden a moment after it is on screen.
                guard !screenCapture.isCaptured() else {
                    state.isBlockedByScreenCapture = true
                    return .none
                }

                state.isLoading = true
                return .run { send in
                    do {
                        let storedWallet = try walletStorage.exportWallet()
                        let words = storedWallet.seedPhrase.value()
                            .split(separator: " ")
                            .map { RedactableString(String($0)) }
                        await send(.seedLoaded(words))
                    } catch {
                        await send(.seedLoadFailed(error.toZcashError()))
                    }
                }

            case let .seedLoadFailed(error):
                state.errorMessage = error.detailedMessage
                state.isLoading = false
                state.isRevealed = false
                state.words.removeAll(keepingCapacity: false)
                return .none

            case let .seedLoaded(words):
                state.words = words
                state.isLoading = false
                state.isRevealed = true
                return .none
            }
        }
    }
}

@Reducer
struct OnboardingMessagingIntro {
    @ObservableState
    struct State: Equatable {
        static let initial = State()
    }

    enum Action: Equatable {
        case continueTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .continueTapped:
                return .none
            }
        }
    }
}

@Reducer
struct OnboardingDone {
    enum Mode: Equatable {
        case biometric
        case pin
    }

    @ObservableState
    struct State: Equatable {
        var mode: Mode

        init(mode: Mode) {
            self.mode = mode
        }
    }

    enum Action: Equatable {
        case enterTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .enterTapped:
                return .none
            }
        }
    }
}

// MARK: Alerts

extension AlertState where Action == RestoreWalletCoordFlow.Action {
    static func cantCreateNewWallet(_ error: ZcashError) -> AlertState {
        AlertState {
            TextState(String(localizable: .rootInitializationAlertFailedTitle))
        } message: {
            TextState(String(localizable: .rootInitializationAlertCantCreateNewWalletMessage(error.detailedMessage)))
        }
    }

    static func cantMarkPhraseBackedUp(_ error: ZcashError) -> AlertState {
        AlertState {
            TextState(String(localizable: .rootInitializationAlertFailedTitle))
        } message: {
            TextState(String(localizable: .onboardingSeedConfirmationFailed(error.detailedMessage)))
        }
    }
}
