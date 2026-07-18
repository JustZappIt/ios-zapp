//
//  TransactionDetailsView.swift
//  Zashi
//
//  Created by Lukáš Korba on 01-08-2024
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct TransactionDetailsView: View {
    enum Constants {
        static let horizontalPadding: CGFloat = 18
        static let iconBox: CGFloat = 48
        static let iconSize: CGFloat = 24
        static let rowVerticalPadding: CGFloat = 14
        static let valueIconSize: CGFloat = 18
    }

    /// The detail rows are derived here rather than in the reducer: they are a pure projection of
    /// state the reducer already holds, and a fork-owned view is free where a reducer change is a
    /// merge tax.
    enum DetailValue {
        case address(String)
        case loading
        case status(SwapBadge.Status)
        case text(String)
    }

    struct DetailItem: Identifiable {
        let id: String
        let title: String
        let value: DetailValue
        var icon: Image?
        var action: TransactionDetails.Action?
    }

    @Environment(\.colorScheme) var colorScheme

    @FocusState var isAnnotationFocused

    @Perception.Bindable var store: StoreOf<TransactionDetails>
    let tokenName: String

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false
    @Shared(.inMemory(.exchangeRate)) var currencyConversion: CurrencyConversion? = nil

    init(store: StoreOf<TransactionDetails>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: detailsTitle) {
                    HStack(spacing: 12) {
                        hideBalancesButton()
                        bookmarkButton()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.transaction.isNonZcashActivity {
                            headerViewSwapToZec()
                        } else {
                            headerView()
                        }

                        if store.isSwap {
                            swapAssetsView()
                                .padding(.bottom, 12)
                        }

                        if store.transaction.isSentTransaction {
                            transactionDetailsList()
                                .padding(.bottom, store.isSwap ? 0 : 20)
                                .padding(.horizontal, Constants.horizontalPadding)

                            if store.areMessagesResolved && !store.transaction.isShieldingTransaction {
                                if !store.memos.isEmpty {
                                    messageViews()
                                        .padding(.horizontal, Constants.horizontalPadding)
                                } else if !store.transaction.isTransparentRecipient {
                                    noMessageView()
                                        .padding(.bottom, 20)
                                        .padding(.horizontal, Constants.horizontalPadding)
                                }
                            }
                        } else {
                            if store.areMessagesResolved {
                                if !store.transaction.isTransparentRecipient && !store.transaction.isShieldingTransaction && !store.transaction.hasTransparentOutputs {
                                    if store.memos.isEmpty {
                                        noMessageView()
                                            .padding(.bottom, 20)
                                            .padding(.horizontal, Constants.horizontalPadding)
                                    } else {
                                        messageViews()
                                            .padding(.bottom, 20)
                                            .padding(.horizontal, Constants.horizontalPadding)
                                    }
                                }
                            }

                            transactionDetailsList()
                                .padding(.horizontal, Constants.horizontalPadding)
                        }

                        if store.isSwap {
                            if store.isProcessingTooLong {
                                swapProcessingInfoView()
                            } else if store.swapStatus == .refunded {
                                swapRefundInfoView()
                            } else if store.swapStatus == .incompleteDeposit {
                                swapIncompleteInfoView()
                            } else if store.swapStatus == .expired {
                                swapExpiredOrFailedInfoView(failed: false)
                            } else if store.swapStatus == .failed {
                                swapExpiredOrFailedInfoView(failed: true)
                            }
                        }
                    }
                }

                footerInfo()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
            .zashiSheet(isPresented: $store.isReportSwapSheetEnabled) {
                // A sheet's content closure escapes: reads inside it only register with TCA's
                // observation system under their own WithPerceptionTracking.
                WithPerceptionTracking {
                    reportSwapSheetContent()
                }
            }
            .zashiSheet(isPresented: $store.annotationRequest) {
                WithPerceptionTracking {
                    annotationContent(store.isEditMode)
                }
            }
            .navigationBarHidden(true)
            .zashiBack(
                hasPrimaryAction: hasInlineFooterActions,
                primaryAction: { footerActions() },
                customDismiss: { store.send(.closeDetailTapped) }
            )
        }
    }

    var detailsTitle: String {
        store.transaction.isSwapToZec
        ? String(localizable: .swapToZecSwapDetails)
        : String(localizable: .transactionHistoryDetails)
    }

    // Info-only footer content; button actions move into the bottom bar via `footerActions`.
    @ViewBuilder func footerInfo() -> some View {
        if store.footerState == .providerFailure {
            if let retryFailure = store.swapAssetFailedWithRetry {
                VStack(spacing: 8) {
                    Asset.Assets.infoOutline.image
                        .zImage(size: 16, style: ZappColors.danger)

                    Text(retryFailure
                         ? String(localizable: .swapAndPayFailureRetryTitle)
                         : String(localizable: .swapAndPayFailureLaterTitle)
                    )
                    .zappFont(.rowTitle, style: ZappColors.danger)

                    Text(retryFailure
                         ? String(localizable: .swapAndPayFailureRetryDesc)
                         : String(localizable: .swapAndPayFailureLaterDesc)
                    )
                    .zappFont(.body, style: ZappColors.danger)
                    .multilineTextAlignment(.center)

                    if retryFailure {
                        ZappButton(
                            title: String(localizable: .swapAndPayFailureTryAgain),
                            variant: .danger
                        ) {
                            store.send(.trySwapsAssetsAgainTapped)
                        }
                        .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.bottom, 16)
            }
        } else if store.footerState == .depositInfo {
            HStack(alignment: .top, spacing: 12) {
                Asset.Assets.infoOutline.image
                    .zImage(size: 16, style: ZappColors.textMuted)

                Text(localizable: .depositsInfo)
                    .zappFont(.caption, style: ZappColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, 16)
        }

        if let supportData = store.supportData {
            UIMailDialogView(
                supportData: supportData,
                completion: {
                    store.send(.sendSupportMailFinished)
                }
            )
            // UIMailDialogView only wraps MFMailComposeViewController presentation
            // so frame is set to 0 to not break SwiftUI's layout
            .frame(width: 0, height: 0)
        }

        shareView()
    }

    // Buttons that share the bottom bar's row with the back button.
    @ViewBuilder func footerActions() -> some View {
        if store.footerState == .contactSupport {
            // footerState resolves to .contactSupport only for the failed/expired/refunded/stuck states.
            ZappButton(
                title: String(localizable: .reportSwapContact),
                variant: .secondary
            ) {
                store.send(.contactSupportTapped)
            }
        } else if store.footerState == .addNote {
            HStack(spacing: 12) {
                ZappButton(
                    title: store.annotation.isEmpty
                    ? String(localizable: .annotationAddArticle)
                    : String(localizable: .annotationEdit),
                    variant: .secondary
                ) {
                    store.send(.noteButtonTapped)
                }

                if store.transaction.isSentTransaction && !store.transaction.isShieldingTransaction && !store.isSwap {
                    if store.alias == nil {
                        ZappButton(title: String(localizable: .transactionHistorySaveAddress)) {
                            store.send(.saveAddressTapped)
                        }
                    } else {
                        ZappButton(title: String(localizable: .transactionHistorySendAgain)) {
                            store.send(.sendAgainTapped)
                        }
                    }
                }
            }
        }
    }

    var hasInlineFooterActions: Bool {
        store.footerState == .addNote || store.footerState == .contactSupport
    }
}

extension TransactionDetailsView {
    @ViewBuilder func bookmarkButton() -> some View {
        Button {
            store.send(.bookmarkTapped)
        } label: {
            let image = store.isBookmarked
            ? Asset.Assets.Icons.bookmarkCheck.image
            : Asset.Assets.Icons.bookmark.image

            image
                .zImage(size: Constants.iconSize, style: store.isBookmarked ? ZappColors.accent : ZappColors.text)
        }
        .buttonStyle(.zappPress)
    }

    @ViewBuilder func hideBalancesButton() -> some View {
        Button {
            $isSensitiveContentHidden.withLock { $0.toggle() }
        } label: {
            let image = isSensitiveContentHidden ? Asset.Assets.eyeOff.image : Asset.Assets.eyeOn.image
            image
                .zImage(size: Constants.iconSize, style: ZappColors.text)
        }
        .buttonStyle(.zappPress)
    }

    @ViewBuilder func shareView() -> some View {
        if let message = store.messageToBeShared {
            UIShareDialogView(activityItems: [
                ShareableMessage(
                    title: String(localizable: .sendFeedbackShareTitle),
                    message: message,
                    desc: String(localizable: .sendFeedbackShareDesc)
                ),
            ]) {
                store.send(.shareFinished)
            }
            // UIShareDialogView only wraps UIActivityViewController presentation
            // so frame is set to 0 to not break SwiftUI's layout
            .frame(width: 0, height: 0)
        } else {
            EmptyView()
        }
    }
}

// Header
extension TransactionDetailsView {
    @ViewBuilder func headerView() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                iconBox {
                    ZcashSymbol()
                        .frame(width: 26, height: 26)
                        .foregroundColor(ZappColors.text.color(colorScheme))
                }

                iconBox {
                    store.transaction.transationIcon
                        .zImage(size: Constants.iconSize, style: ZappColors.text)
                }
            }
            .padding(.top, 12)

            Text(store.transaction.title(true))
                .zappFont(.body, style: ZappColors.textMuted)
                .padding(.top, 12)

            amountView()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
        .padding(.horizontal, Constants.horizontalPadding)
    }

    @ViewBuilder func headerViewSwapToZec() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                iconBox {
                    if let swapFromAsset = store.swapFromAsset {
                        swapFromAsset.tokenIcon
                            .resizable()
                            .scaledToFit()
                            .frame(width: Constants.iconSize, height: Constants.iconSize)
                    } else {
                        unknownAsset()
                    }
                }

                iconBox {
                    store.transaction.transationIcon
                        .zImage(size: Constants.iconSize, style: ZappColors.text)
                }

                iconBox {
                    if let swapToAsset = store.swapToAsset {
                        swapToAsset.tokenIcon
                            .resizable()
                            .scaledToFit()
                            .frame(width: Constants.iconSize, height: Constants.iconSize)
                    } else {
                        unknownAsset()
                    }
                }
            }
            .padding(.top, 12)

            if !store.transaction.title(true).isEmpty {
                Text(store.transaction.title(true))
                    .zappFont(.body, style: ZappColors.textMuted)
                    .padding(.top, 12)
            } else {
                unknownValue()
                    .padding(.top, 12)
            }

            amountView()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
        .padding(.horizontal, Constants.horizontalPadding)
    }

    @ViewBuilder func iconBox(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: Constants.iconBox, height: Constants.iconBox)
            .background(ZappColors.surfaceAlt.color(colorScheme))
    }

    @ViewBuilder func amountView() -> some View {
        VStack(spacing: 4) {
            Group {
                if store.isSensitiveContentHidden {
                    Text(localizable: .generalHideBalancesMost)
                        .zappFont(.display, style: amountStyle)
                } else if store.transaction.isSwapToZec {
                    if let amount = store.swapAmountOut {
                        Text("\(amount) \(tokenName)")
                            .zappFont(.display, style: amountStyle)
                    } else {
                        unknownAmount()
                    }
                } else {
                    Text("\(store.transaction.netValue) \(tokenName)")
                        .zappFont(.display, style: amountStyle)
                }
            }
            .minimumScaleFactor(0.1)
            .lineLimit(1)

            if let amountFiat {
                Text(amountFiat)
                    .zappFont(.body, style: ZappColors.textMuted)
            }
        }
    }

    // The transaction amount in the selected fiat, shown under the ZEC value (nil when there is no rate).
    private var amountFiat: String? {
        guard !store.isSensitiveContentHidden, !store.transaction.isSwapToZec else { return nil }
        guard let currencyConversion else { return nil }

        return currencyConversion.convert(store.transaction.zecAmount)
    }

    var amountStyle: ZappColors {
        let transaction = store.transaction

        if transaction.status == .failed
            || transaction.swapStatus == .failed
            || transaction.swapStatus == .expired
            || transaction.swapStatus == .refunded {
            return .danger
        }

        return transaction.isSentTransaction ? .text : .success
    }
}

