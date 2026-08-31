// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import SwiftUI

struct PeerCashOutFormView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Perception.Bindable var store: StoreOf<PeerCashOutForm>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(
                    title: String(localizable: .peerFormTitle(PeerDestination.displayName(for: store.destinationCode)))
                )

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 0) {
                            amountHero
                            ledger.padding(.top, 6)
                            notice
                            handleField.padding(.top, 16)
                            currencyChips
                            topUpButton.padding(.top, 16)
                            openOrders

                            Spacer(minLength: 16)
                            terms.padding(.bottom, 4)
                        }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }
                }

                ZappBottomActionBar(onBack: { store.send(.backTapped) }) {
                    ZappButton(
                        title: String(localizable: .peerFormContinue),
                        isEnabled: store.canSubmit
                    ) { store.send(.continueTapped) }
                }
            }
            .applyScreenBackground()
            .onAppear { store.send(.onAppear) }
            .onDisappear { store.send(.onDisappear) }
        }
    }

    private var amountHero: some View {
        VStack(spacing: 6) {
            HStack {
                Text(String(localizable: .peerFormAmountLabel))
                    .zappFont(.eyebrow, style: ZappColors.textMuted)
                Spacer()
                Text(availableLabel)
                    .zappFont(.caption, style: ZappColors.textMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: Binding(
                    get: { store.amountInput },
                    set: { store.send(.amountChanged($0)) }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .zappFont(.display, style: ZappColors.text)
                .accessibilityLabel(String(localizable: .peerFormAmountLabel))

                Text(String(localizable: .peerUsdcTicker))
                    .zappFont(.displaySecondary, style: ZappColors.textMuted)
            }
            .padding(.vertical, 4)

            Rectangle()
                .fill(
                    store.amountError == nil
                        ? ZappColors.accent.color(colorScheme)
                        : ZappColors.danger.color(colorScheme)
                )
                .frame(height: 2)

            if let fiat = fiatEquivalent {
                Text(fiat)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZappCompactLedger(rows: ledgerRows)

            // Indicative is the whole point: the binding rate is whatever the oracle says when a
            // buyer commits, so the number above must never be read as locked in.
            Text(String(localizable: .peerFormRateDisclosure))
                .zappFont(.caption, style: ZappColors.textSubtle)
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let error = store.amountError ?? store.errorMessage {
            Text(error)
                .zappFont(.caption, style: ZappColors.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        } else if let warning = store.sizingWarning {
            Text(warning)
                .zappFont(.caption, style: ZappColors.accentText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ZappColors.accentSoft.color(colorScheme))
                .padding(.top, 10)
        }
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localizable: .peerFormHandleLabel))
                .zappFont(.eyebrow, style: ZappColors.textMuted)

            TextField(store.destination?.handleHint ?? "", text: Binding(
                get: { store.handleInput },
                set: { store.send(.handleChanged($0)) }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.plain)
            .zappFont(.rowTitle, style: ZappColors.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(ZappColors.surfaceInput.color(colorScheme))
            .overlay(
                Rectangle().strokeBorder(
                    store.handleError == nil
                        ? ZappColors.border.color(colorScheme)
                        : ZappColors.danger.color(colorScheme),
                    lineWidth: 1
                )
            )
            .accessibilityLabel(String(localizable: .peerFormHandleLabel))

            if let error = store.handleError {
                Text(error).zappFont(.caption, style: ZappColors.danger)
            } else if let echo = store.normalizedEcho {
                Text(echo).zappFont(.caption, style: ZappColors.textMuted)
            }

            if store.showsUnverifiedHandleWarning {
                Text(String(localizable: .peerFormHandleUnverified))
                    .zappFont(.caption, style: ZappColors.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(ZappColors.accentSoft.color(colorScheme))
            }
        }
    }

    @ViewBuilder
    private var currencyChips: some View {
        if let destination = store.destination, destination.offersCurrencyChoice {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localizable: .peerFormCurrenciesLabel))
                    .zappFont(.eyebrow, style: ZappColors.textMuted)

                // Wrapping: a rail can offer eleven currencies, and one line would clip the tail.
                ZappFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(destination.currencies) { currency in
                        let isSelected = store.selectedCurrencyCodes.contains(currency.code)
                        ZappStatusChip(
                            text: currency.code,
                            variant: isSelected ? .accent : .muted
                        ) { store.send(.currencyTapped(currency.code)) }
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    /// Who the user is actually dealing with, and that a completed payment is final. It sits at the
    /// bottom rather than in a sheet: it is a term of the product, not a help topic.
    private var terms: some View {
        Text(String(localizable: .peerFormTerms))
            .zappFont(.caption, style: ZappColors.textSubtle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topUpButton: some View {
        ZappButton(title: String(localizable: .peerFormTopUp), variant: .ghost) {
            store.send(.topUpTapped)
        }
    }

    @ViewBuilder
    private var openOrders: some View {
        if !store.unindexedRuns.isEmpty || !store.activeOrders.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localizable: .peerFormOpenOrders))
                    .zappFont(.eyebrow, style: ZappColors.textMuted)

                // Attempts first: they are the ones the chain cannot answer for yet, and the only
                // route back to an order whose deposit has not been indexed.
                ForEach(store.unindexedRuns) { run in
                    orderRow(
                        title: String(localizable: .peerUsdcAmount(run.amount.display)),
                        subtitle: String(localizable: .peerFormAttemptInProgress)
                    ) { store.send(.attemptTapped(attemptID: run.id)) }
                }

                ForEach(store.activeOrders) { order in
                    orderRow(
                        title: String(localizable: .peerUsdcAmount(order.remaining.display)),
                        subtitle: order.phase.label
                    ) { store.send(.orderTapped(depositID: order.depositID)) }
                }
            }
            .padding(.top, 20)
        }
    }

    private func orderRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).zappFont(.rowTitle, style: ZappColors.text)
                    Text(subtitle).zappFont(.caption, style: ZappColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Asset.Assets.chevronRight.image
                    .zImage(width: 16, height: 16, style: ZappColors.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(ZappColors.surface.color(colorScheme))
            .overlay(Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.zappPress)
    }

    private var ledgerRows: [ZappCompactLedgerRow] {
        var rows = [
            ZappCompactLedgerRow(
                label: String(localizable: .peerFormLedgerRate),
                value: store.rate.map {
                    String(localizable: .peerFormRateValue(decimalText($0.fiatPerUsdc), $0.currencyCode))
                } ?? String(localizable: .peerFormRateUnavailable)
            )
        ]
        // Only explains why Available is lower than the account balance; Available itself sits
        // against the amount field, where it is being spent.
        if let committed = store.spendable.committed {
            rows.append(
                ZappCompactLedgerRow(
                    label: String(localizable: .peerFormLedgerInProgress),
                    value: String(localizable: .peerUsdcAmount(committed.display))
                )
            )
        }
        rows.append(
            ZappCompactLedgerRow(
                label: String(localizable: .peerFormLedgerPaidTo),
                value: PeerDestination.displayName(for: store.destinationCode)
            )
        )
        return rows
    }

    private var availableLabel: String {
        guard let available = store.spendable.available else { return String(localizable: .peerFormBalancePending) }
        return String(localizable: .peerFormAvailable(available.display))
    }

    private var fiatEquivalent: String? {
        guard let amount = store.amount, let rate = store.rate else { return nil }
        return String(
            localizable: .peerFormFiatEquivalent(
                decimalText(rate.fiatValue(of: amount), fractionDigits: 2),
                rate.currencyCode
            )
        )
    }

    private func decimalText(_ value: Decimal, fractionDigits: Int = 6) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ""
    }
}

#Preview {
    PeerCashOutFormView(
        store: Store(initialState: PeerCashOutForm.State(destinationCode: "revolut")) { PeerCashOutForm() }
    )
    .applyScreenBackground()
}
