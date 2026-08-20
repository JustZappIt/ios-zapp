// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation

extension Onramp {
    enum Action: Equatable {
        case onAppear
        case loaded(OnrampLimitsModel, String, OnrampCheckpointModel?, Bool, OfframpAccountModel?)
        case loadFailed(String)
        case resumeLoadedCheckpoint(OnrampCheckpointModel)
        case amountChanged(String)
        case destinationSelected(OnrampDestinationModel)
        case continueTapped
        case quoteLoaded(OnrampQuoteModel)
        case quoteFailed(String)
        case zecEstimateLoaded(OnrampZecEstimateModel)
        case zecEstimateFailed(String)
        case quoteTicked(Int)
        case quoteExpired
        case statusReceived(OnrampStatusModel)
        case statusStreamFinished
        case statusOperationFailed(String)
        case authenticationCancelled
        case paymentAmountChecked(Bool)
        case paidTapped
        case paidConfirmed
        case paidDismissed
        case cancelTapped
        case retryTapped
        case doneTapped
        case deliveryStatusReceived(OnrampDeliveryModel)
        case deliveryFailed(OnrampDeliveryModel)
        case deliveryStreamFinished
        case deliveryActionTapped
        case copyAccountAddressTapped
        case copyPaymentAddressTapped
        case sendBaseBalanceToZecTapped
        case baseRefundPreviewLoaded(OfframpBridgePreview)
        case sendBaseBalanceToZecConfirmed
        case sendBaseBalanceToZecDismissed
        case baseBalanceSent
        case baseBalanceSendFailed(String)
        case baseBalanceSendCancelled
        case transactionURLLoaded(URL?)
        case paymentTicked(Int)
        case paymentWindowExpired(String)
        case recheckOrderTapped
        case infoTapped
        case infoDismissed
        case backTapped
        case cancelAll
        case delegate(Delegate)

        enum Delegate: Equatable { case close }
    }
}