// Details
extension TransactionDetailsView {
    var detailItems: [DetailItem] {
        let transaction = store.transaction
        let hiddenValue = String(localizable: .generalHideBalancesMost)
        var items: [DetailItem] = []

        if store.isSwap {
            items.append(
                DetailItem(
                    id: "status",
                    title: String(localizable: .swapAndPayStatus),
                    value: store.swapStatus.map { DetailValue.status($0) } ?? .loading
                )
            )
        }

        if transaction.isSentTransaction && !transaction.isShieldingTransaction {
            items.append(
                DetailItem(
                    id: "sentTo",
                    title: transaction.isSwapToZec
                    ? String(localizable: .swapToZecDepositTo)
                    : String(localizable: .transactionHistorySentTo),
                    value: isSensitiveContentHidden
                    ? .text(hiddenValue)
                    : store.alias.map { DetailValue.text($0) } ?? .address(transaction.address.zip316),
                    icon: Asset.Assets.copy.image,
                    action: .addressTapped
                )
            )
        }

        if store.areDetailsExpanded || !transaction.isSentTransaction {
            if let recipient = store.swapRecipient, store.isSwap {
                items.append(
                    DetailItem(
                        id: "recipient",
                        title: String(localizable: .swapAndPayRecipient),
                        value: isSensitiveContentHidden ? .text(hiddenValue) : .address(recipient.zip316),
                        icon: Asset.Assets.copy.image,
                        action: .swapRecipientTapped
                    )
                )
            }

            if !transaction.isSwapToZec {
                items.append(
                    DetailItem(
                        id: "transactionId",
                        title: String(localizable: .transactionListTransactionId),
                        value: isSensitiveContentHidden ? .text(hiddenValue) : .address(transaction.id.truncateMiddle),
                        icon: Asset.Assets.copy.image,
                        action: .transactionIdTapped
                    )
                )
            }

            if transaction.isSentTransaction {
                items.append(feeItem)
            }

            if store.isSwap {
                items.append(
                    DetailItem(
                        id: "slippage",
                        title: store.swapStatus == .success
                        ? String(localizable: .swapAndPayExecutedSlippage)
                        : String(localizable: .swapAndPayMaxSlippageTitle),
                        value: store.swapSlippage.map { DetailValue.text($0) } ?? .loading
                    )
                )

                if store.swapStatus == .refunded {
                    items.append(
                        DetailItem(
                            id: "refunded",
                            title: String(localizable: .swapAndPayRefundedAmount),
                            value: store.refundedAmount.map { DetailValue.text("\($0) \(tokenName)") } ?? .loading
                        )
                    )
                }
            }

            items.append(
                DetailItem(
                    id: "timestamp",
                    title: String(localizable: .transactionHistoryTimestamp),
                    value: .text(
                        isSensitiveContentHidden
                        ? hiddenValue
                        : store.transaction.listDateYearString ?? String(localizable: .transactionHistoryPending)
                    )
                )
            )
        }

        return items
    }

