// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

/// The durable marker divides `FundGiftCard.submit`. Both SDKs can broadcast a locally created
/// transaction before an explicit submit, so a card whose marker was not written first can be
/// funded and never recorded — money on a bearer seed nobody is ever handed a link to, with no
/// error shown. Everything past the marker is `submitUncertain`, and nothing past it drops the txid.
@Suite struct FundGiftCardSubmitTests {
    @Test func writesTheDurableAttemptMarkerBeforeTheTransactionExists() async throws {
        let calls = LockIsolated<[String]>([])

        let txid = try await submitFunding(calls: calls)

        #expect(txid == Self.txid)
        #expect(
            calls.value == [
                "setFundingAttemptedAt",
                "createProposedTransactionsWithoutSubmit",
                "recordFundingCreated(\(Self.txid))",
                "submitCreatedTransactionsForGift",
                "recordFundingSubmitted(\(Self.txid))"
            ]
        )
    }

    @Test func refusesToCreateAnythingWhenTheAttemptMarkerCannotBePersisted() async {
        let calls = LockIsolated<[String]>([])

        await #expect(throws: GiftFundingError.proposalFailed) {
            try await self.submitFunding(calls: calls, markerFails: true)
        }

        #expect(calls.value == ["setFundingAttemptedAt"])
    }

    @Test func leavesACreationFailurePastTheMarkerUnresolvedRatherThanRetryable() async {
        let calls = LockIsolated<[String]>([])

        await #expect(throws: GiftFundingError.submitUncertain) {
            try await self.submitFunding(calls: calls, creationFails: true)
        }

        #expect(calls.value == ["setFundingAttemptedAt", "createProposedTransactionsWithoutSubmit"])
    }

    @Test func keepsTheRecordedTxidOnEveryUnsuccessfulBroadcastOutcome() async {
        let outcomes: [SDKSynchronizerClient.CreateProposedTransactionsResult] = [
            .failure(txIds: [], code: 1, description: "rejected"),
            .partial(txIds: [Self.txid], statuses: ["failed"]),
            .grpcFailure(txIds: [], reason: .timeout)
        ]

        for outcome in outcomes {
            let calls = LockIsolated<[String]>([])

            await #expect(throws: GiftFundingError.submitUncertain) {
                try await self.submitFunding(calls: calls, submitResult: outcome)
            }

            #expect(
                calls.value == [
                    "setFundingAttemptedAt",
                    "createProposedTransactionsWithoutSubmit",
                    "recordFundingCreated(\(Self.txid))",
                    "submitCreatedTransactionsForGift"
                ],
                "broadcast outcome \(outcome)"
            )
        }
    }

    @Test func reportsAStorageFailureAfterTheBroadcastAsUncertain() async {
        let calls = LockIsolated<[String]>([])

        await #expect(throws: GiftFundingError.submitUncertain) {
            try await self.submitFunding(calls: calls, recordSubmittedFails: true)
        }

        #expect(
            calls.value == [
                "setFundingAttemptedAt",
                "createProposedTransactionsWithoutSubmit",
                "recordFundingCreated(\(Self.txid))",
                "submitCreatedTransactionsForGift",
                "recordFundingSubmitted(\(Self.txid))"
            ]
        )
    }

    // MARK: - Helpers

    private func submitFunding(
        calls: LockIsolated<[String]>,
        markerFails: Bool = false,
        creationFails: Bool = false,
        recordSubmittedFails: Bool = false,
        submitResult: SDKSynchronizerClient.CreateProposedTransactionsResult = .success(txIds: [FundGiftCardSubmitTests.txid])
    ) async throws -> String {
        let card = try Self.card()

        return try await withDependencies {
            $0.date.now = { Self.now }

            var derivationTool = DerivationToolClient.noOp
            derivationTool.deriveSpendingKey = { _, _, _ in UnifiedSpendingKey(network: .testnet, bytes: []) }
            $0.derivationTool = derivationTool

            var storage = GiftCardStorageClient()
            storage.get = { _ in card }
            storage.setFundingAttemptedAt = { _, _ in
                calls.withValue { $0.append("setFundingAttemptedAt") }
                if markerFails { throw GiftFundingStubFailure() }
            }
            storage.recordFundingCreated = { _, txid, _ in
                calls.withValue { $0.append("recordFundingCreated(\(txid))") }
            }
            storage.recordFundingSubmitted = { _, txid, _ in
                calls.withValue { $0.append("recordFundingSubmitted(\(txid))") }
                if recordSubmittedFails { throw GiftFundingStubFailure() }
            }
            $0.giftCardStorage = storage

            $0.mnemonic = .noOp

            var synchronizer = SDKSynchronizerClient.noOp
            synchronizer.walletAccounts = { [Self.account] }
            synchronizer.createProposedTransactionsWithoutSubmit = { _, _ in
                calls.withValue { $0.append("createProposedTransactionsWithoutSubmit") }
                if creationFails { throw GiftFundingStubFailure() }
                return [CreatedTransaction(txId: Self.txidBytes, raw: Data([0x01]), expiryHeight: nil)]
            }
            synchronizer.submitCreatedTransactionsForGift = { _ in
                calls.withValue { $0.append("submitCreatedTransactionsForGift") }
                return submitResult
            }
            $0.sdkSynchronizer = synchronizer

            $0.walletStorage = .noOp
        } operation: {
            try await FundGiftCard().submit(
                GiftFundingQuote(
                    card: card,
                    proposal: .testOnlyFakeProposal(totalFee: 10_000),
                    claimFeeReserve: Zatoshi(10_000),
                    networkFee: Zatoshi(10_000),
                    link: "https://gift.justzappit.xyz/c/v1#k=unused"
                )
            )
        }
    }

    private static func card() throws -> StoredGiftCard {
        try StoredGiftCard(
            id: "card-1",
            network: "main",
            address: "u1exampleunifiedaddressforgiftcardtests",
            mnemonic: mnemonic,
            amountZatoshi: 100_000_000,
            birthdayHeight: 2_800_000,
            sourceAccountUuid: accountUUID.giftStorageKey,
            createdAt: "2026-08-20T12:00:00Z",
            updatedAt: "2026-08-20T12:00:00Z",
            status: .draft
        )
    }

    private static let now = Date(timeIntervalSince1970: 0)

    private static let txidBytes = Data(repeating: 0xAB, count: 32)
    private static let txid = String(repeating: "ab", count: 32)

    private static let accountUUID = AccountUUID(id: [UInt8](repeating: 0x01, count: 16))

    private static let account = WalletAccount(
        Account(
            id: accountUUID,
            name: "Zapp",
            keySource: "zashi",
            seedFingerprint: nil,
            hdAccountIndex: Zip32AccountIndex(0),
            ufvk: nil,
            uivk: nil
        )
    )

    /// BIP-39 test vector for all-zero entropy. Never a real wallet.
    private static let mnemonic = "\(String(repeating: "abandon ", count: 23))art"
}

private struct GiftFundingStubFailure: Error {}
