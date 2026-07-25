//
//  SharedStateKeys.swift
//
//
//  Created by Lukáš Korba on 05-09-2024
//

import Foundation

public extension String {
    static let exchangeRate = "sharedStateKey_exchangeRate"
    static let sensitiveContent = "udHideBalances"
    static let walletStatus = "sharedStateKey_walletStatus"
    static let flexaAccountId = "sharedStateKey_flexaAccountId"
    static let addressBookContacts = "sharedStateKey_addressBookContacts"
    static let chatContacts = "sharedStateKey_chatContacts"
    static let chatTermsAccepted = "sharedStateKey_chatTermsAccepted"
    static let toast = "sharedStateKey_toast"
    static let featureFlags = "sharedStateKey_featureFlags"
    static let lastAuthenticationTimestamp = "sharedStateKey_lastAuthenticationTimestamp"
    static let appAuthenticationMethod = "sharedStateKey_appAuthenticationMethod"
    static let failedPINAttempts = "sharedStateKey_failedPINAttempts"
    static let pinLockoutEndTimestamp = "sharedStateKey_pinLockoutEndTimestamp"
    static let walletAccounts = "sharedStateKey_walletAccounts"
    static let selectedWalletAccount = "sharedStateKey_selectedWalletAccount"
    static let zashiWalletAccount = "sharedStateKey_zashiWalletAccount"
    static let transactions = "sharedStateKey_transactions"
    static let transactionMemos = "sharedStateKey_transactionMemos"
    static let swapAssets = "sharedStateKey_swapAssets"
    static let swapAssetsCatalog = "sharedStateKey_swapAssetsCatalog"
    static let zappFiatQuote = "sharedStateKey_zappFiatQuote"
    static let swapAPIAccess = "sharedStateKey_swapAPIAccess"
    static let hasSeenHowToVote = "sharedStateKey_hasSeenHowToVote"
    static let hasSeenHowToVoteKeystone = "sharedStateKey_hasSeenHowToVoteKeystone"
    static let votingConfigOverrideURL = "sharedStateKey_votingConfigOverrideURL"
    static let votingCustomChains = "sharedStateKey_votingCustomChains"
}