    var feeItem: DetailItem {
        if isSensitiveContentHidden {
            return DetailItem(
                id: "fee",
                title: String(localizable: .transactionDetailFeeSummary),
                value: .text(String(localizable: .generalHideBalancesMost))
            )
        }

        if store.transaction.isSwapToZec {
            var value = DetailValue.loading

            if let fee = store.totalSwapToZecFee, let assetName = store.totalSwapToZecFeeAssetName {
                value = .text("~\(fee) \(assetName)")
            }

            return DetailItem(id: "fee", title: String(localizable: .swapAndPayTotalFees), value: value)
        }

        if let totalFeesStr = store.totalFeesStr {
            return DetailItem(
                id: "fee",
                title: String(localizable: .swapAndPayTotalFees),
                value: .text("\(totalFeesStr) \(tokenName)")
            )
        }

        return DetailItem(
            id: "fee",
            title: String(localizable: .sendFeeSummary),
            value: .text(
                store.transaction.fee == nil
                ? "\(String(localizable: .generalFeeShort(store.feeStr))) \(tokenName)"
                : "\(store.feeStr) \(tokenName)"
            )
        )
    }

    @ViewBuilder func transactionDetailsList() -> some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                if store.transaction.isSentTransaction && !store.transaction.isShieldingTransaction {
                    showHideButton()
                        .padding(.bottom, 8)
                }

