//
//  TransactionsManagerView.swift
//  Zashi
//
//  Created by Lukáš Korba on 01-22-2025.
//

import SwiftUI
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

struct TransactionsManagerView: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Constants {
        static let horizontalPadding: CGFloat = 18
        static let controlSize: CGFloat = 44
        static let iconSize: CGFloat = 20
        static let badgeSize: CGFloat = 16
        static let placeholderRows = 15
    }

    @Perception.Bindable var store: StoreOf<TransactionsManager>
    let tokenName: String

    @Shared(.appStorage(.sensitiveContent)) var isSensitiveContentHidden = false

    init(store: StoreOf<TransactionsManager>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ZappScreenHeader(title: String(localizable: .generalActivity)) {
                    hideBalancesButton()
                }

                searchRow()

                if store.transactionSections.isEmpty && !store.isInvalidated {
                    noTransactionsView()

                    Spacer()
                } else {
                    transactionsList()
                }
            }
            .disabled(store.transactions.isEmpty)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ZappColors.bg.color(colorScheme))
            .onAppear { store.send(.onAppear) }
            .zashiSheet(isPresented: $store.filtersRequest) {
                // A sheet's content closure escapes: reads inside it only register with TCA's
                // observation system under their own WithPerceptionTracking.
                WithPerceptionTracking {
                    filtersContent()
                }
            }
        }
        .navigationBarHidden(true)
        .zashiBack() {
            store.send(.dismissRequired)
        }
    }

    @ViewBuilder func transactionsList() -> some View {
        ScrollViewReader { scrollViewProxy in
            List {
                if store.isInvalidated {
                    VStack(spacing: 0) {
                        ForEach(0..<Constants.placeholderRows, id: \.self) { _ in
                            TransactionPlaceholderRow()
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(ZappColors.bg.color(colorScheme))
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(store.transactionSections) { section in
                        WithPerceptionTracking {
                            Section {
                                ForEach(section.transactions) { transaction in
                                    WithPerceptionTracking {
                                        ZappTransactionRow(
                                            transaction: transaction,
                                            tokenName: tokenName,
                                            isUnread: TransactionsManager.isUnread(transaction),
                                            isSwap: TransactionsManager.isSwap(transaction),
                                            divider: section.latestTransactionId != transaction.id
                                        ) {
                                            store.send(.transactionTapped(transaction.id))
                                        }
                                        // Feeds the swap-status poll in RootSwaps; drop it and swap
                                        // rows keep rendering a stale status.
                                        .onAppear {
                                            if transaction.requiresAutoUpdate {
                                                store.send(.transactionOnAppear(transaction.id))
                                            }
                                        }
                                        .listRowInsets(EdgeInsets())
                                    }
                                }
                                .listRowBackground(ZappColors.bg.color(colorScheme))
                                .listRowSeparator(.hidden)
                            } header: {
                                ZappSectionLabel(text: section.id)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Constants.horizontalPadding)
                                    .padding(.vertical, 8)
                                    .background(ZappColors.bg.color(colorScheme))
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(ZappColors.bg.color(colorScheme))
                                    .listRowSeparator(.hidden)
                                    .id(section.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: store.transactionSections) { _ in
                scrollViewProxy.scrollTo(store.transactionSections.first?.id, anchor: .top)
            }
        }
    }

    @ViewBuilder func searchRow() -> some View {
        HStack(spacing: 8) {
            searchField()

            filterButton()
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder func searchField() -> some View {
        HStack(spacing: 8) {
            Asset.Assets.Icons.search.image
                .zImage(size: Constants.iconSize, style: ZappColors.textSubtle)

            ZStack(alignment: .leading) {
                if store.searchTerm.isEmpty {
                    Text(localizable: .filterSearch)
                        .zappFont(.body, style: ZappColors.textSubtle)
                        .allowsHitTesting(false)
                }

                TextField("", text: $store.searchTerm)
                    .zappFont(.body, style: ZappColors.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if !store.searchTerm.isEmpty {
                Button {
                    store.send(.eraseSearchTermTapped)
                } label: {
                    Asset.Assets.Icons.xClose.image
                        .zImage(size: 16, style: ZappColors.textMuted)
                }
                .buttonStyle(.zappPress)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Constants.controlSize)
        .background(ZappColors.surfaceInput.color(colorScheme))
        .overlay {
            Rectangle()
                .strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1)
        }
    }

    @ViewBuilder func filterButton() -> some View {
        Button {
            store.send(.filterTapped)
        } label: {
            ZStack(alignment: .topTrailing) {
                Asset.Assets.Icons.filter.image
                    .zImage(size: Constants.iconSize, style: ZappColors.text)
                    .frame(width: Constants.controlSize, height: Constants.controlSize)
                    .background(ZappColors.surfaceAlt.color(colorScheme))
                    .overlay {
                        Rectangle()
                            .strokeBorder(
                                store.activeFilters.isEmpty
                                ? ZappColors.border.color(colorScheme)
                                : ZappColors.accent.color(colorScheme),
                                lineWidth: store.activeFilters.isEmpty ? 1 : 2
                            )
                    }

                if !store.activeFilters.isEmpty {
                    Text("\(store.activeFilters.count)")
                        .zappFont(.chip, style: ZappColors.onAccent)
                        .frame(width: Constants.badgeSize, height: Constants.badgeSize)
                        .background(ZappColors.accent.color(colorScheme))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.zappPress)
    }

    @ViewBuilder func hideBalancesButton() -> some View {
        Button {
            $isSensitiveContentHidden.withLock { $0.toggle() }
        } label: {
            let image = isSensitiveContentHidden ? Asset.Assets.eyeOff.image : Asset.Assets.eyeOn.image
            image
                .zImage(size: 24, style: ZappColors.text)
        }
        .buttonStyle(.zappPress)
    }

    @ViewBuilder func noTransactionsView() -> some View {
        WithPerceptionTracking {
            VStack(spacing: 8) {
                Text(localizable: .filterNoResults)
                    .zappFont(.sectionTitle, style: ZappColors.text)

                Text(localizable: .filterWeTried)
                    .zappFont(.body, style: ZappColors.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Design.Spacing._4xl)
            .padding(.top, 64)
        }
    }
}

private struct TransactionPlaceholderRow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(ZappColors.surfaceAlt.color(colorScheme))
                .shimmer(true)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                bar(width: 86)
                bar(width: 64)
            }

            Spacer()

            bar(width: 40)
        }
        .padding(.horizontal, TransactionsManagerView.Constants.horizontalPadding)
        .padding(.vertical, 14)
    }

    private func bar(width: CGFloat) -> some View {
        Rectangle()
            .fill(ZappColors.surfaceAlt.color(colorScheme))
            .shimmer(true)
            .frame(width: width, height: 12)
    }
}

// MARK: - Previews

#Preview {
    TransactionsManagerView(store: TransactionsManager.initial, tokenName: "ZEC")
}

// MARK: - Store

extension TransactionsManager {
    @MainActor static var initial = StoreOf<TransactionsManager>(
        initialState: .initial
    ) {
        TransactionsManager()
    }
}

// MARK: - Placeholders

extension TransactionsManager.State {
    static var initial: TransactionsManager.State { TransactionsManager.State() }
}
