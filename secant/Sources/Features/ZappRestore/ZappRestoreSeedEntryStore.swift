//
//  ZappRestoreSeedEntryStore.swift
//  Zapp
//
//  Step 1 of the Zapp restore flow (Android's `RestoreStep.SEED_ENTRY`, `ZappRestoreFlowVM`'s seed
//  half). The word handling is the upstream restore screen's, which this step replaces, plus the
//  paste handling PR #70 adds to it: a pasted phrase is spread across the 24 fields.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ZappRestoreSeedEntry {
    static let wordCount = 24

    @ObservableState
    struct State: Equatable {
        var isValidSeed = false
        var nextIndex: Int?
        var prevWords: [String] = Array(repeating: "", count: ZappRestoreSeedEntry.wordCount)
        var selectedIndex: Int?
        var suggestedWords: [String] = []
        var words: [String] = Array(repeating: "", count: ZappRestoreSeedEntry.wordCount)
        var wordsValidity: [Bool] = Array(repeating: true, count: ZappRestoreSeedEntry.wordCount)

        var seedPhrase: String { words.joined(separator: " ") }

        static let initial = State()
    }

    enum Action: BindableAction, Equatable {
        case backTapped
        case binding(BindingAction<State>)
        case helpTapped
        case nextTapped
        case selectedIndex(Int?)
        case suggestedWordTapped(String)
        #if DEBUG
        case debugPasteSeed
        #endif
    }

    @Dependency(\.mnemonic) var mnemonic
    @Dependency(\.pasteboard) var pasteboard

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding(\.words):
                let changedIndices = state.words.indices.filter { state.words[$0] != state.prevWords[$0] }
                state.prevWords = state.words

                guard let index = changedIndices.first else {
                    return .none
                }
                let word = state.words[index]

                // A field only ever holds one word, so several words arriving at once is a paste
                // of (part of) a phrase: spread it across the grid instead of leaving it crammed
                // into one box.
                let pasted = Self.splitPastedSeedWords(word)
                if pasted.count > 1 {
                    let before = state.words
                    state.words = Self.placePastedSeedWords(before, at: index, words: pasted)
                    state.prevWords = state.words
                    state.suggestedWords = []
                    // Only the slots the paste wrote to are re-judged; a word the user is still
                    // typing elsewhere keeps its prefix-based verdict.
                    for i in state.words.indices where i == index || state.words[i] != before[i] {
                        state.wordsValidity[i] = Self.isPastedWordValid(state.words[i], suggest: mnemonic.suggestWords)
                    }
                    // Carry on from the pasted block: the first slot from its start that is still
                    // empty or wrong, so a typo inside the paste gets focus too.
                    let start = pasted.count >= state.words.count ? 0 : index
                    state.nextIndex = state.words.indices.first {
                        $0 >= start && (state.words[$0].isEmpty || !state.wordsValidity[$0])
                    }
                    evaluateSeedValidity(&state)
                    return .none
                }

                if word.hasSuffix(" ") {
                    state.words[index] = word.trimmingCharacters(in: .whitespaces)
                    state.prevWords = state.words
                    return .send(.suggestedWordTapped(state.words[index]))
                }
                requestSuggestions(&state, at: index, hasIndexChanged: false)
                return .none

            case .binding:
                return .none

            case .selectedIndex(let index):
                state.selectedIndex = index
                state.nextIndex = index
                if let index {
                    requestSuggestions(&state, at: index, hasIndexChanged: true)
                }
                return .none

            case .suggestedWordTapped(let word):
                guard let index = state.selectedIndex else {
                    return .none
                }
                state.words[index] = word
                if !state.isValidSeed && index != Self.wordCount - 1 {
                    state.prevWords = state.words
                    state.nextIndex = index + 1
                }
                evaluateSeedValidity(&state)
                return .none

            case .backTapped, .helpTapped:
                return .none

            case .nextTapped:
                // The coordinator advances on this; it only gets here with a valid phrase.
                return .none

            #if DEBUG
            case .debugPasteSeed:
                let seedToPaste = pasteboard.getString()?.data ?? PartnerKeys.testSeed ?? ""
                let words = Self.splitPastedSeedWords(seedToPaste)
                guard words.count == Self.wordCount else {
                    return .none
                }
                state.words = words
                state.prevWords = words
                state.wordsValidity = Array(repeating: true, count: Self.wordCount)
                evaluateSeedValidity(&state)
                return .none
            #endif
            }
        }
    }

    private func requestSuggestions(_ state: inout State, at index: Int, hasIndexChanged: Bool) {
        let prefix = state.words[index]
        if prefix.isEmpty {
            state.suggestedWords = []
        } else {
            state.suggestedWords = mnemonic.suggestWords(prefix)
            // Focus moving onto a field doesn't change its word, so it keeps its verdict. A pasted
            // "aban" is flagged because a pasted word must be whole; re-judging it here as a prefix
            // of "abandon" cleared the flag on the one field that was wrong.
            if !hasIndexChanged {
                state.wordsValidity[index] = !state.suggestedWords.isEmpty
            }
        }
        // Landing on a field that already holds a complete word must not jump focus onward.
        if hasIndexChanged, state.suggestedWords == [prefix], !state.isValidSeed {
            return
        }
        evaluateSeedValidity(&state)
    }

    private func evaluateSeedValidity(_ state: inout State) {
        do {
            try mnemonic.isValid(state.seedPhrase)
            state.isValidSeed = true
            state.nextIndex = nil
        } catch {
            state.isValidSeed = false
            // A word typed out in full that matches exactly one wordlist entry moves on by itself.
            if let index = state.selectedIndex, state.suggestedWords == [state.words[index]] {
                state.prevWords = state.words
                state.nextIndex = index + 1 < Self.wordCount ? index + 1 : 0
            }
        }
    }
}

// MARK: - Pasted seed phrases

extension ZappRestoreSeedEntry {
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
