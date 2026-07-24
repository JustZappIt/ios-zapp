//
//  PINInputTests.swift
//  zodlTests
//

import Testing
@testable import zodl_internal

@Suite struct PINInputTests {
    @Test func acceptsSixDigitsAndIgnoresAdditionalInput() {
        var pin = ""

        for digit in 1 ... 6 {
            PINInput.apply(.digit(digit), to: &pin)
        }

        #expect(pin == "123456")
        #expect(PINInput.isComplete(pin))

        PINInput.apply(.digit(7), to: &pin)
        #expect(pin == "123456")
    }

    @Test func deleteRemovesTheLastDigit() {
        var pin = "123"

        PINInput.apply(.delete, to: &pin)

        #expect(pin == "12")
        #expect(!PINInput.isComplete(pin))
    }

    @Test func submissionRequiresMatchingConfirmation() {
        var pin = "123456"
        var firstPIN = ""

        var submission = PINInput.submit(pin: pin, firstPIN: firstPIN)
        #expect(submission.result == .confirmationRequired)
        pin = submission.pin
        firstPIN = submission.firstPIN
        #expect(pin.isEmpty)
        #expect(firstPIN == "123456")

        pin = "654321"
        submission = PINInput.submit(pin: pin, firstPIN: firstPIN)
        #expect(submission.result == .mismatch)
        pin = submission.pin
        firstPIN = submission.firstPIN
        #expect(pin.isEmpty)
        #expect(firstPIN.isEmpty)

        pin = "123456"
        submission = PINInput.submit(pin: pin, firstPIN: firstPIN)
        #expect(submission.result == .confirmationRequired)
        pin = submission.pin
        firstPIN = submission.firstPIN
        pin = "123456"
        submission = PINInput.submit(pin: pin, firstPIN: firstPIN)
        #expect(submission.result == .confirmed("123456"))
    }
}