                let items = detailItems

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        detailRow(item)

                        if index < items.count - 1 {
                            ZappRowDivider()
                        }
                    }
                }
                .background(ZappColors.surface.color(colorScheme))
                .overlay {
                    Rectangle()
                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                }

                noteView()
            }
        }
    }

    @ViewBuilder func showHideButton() -> some View {
        HStack(spacing: 0) {
            Spacer()

            Button {
                store.send(.showHideButtonTapped, animation: .easeInOut)
            } label: {
                HStack(spacing: 6) {
                    Text(store.areDetailsExpanded
                         ? String(localizable: .generalLess)
                         : String(localizable: .generalMore)
                    )
                    .zappFont(.buttonSmall, style: ZappColors.textMuted)

                    Asset.Assets.chevronDown.image
                        .zImage(size: 16, style: ZappColors.textMuted)
                        .rotationEffect(Angle(degrees: store.areDetailsExpanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ZappColors.chipBg.color(colorScheme))
            }
            .buttonStyle(.zappPress)
        }
    }

    @ViewBuilder func detailRow(_ item: DetailItem) -> some View {
        HStack(spacing: 8) {
            Text(item.title)
                .zappFont(.body, style: ZappColors.textMuted)

            Spacer(minLength: 8)

            detailValue(item.value)

            if let icon = item.icon {
                icon
                    .zImage(size: Constants.valueIconSize, style: ZappColors.textSubtle)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            if let action = item.action {
                store.send(action)
            }
        }
    }

    @ViewBuilder func detailValue(_ value: DetailValue) -> some View {
        switch value {
        case .address(let address):
            Text(address)
                .zappFont(.mono, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

        case .loading:
            Rectangle()
                .fill(ZappColors.surfaceAlt.color(colorScheme))
                .shimmer(true)
                .frame(width: 86, height: 18)

        case .status(let status):
            ZappStatusChip(text: status.title, variant: status.zappVariant)

        case .text(let text):
            Text(text)
                .zappFont(.rowTitle, style: ZappColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    @ViewBuilder func noteView() -> some View {
        if !store.annotation.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ZappSectionLabel(text: String(localizable: .annotationTitle))

                Text(store.annotation)
                    .zappFont(.body, style: ZappColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, 12)
            .background(ZappColors.surface.color(colorScheme))
            .overlay {
                Rectangle()
                    .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
            }
            .padding(.top, 12)
        }
    }
}

// Messages
extension TransactionDetailsView {
    @ViewBuilder func messageViews() -> some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 8) {
                ZappSectionLabel(text: String(localizable: .sendMessage))
                    .padding(.top, 20)

                ForEach(0..<store.memos.count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        if index < store.messageStates.count && store.messageStates[index] == .longExpanded {
                            Text("\(store.memos[index].prefix(TransactionDetails.State.Constants.messageExpandThreshold))...")
                                .zappFont(.body, style: ZappColors.text)
                        } else {
                            Text(store.memos[index])
                                .textSelection(.enabled)
                                .zappFont(.body, style: ZappColors.text)
                        }

                        if index < store.messageStates.count && store.messageStates[index] != .short {
                            HStack(spacing: 6) {
                                Text(index < store.messageStates.count && store.messageStates[index] == .longExpanded
                                     ? String(localizable: .transactionHistoryViewMore)
                                     : String(localizable: .transactionHistoryViewLess)
                                )
                                .zappFont(.buttonSmall, style: ZappColors.textMuted)

                                if index < store.messageStates.count && store.messageStates[index] == .longExpanded {
                                    Asset.Assets.chevronUp.image
                                        .zImage(size: 16, style: ZappColors.textMuted)
                                } else {
                                    Asset.Assets.chevronDown.image
                                        .zImage(size: 16, style: ZappColors.textMuted)
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ZappColors.surface.color(colorScheme))
                    .overlay {
                        Rectangle()
                            .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.messageTapped(index), animation: .easeInOut)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder func noMessageView() -> some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 8) {
                ZappSectionLabel(text: String(localizable: .sendMessage))
                    .padding(.top, 20)

                HStack(spacing: 8) {
                    Asset.Assets.Icons.noMessage.image
                        .zImage(size: 20, style: ZappColors.textSubtle)

                    Text(localizable: .transactionHistoryNoMessage)
                        .zappFont(.body, style: ZappColors.textSubtle)

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .overlay {
                    Rectangle()
                        .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

extension SwapBadge.Status {
    var zappVariant: ZappChipVariant {
        switch self {
        case .success:
            return .success
        case .failed, .expired, .refunded:
            return .danger
        case .pending, .pendingDeposit, .processing, .incompleteDeposit:
            return .accent
        }
    }
}

// MARK: - Previews

#Preview {
    TransactionDetailsView(store: TransactionDetails.initial, tokenName: "ZEC")
}

// MARK: - Store

extension TransactionDetails {
    @MainActor static var initial = StoreOf<TransactionDetails>(
        initialState: .initial
    ) {
        TransactionDetails()
    }
}

// MARK: - Placeholders

extension TransactionDetails.State {
    static var initial: TransactionDetails.State { TransactionDetails.State(transaction: .placeholder()) }
}
