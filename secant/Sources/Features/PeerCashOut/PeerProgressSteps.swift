// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

/// Cash-out status to the rows the shared step list renders. A pure mapper so it can be tested
/// without a store, and so both the progress screen and its tests read one implementation.
///
/// Two rows are conditional, because a permanently pending row reads as something left undone:
/// funding appears only when it actually did something — which on iOS means it failed, since a
/// cash-out spends Base USDC the user already has — and withdrawal only once an unwind is under way.
enum PeerProgressSteps {
    static func build(from run: PeerRun?) -> [ZappOfframpStepItem] {
        let statuses = run?.statuses ?? []
        let latest = statuses.last
        let failure = latest?.failure
        let visible = PeerProgress.Step.displayed.filter { shows($0, statuses: statuses, failure: failure) }
        let pivot = pivotIndex(in: visible, statuses: statuses, failure: failure)

        return visible.enumerated().map { index, step in
            ZappOfframpStepItem(
                id: step.rawValue,
                label: label(for: step, latest: latest),
                detail: detail(for: step, latest: latest),
                status: status(index: index, pivot: pivot, isFailed: failure != nil, latest: latest)
            )
        }
    }

    private static func shows(_ step: PeerProgress.Step, statuses: [PeerProgress], failure: PeerFailure?) -> Bool {
        switch step {
        case .funding:
            return failure?.step == .funding
        case .withdrawing:
            let unwinding = statuses.contains { status in
                status.kind == .withdrawing || status.kind == .withdrawn
            }
            return unwinding || failure?.step == .withdrawing
        default:
            return true
        }
    }

    /// Where the list is "up to", and never behind the furthest row the attempt actually reached.
    ///
    /// A step this build does not recognise decodes as `initialization`, which has no row and would
    /// otherwise pull the marker back to the first one — reporting a failure that happened after the
    /// escrow took the money as "we could not check your details".
    private static func pivotIndex(
        in visible: [PeerProgress.Step],
        statuses: [PeerProgress],
        failure: PeerFailure?
    ) -> Int? {
        guard let step = failure?.step ?? statuses.last?.step else { return nil }
        let reached = statuses.compactMap { rowIndex(of: $0.step, in: visible) }.max()
        guard let index = rowIndex(of: step, in: visible) else { return reached ?? 0 }
        return max(index, reached ?? index)
    }

    /// The visible row a step belongs to: its own, or the next one still on screen when the step is
    /// hidden, so everything before it reads as done rather than the list resetting to pending. Nil
    /// for a step that precedes every row, which is the only thing `initialization` can mean.
    private static func rowIndex(of step: PeerProgress.Step, in visible: [PeerProgress.Step]) -> Int? {
        if let index = visible.firstIndex(of: step) { return index }
        guard let canonical = PeerProgress.Step.displayed.firstIndex(of: step) else { return nil }
        let next = PeerProgress.Step.displayed[canonical...].dropFirst().first { visible.contains($0) }
        return next.flatMap { visible.firstIndex(of: $0) } ?? visible.count
    }

    private static func status(
        index: Int,
        pivot: Int?,
        isFailed: Bool,
        latest: PeerProgress?
    ) -> ZappOfframpStepStatus {
        // A sold-out or withdrawn order is finished end to end: every row is done, including the
        // waiting one, which would otherwise still read "waiting for a buyer" after the sale.
        if latest?.kind == .withdrawn || latest?.order?.phase == .sold { return .completed }
        guard let pivot else { return .pending }
        if index < pivot { return .completed }
        if index > pivot { return .pending }
        return isFailed ? .failed : .inProgress
    }

    private static func label(for step: PeerProgress.Step, latest: PeerProgress?) -> String {
        if step == .awaitingBuyer, latest?.order?.phase == .sold {
            return String(localizable: .peerStepSold)
        }
        switch step {
        case .initialization: return String(localizable: .peerStepInitialization)
        case .validatingPayee: return String(localizable: .peerStepValidatingPayee)
        case .funding: return String(localizable: .peerStepFunding)
        case .approvingUsdc: return String(localizable: .peerStepApprovingUsdc)
        case .creatingDeposit: return String(localizable: .peerStepCreatingDeposit)
        case .awaitingBuyer: return String(localizable: .peerStepAwaitingBuyer)
        case .settling: return String(localizable: .peerStepSettling)
        case .withdrawing: return String(localizable: .peerStepWithdrawing)
        }
    }

    private static func detail(for step: PeerProgress.Step, latest: PeerProgress?) -> String? {
        guard let order = latest?.order else { return nil }
        switch step {
        case .awaitingBuyer where order.sold.isPositive:
            return String(localizable: .peerStepDetailPartialFill(order.sold.display, order.gross.display))
        case .settling:
            guard
                let leg = order.buyerLegs.first(where: \.holdsFunds),
                let amount = leg.paymentAmount,
                let currency = leg.paymentCurrencyCode
            else { return nil }
            return String(localizable: .peerStepDetailBuyerOwes(amount, currency))
        default:
            return nil
        }
    }
}
