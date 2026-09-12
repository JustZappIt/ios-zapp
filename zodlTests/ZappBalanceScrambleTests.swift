import Testing
@testable import zodl_internal

@Suite
struct ZappBalanceScrambleTests {
    @Test
    func hidingPreservesFormattingAndEventuallyReplacesEveryDigit() {
        let value = "₦1,234.56"
        let first = ZappBalanceScramble.frame(value, index: 0, revealing: false)
        let last = ZappBalanceScramble.frame(value, index: .max, revealing: false)

        #expect(first == "₦%,234.56")
        let remainingDigits = last.filter { $0.isNumber }
        let characters = Array(last)
        #expect(remainingDigits.isEmpty)
        #expect(last.first == "₦")
        #expect(characters[2] == ",")
        #expect(characters[6] == ".")
    }

    @Test
    func revealingRestoresDigitsProgressively() {
        let value = "$12.34 ZEC"
        let first = ZappBalanceScramble.frame(value, index: 0, revealing: true)
        let middle = ZappBalanceScramble.frame(value, index: 4, revealing: true)
        let last = ZappBalanceScramble.frame(value, index: .max, revealing: true)

        let firstDigits = first.filter { $0.isNumber }
        #expect(firstDigits.isEmpty)
        #expect(middle.hasPrefix("$12."))
        #expect(middle.filter(\.isNumber).count == 2)
        #expect(last == value)
    }

    @Test
    func localizedDigitsAreMaskedAndFramesAreBounded() {
        let value = "١٢٣٫٤٥ ZEC"
        let hidden = ZappBalanceScramble.frame(value, index: 7, revealing: false)
        let remainingDigits = hidden.filter { $0.isNumber }
        #expect(remainingDigits.isEmpty)
        #expect(ZappBalanceScramble.frame(value, index: -10, revealing: true)
            == ZappBalanceScramble.frame(value, index: 0, revealing: true))
        #expect(ZappBalanceScramble.frame("*** ZEC", index: 2, revealing: false) == "*** ZEC")
    }
}
