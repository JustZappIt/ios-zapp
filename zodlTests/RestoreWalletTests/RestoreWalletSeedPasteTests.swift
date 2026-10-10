import ComposableArchitecture
import Testing
@testable import zodl_internal

/// Pasting a backed-up phrase is the common way to restore, and a paste arrives as one text change
/// on whichever field the user long-pressed. These pin down how that text is split and where the
/// words land, on the Zapp restore flow's seed entry (both restore entries open it).
@Suite(.serialized) @MainActor struct RestoreWalletSeedPasteTests {
    private static let wordlist = ["abandon", "ability", "able", "about", "art"]

    @Test func whitespaceCommasAndNumberingAllSeparatePastedWords() {
        #expect(
            ZappRestoreSeedEntry.splitPastedSeedWords("abandon ability\table\nabout")
                == ["abandon", "ability", "able", "about"]
        )
        #expect(
            ZappRestoreSeedEntry.splitPastedSeedWords("abandon, ability; able") == ["abandon", "ability", "able"]
        )
        #expect(
            ZappRestoreSeedEntry.splitPastedSeedWords("1. abandon 2) ability 3 able") == ["abandon", "ability", "able"]
        )
        #expect(ZappRestoreSeedEntry.splitPastedSeedWords("  Abandon   ABILITY  ") == ["abandon", "ability"])
        #expect(ZappRestoreSeedEntry.splitPastedSeedWords("   ").isEmpty)
    }

    @Test func aWholePhraseFillsTheGridFromTheFirstFieldWhereverItIsPasted() {
        let current = Array(repeating: "", count: 24)
        let words = (1...24).map { "w\($0)" }

        #expect(ZappRestoreSeedEntry.placePastedSeedWords(current, at: 0, words: words) == words)
        #expect(ZappRestoreSeedEntry.placePastedSeedWords(current, at: 17, words: words) == words)
        // Anything beyond the grid is dropped rather than wrapped around.
        #expect(ZappRestoreSeedEntry.placePastedSeedWords(current, at: 5, words: words + ["extra"]) == words)
    }

    @Test func aPartialPhraseLandsOnTheFocusedFieldAndStopsAtTheLastOne() {
        let current = (0..<24).map { "old\($0)" }

        let fromMiddle = ZappRestoreSeedEntry.placePastedSeedWords(current, at: 3, words: ["a", "b", "c"])
        #expect(Array(fromMiddle[2..<7]) == ["old2", "a", "b", "c", "old6"])

        let nearEnd = ZappRestoreSeedEntry.placePastedSeedWords(current, at: 22, words: ["a", "b", "c"])
        #expect(Array(nearEnd[21..<24]) == ["old21", "a", "b"])
    }

    @Test func pastingAValidPhraseIntoAFieldSpreadsItOverAll24() {
        let phrase = Array(repeating: "abandon", count: 23) + ["art"]
        let store = makeStore(validPhrase: phrase)
        store.send(.selectedIndex(5))

        store.send(.binding(.set(\.words, pasted(phrase.joined(separator: " "), into: 5))))

        #expect(store.state.words == phrase)
        #expect(store.state.wordsValidity == Array(repeating: true, count: 24))
        #expect(store.state.isValidSeed)
    }

    /// Picking the suggestion for a flagged word clears the flag.
    @Test func pickingASuggestionClearsAPastedWordsFlag() {
        var phrase = Array(repeating: "abandon", count: 23) + ["art"]
        phrase[7] = "aban"
        let store = makeStore(validPhrase: [])
        store.send(.selectedIndex(0))
        store.send(.binding(.set(\.words, pasted(phrase.joined(separator: " "), into: 0))))
        store.send(.selectedIndex(7))
        #expect(!store.state.wordsValidity[7])

        store.send(.suggestedWordTapped("abandon"))

        #expect(store.state.words[7] == "abandon")
        #expect(store.state.wordsValidity[7])
    }

    @Test func pastingAPhraseWithATypoSpreadsItAndMovesFocusToTheBadWord() {
        var phrase = Array(repeating: "abandon", count: 23) + ["art"]
        phrase[7] = "abandn"
        let store = makeStore(validPhrase: [])
        store.send(.selectedIndex(0))

        store.send(.binding(.set(\.words, pasted(phrase.joined(separator: "\n"), into: 0))))

        #expect(store.state.words == phrase)
        #expect(store.state.wordsValidity.indices.filter { !store.state.wordsValidity[$0] } == [7])
        #expect(store.state.nextIndex == 7)
        #expect(!store.state.isValidSeed)
    }

    @Test func focusingAnIncompletePastedWordKeepsItsInvalidVerdict() {
        var phrase = Array(repeating: "abandon", count: 23) + ["art"]
        phrase[7] = "aban"
        let store = makeStore(validPhrase: [])
        store.send(.selectedIndex(0))

        store.send(.binding(.set(\.words, pasted(phrase.joined(separator: " "), into: 0))))
        #expect(store.state.nextIndex == 7)
        #expect(!store.state.wordsValidity[7])

        // The view sends this when the nextIndex change moves focus to the bad word.
        store.send(.selectedIndex(7))

        #expect(store.state.suggestedWords == ["abandon"])
        #expect(!store.state.wordsValidity[7])
        #expect(!store.state.isValidSeed)
    }

    @Test func aPartialPasteMovesFocusToTheFirstEmptyFieldAfterIt() {
        let store = makeStore(validPhrase: [])
        store.send(.selectedIndex(2))

        store.send(.binding(.set(\.words, pasted("abandon ability able", into: 2))))

        #expect(Array(store.state.words[0..<6]) == ["", "", "abandon", "ability", "able", ""])
        #expect(store.state.nextIndex == 5)
        #expect(store.state.wordsValidity == Array(repeating: true, count: 24))
    }

    @Test func aSinglePastedWordBehavesLikeTyping() {
        let store = makeStore(validPhrase: [])
        store.send(.selectedIndex(4))

        store.send(.binding(.set(\.words, pasted("aban", into: 4))))

        #expect(store.state.words[4] == "aban")
        #expect(store.state.words.filter { !$0.isEmpty }.count == 1)
        #expect(store.state.suggestedWords == ["abandon"])
    }

    private func pasted(_ text: String, into index: Int) -> [String] {
        var words = Array(repeating: "", count: 24)
        words[index] = text
        return words
    }

    private func makeStore(validPhrase: [String]) -> StoreOf<ZappRestoreSeedEntry> {
        Store(initialState: ZappRestoreSeedEntry.State.initial) { ZappRestoreSeedEntry() } withDependencies: {
            $0.mnemonic = .noOp
            $0.mnemonic.suggestWords = { prefix in Self.wordlist.filter { $0.hasPrefix(prefix) } }
            $0.mnemonic.isValid = { phrase in
                if phrase != validPhrase.joined(separator: " ") { throw InvalidPhrase() }
            }
            $0.walletStorage = .noOp
            $0.continuousClock = ImmediateClock()
        }
    }

    private struct InvalidPhrase: Error {}
}
