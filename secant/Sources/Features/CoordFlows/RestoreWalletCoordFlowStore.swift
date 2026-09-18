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

    @Reducer
    enum Path {
        case appLockSetup(AppLockSetup)
        case chatUsername(ChatUsernameEntry)
        case done(OnboardingDone)
        case estimateBirthdaysDate(WalletBirthday)
        case estimatedBirthday(WalletBirthday)
        case identityDerivation(OnboardingIdentityDerivation)
        case messagingIntro(OnboardingMessagingIntro)
        case recoverySeedPhraseEntry(RestoreWalletCoordFlow)
        case restoreInfo(RestoreInfo)
        case seedBackup(OnboardingSeedBackup)
        case walletBirthday(WalletBirthday)
    }
    
    @ObservableState
    struct State {
        @Presents var alert: AlertState<Action>?
        var birthday: BlockHeight? = nil
        var isHelpSheetPresented = false
        var isKeyboardVisible = false
        var isValidSeed = false
        var isTorOn = false
        var isTorSheetPresented = false
        var landingForward = true
        var landingStep = LandingStep.welcome
        var walletCreationError: String?
        var nextIndex: Int?
        var path = StackState<Path.State>()
        var prevWords: [String] = Array(repeating: "", count: 24)
        var selectedIndex: Int?
        var suggestedWords: [String] = []
        var words: [String] = Array(repeating: "", count: 24)
        var wordsValidity: [Bool] = Array(repeating: true, count: 24)

        var isImportingWallet: Bool {
            for element in path {
                if element.is(\.recoverySeedPhraseEntry) {
                    return true
                }
            }
            
            return false
        }
        
        init() { }
    }

    enum Action: BindableAction {
        case alert(PresentationAction<Action>)
        case binding(BindingAction<RestoreWalletCoordFlow.State>)
        case evaluateSeedValidity
        case failedToRecover(ZcashError)
        case helpSheetRequested
        case landingBackTapped
        case landingContinueTapped
        case landingGetStartedTapped
        case nextTapped
        case path(StackActionOf<Path>)
        case resolveRestore
        case resolveRestoreRequested
        case resolveRestoreTapped
        case restoreCancelTapped
        case selectedIndex(Int?)
        case successfullyRecovered
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

                    // A field only ever holds one word, so several words arriving at once is a
                    // paste of (part of) a phrase: spread it across the grid instead of leaving
                    // it crammed into one box.
                    let pasted = Self.splitPastedSeedWords(word)
                    if pasted.count > 1 {
                        let before = state.words
                        state.words = Self.placePastedSeedWords(before, at: index, words: pasted)
                        state.prevWords = state.words
                        state.suggestedWords = []
                        // Only the slots the paste wrote to are re-judged; a word the user is
                        // still typing elsewhere keeps its prefix-based verdict.
                        for i in state.words.indices where i == index || state.words[i] != before[i] {
                            state.wordsValidity[i] = Self.isPastedWordValid(state.words[i], suggest: mnemonic.suggestWords)
                        }
                        // Carry on from the pasted block: the first slot from its start that is
                        // still empty or wrong, so a typo inside the paste gets focus too.
                        let start = pasted.count >= state.words.count ? 0 : index
                        state.nextIndex = state.words.indices.first {
                            $0 >= start && (state.words[$0].isEmpty || !state.wordsValidity[$0])
                        }
                        return .send(.evaluateSeedValidity)
                    }

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

// MARK: - Pasted seed phrases

extension RestoreWalletCoordFlow {
    /// Break pasted text into candidate seed words: whitespace, commas and semicolons all separate
    /// words, and tokens with no letters (the "1." or "12)" of a numbered backup) are dropped.
    /// BIP-39 words are lowercase, so the case of the paste is not preserved.
    static func splitPastedSeedWords(_ text: String) -> [String] {
        text
            .components(separatedBy: pastedSeedSeparators)
            .map { $0.lowercased() }
            .filter { $0.contains { $0.isLetter } }
    }

    /// Lay `words` over `current`, starting at `index`; a paste that holds a whole phrase always
    /// starts at the first field so pasting it into any box fills the grid. Words that would spill
    /// past the last field are dropped.
    static func placePastedSeedWords(_ current: [String], at index: Int, words: [String]) -> [String] {
        guard !current.isEmpty else { return current }
        let start = words.count >= current.count ? 0 : min(max(index, 0), current.count - 1)
        var result = current
        for (offset, word) in words.prefix(current.count - start).enumerated() {
            result[start + offset] = word
        }
        return result
    }

    /// Unlike a word being typed, a pasted word is complete, so it has to be an exact wordlist
    /// entry rather than a prefix of one. An empty slot is not flagged.
    static func isPastedWordValid(_ word: String, suggest: (String) -> [String]) -> Bool {
        word.isEmpty || suggest(word).contains(word)
    }

    private static let pastedSeedSeparators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
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
    @ObservableState
    struct State: Equatable {
        var errorMessage: String?
        var isConfirmed = false
        var isLoading = false
        var isRevealed = false
        var words: [RedactableString] = []

        /// The reveal was refused because the screen was ALREADY being recorded when it was
        /// asked for — the case `capturedDidChange` cannot see, since it only fires on a change.
        var isBlockedByScreenCapture = false

        static let initial = State()
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
