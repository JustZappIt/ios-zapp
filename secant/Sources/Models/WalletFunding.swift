//
//  WalletFunding.swift
//  Zapp
//
//  Android's `Funding` (`ObserveFundingUseCase`): whether a money flow has anything to spend.
//  Send, Swap (ZEC out), Gift, Pay a merchant and Add funds to Base read it to show "Add ZEC" up
//  front instead of letting someone fill a form they cannot pay for.
//

import Foundation
import ZcashLightClientKit

enum WalletFunding: Equatable {
    /// Not known yet: syncing, restoring, or no balance read. The flow shows its usual form.
    case unknown
    /// Fully synced and still holding nothing.
    case empty
    case funded

    /// Android's `nextZecFunding`. `.empty` is claimed only for a synced, non-restoring wallet
    /// whose total (every pool, pending included) is zero. A synced wallet starts a catch-up sync
    /// on every new block, so once `.empty` has been seen it holds through those instead of the
    /// panel blinking off each time.
    static func next(
        previous: WalletFunding,
        total: Zatoshi?,
        isUpToDate: Bool,
        isRestoring: Bool
    ) -> WalletFunding {
        guard let total else { return .unknown }

        if total.amount > 0 { return .funded }
        if isRestoring { return .unknown }
        if isUpToDate { return .empty }
        if previous == .empty { return .empty }

        return .unknown
    }

    /// Android's `withBaseUsdc`, for Pay a merchant, which can also pay from USDC on Base.
    /// `baseUsdc` is nil until the Base balance has been read; an unread balance never counts as
    /// empty.
    func withBaseUsdc(_ baseUsdc: Decimal?) -> WalletFunding {
        if self == .funded { return .funded }
        guard let baseUsdc else { return .unknown }
        if baseUsdc > 0 { return .funded }

        return self == .empty ? .empty : .unknown
    }
}

extension AccountBalance {
    /// Everything the account holds: every shielded pool (spendable, pending and locked), the
    /// transparent balance and value awaiting resolution. Android's `totalBalance`.
    var fundingTotal: Zatoshi {
        shieldedTotal() + unshielded + awaitingResolution
    }
}
