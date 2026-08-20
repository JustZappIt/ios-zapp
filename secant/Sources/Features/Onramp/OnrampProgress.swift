// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

enum OnrampVisibleStep: String, CaseIterable, Equatable, Sendable {
    case orderPlaced
    case merchantMatched
    case payMerchant
    case paymentConfirmed
    case receivingUsdc
    case usdcReceived
    case convertingToZec
    case zecReceived
}

struct OnrampProgressStep: Equatable, Sendable {
    let step: OnrampVisibleStep
    let status: ZappOfframpStepStatus
}

enum OnrampProgressMapper {
    static func map(
        status: OnrampStatusModel?,
        delivery: OnrampDeliveryModel? = nil,
        destination: OnrampDestinationModel = .base
    ) -> [OnrampProgressStep] {
        let steps = destination == .zcash
            ? OnrampVisibleStep.allCases
            : Array(OnrampVisibleStep.allCases.prefix(baseStepCount))
        let activeIndex = delivery.map(deliveryIndex) ?? status.map { statusIndex($0, destination: destination) } ?? 0
        let terminalFailure = status?.kind == .cancelled || status?.kind == .failed ||
            delivery?.kind == .failed || delivery?.kind == .refundedToBase

        return steps.enumerated().map { index, step in
            let state: ZappOfframpStepStatus
            if index < activeIndex {
                state = .completed
            } else if index == activeIndex, terminalFailure {
                state = .failed
            } else if index == activeIndex {
                state = .inProgress
            } else {
                state = .pending
            }
            return OnrampProgressStep(step: step, status: state)
        }
    }

    private static func statusIndex(_ status: OnrampStatusModel, destination: OnrampDestinationModel) -> Int {
        switch status.phase {
        case .placing: return index(.orderPlaced)
        case .awaitingMerchant: return index(.merchantMatched)
        case .awaitingPayment: return index(.payMerchant)
        case .confirmingPaid: return index(.paymentConfirmed)
        case .awaitingSettlement: return index(.receivingUsdc)
        case .completed: return destination == .zcash ? index(.convertingToZec) : baseStepCount
        case .expired:
            return status.failureCode == .orderExpired ? index(.payMerchant) : index(.merchantMatched)
        case .cancelled: return index(.merchantMatched)
        case .failed: return index(.orderPlaced)
        case .unknown: return index(.orderPlaced)
        }
    }

    /// Only a delivered swap advances past conversion. A refund remains on that row because
    /// marking it complete would claim a conversion that never happened.
    private static func deliveryIndex(_ delivery: OnrampDeliveryModel) -> Int {
        delivery.kind == .delivered ? OnrampVisibleStep.allCases.count : index(.convertingToZec)
    }

    private static func index(_ step: OnrampVisibleStep) -> Int {
        OnrampVisibleStep.allCases.firstIndex(of: step) ?? 0
    }

    private static let baseStepCount = index(.usdcReceived) + 1
}
