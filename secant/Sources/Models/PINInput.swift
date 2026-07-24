//
//  PINInput.swift
//  Zashi
//

enum PINKey: Equatable, Sendable {
    case delete
    case digit(Int)
}

enum PINSubmissionResult: Equatable, Sendable {
    case incomplete
    case confirmationRequired
    case confirmed(String)
    case mismatch
}

struct PINSubmission: Equatable, Sendable {
    let result: PINSubmissionResult
    let pin: String
    let firstPIN: String
}

enum PINInput {
    static let requiredLength = 6

    static func apply(_ key: PINKey, to value: inout String) {
        switch key {
        case .delete:
            if !value.isEmpty {
                value.removeLast()
            }
        case let .digit(digit):
            guard (0...9).contains(digit), value.count < requiredLength else {
                return
            }
            value.append(contentsOf: String(digit))
        }
    }

    static func isComplete(_ value: String) -> Bool {
        value.count == requiredLength
    }

    static func submit(pin: String, firstPIN: String) -> PINSubmission {
        guard isComplete(pin) else {
            return PINSubmission(result: .incomplete, pin: pin, firstPIN: firstPIN)
        }

        guard !firstPIN.isEmpty else {
            return PINSubmission(result: .confirmationRequired, pin: "", firstPIN: pin)
        }

        guard pin == firstPIN else {
            return PINSubmission(result: .mismatch, pin: "", firstPIN: "")
        }

        return PINSubmission(result: .confirmed(pin), pin: pin, firstPIN: firstPIN)
    }
}
