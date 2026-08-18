// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@preconcurrency import ZappOfframp
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized)
struct OfframpNearBridgeTests {
    private static let testnetUnifiedAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """

    @Test func expiredStatusEndsPollingAndClearsTheCheckpoint() async throws {
        let statusCalls = LockIsolated(0)
        let bridge = makeBridge { _, _ in
            statusCalls.withValue { $0 += 1 }
            return self.details(
                status: Near1Click.swapStatus(from: SwapConstants.expired, isSwapToZec: false)
            )
        }

        let result = try await bridge.resume(depositAddress: "deposit")

        #expect(!result.succeeded)
        #expect(result.terminal)
        #expect(result.message?.contains(SwapConstants.expired) == true)
        #expect(statusCalls.value == 1)
    }

    @Test func unknownProviderStatusFallsBackToPendingAndStopsAtTheDeadline() async throws {
        let statusCalls = LockIsolated(0)
        let mappedStatus = Near1Click.swapStatus(from: "FUTURE_PROVIDER_STATUS", isSwapToZec: false)
        #expect(mappedStatus == .pending)
        let bridge = makeBridge(pollingTimeout: .zero) { _, _ in
            statusCalls.withValue { $0 += 1 }
            return self.details(status: mappedStatus)
        }

        let result = try await bridge.resume(depositAddress: "deposit")

        #expect(!result.succeeded)
        #expect(!result.terminal)
        #expect(result.message?.contains("Resume") == true)
        #expect(statusCalls.value == 1)
    }

    @Test func processingStatusStopsAtTheLocalDeadlineAndRemainsResumable() async throws {
        let statusCalls = LockIsolated(0)
        let bridge = makeBridge(
            pollingTimeout: .zero
        ) { _, _ in
            statusCalls.withValue { $0 += 1 }
            return self.details(status: .processing)
        }

        let result = try await bridge.resume(depositAddress: "deposit")

        #expect(!result.succeeded)
        #expect(!result.terminal)
        #expect(result.message?.contains(SwapConstants.processing) == true)
        #expect(result.message?.contains("Resume") == true)
        #expect(statusCalls.value == 1)
    }

    @Test func pollingReachesSuccessBeforeTheDeadline() async throws {
        let statusCalls = LockIsolated(0)
        let bridge = makeBridge { _, _ in
            let call = statusCalls.withValue {
                $0 += 1
                return $0
            }
            return call == 1
                ? self.details(status: .processing)
                : self.details(status: .success)
        }

        let result = try await bridge.resume(depositAddress: "deposit")

        #expect(result.succeeded)
        #expect(!result.terminal)
        #expect(result.message == nil)
        #expect(statusCalls.value == 2)
    }

    /// Exercises preview -> authorization -> Zcash submission -> provider tx-id handoff -> poll
    /// without network access or real funds. It pins the production corridor that calls `poll`
    /// immediately after broadcasting the deposit transaction.
    @Test func executeCorridorSubmitsOnceThenPollsToSuccess() async throws {
        let account = try zcashAccountWithPrivateAddress()
        let depositAddress = Self.testnetUnifiedAddress
        let destinationAddress = "0xBase"
        let usdcMicros = "2500000"
        let usdcAssetID = "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near"
        let quote = SwapQuote(
            depositAddress: depositAddress,
            destinationAddress: destinationAddress,
            refundAddress: Self.testnetUnifiedAddress,
            originAssetId: Near1Click.Constants.nearZecAssetId,
            destinationAssetId: usdcAssetID,
            amountIn: 100_000_000,
            amountInUsd: "1",
            minAmountIn: 100_000_000,
            amountOut: 2.5,
            amountOutUsd: "2.5",
            timeEstimate: 60
        )
        let submittedTransactions = LockIsolated(0)
        let submittedTxIDs = LockIsolated<[(String, String)]>([])
        let statusCalls = LockIsolated(0)

        var swapAndPay = SwapAndPayClient()
        swapAndPay.swapAssetsCatalog = {
            IdentifiedArrayOf(uniqueElements: [
                SwapAsset(
                    provider: "near",
                    chain: "zec",
                    token: "ZEC",
                    assetId: Near1Click.Constants.nearZecAssetId,
                    usdPrice: 1,
                    decimals: 8
                ),
                SwapAsset(
                    provider: "near",
                    chain: "base",
                    token: "USDC",
                    assetId: usdcAssetID,
                    usdPrice: 1,
                    decimals: 6
                )
            ])
        }
        swapAndPay.quote = { _, _, _, _, _, _, _, _, _ in quote }
        swapAndPay.submitDepositTxId = { txID, address in
            submittedTxIDs.withValue { $0.append((txID, address)) }
        }
        swapAndPay.status = { _, _ in
            statusCalls.withValue { $0 += 1 }
            return self.details(status: .success)
        }

        let synchronizer = SDKSynchronizerClient.mocked(
            getAccountsBalances: {
                [
                    account.id: AccountBalance(
                        saplingBalance: PoolBalance(
                            spendableValue: Zatoshi(200_000_000),
                            changePendingConfirmation: .zero,
                            valuePendingSpendability: .zero
                        ),
                        orchardBalance: .zero,
                        ironwoodBalance: .zero,
                        unshielded: .zero
                    )
                ]
            },
            proposeTransfer: { _, _, _, _ in .testOnlyFakeProposal(totalFee: 0) },
            createAndSubmitProposedTransactions: { _, _ in
                submittedTransactions.withValue { $0 += 1 }
                return .success(txIds: ["zcash-tx-id"])
            }
        )

        let bridge = OfframpNearBridge(
            account: account,
            swapAndPay: swapAndPay,
            sdkSynchronizer: synchronizer,
            walletStorage: .noOp,
            mnemonic: .mock,
            derivationTool: .liveValue,
            environment: .testnet
        )

        _ = try await bridge.previewTopUp(accountAddress: destinationAddress, usdcMicros: usdcMicros)
        let preparedAddress = try await bridge.prepare(
            accountAddress: destinationAddress,
            usdcMicros: usdcMicros
        )
        let result = try await bridge.execute(depositAddress: preparedAddress)

        #expect(result.succeeded)
        #expect(submittedTransactions.value == 1)
        #expect(submittedTxIDs.value.count == 1)
        #expect(submittedTxIDs.value.first?.0 == "zcash-tx-id")
        #expect(submittedTxIDs.value.first?.1 == depositAddress)
        #expect(statusCalls.value == 1)
    }

    private func makeBridge(
        clock: AnyClock<Swift.Duration> = AnyClock(ImmediateClock()),
        pollingInterval: Swift.Duration = .seconds(5),
        pollingTimeout: Swift.Duration = .seconds(30 * 60),
        status: @escaping @Sendable (String, Bool) async throws -> SwapDetails
    ) -> OfframpNearBridge {
        var swapAndPay = SwapAndPayClient()
        swapAndPay.status = status
        return OfframpNearBridge(
            account: zcashAccount(),
            swapAndPay: swapAndPay,
            sdkSynchronizer: .noOp,
            walletStorage: .noOp,
            mnemonic: .noOp,
            derivationTool: .noOp,
            environment: .testnet,
            pollingClock: clock,
            pollingInterval: pollingInterval,
            pollingTimeout: pollingTimeout
        )
    }

    private func zcashAccount() -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: 0x42, count: 16)),
                name: "Zapp",
                keySource: nil,
                seedFingerprint: [UInt8](repeating: 0x24, count: 32),
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
    }

    private func zcashAccountWithPrivateAddress() throws -> WalletAccount {
        var account = zcashAccount()
        account.privateUA = try UnifiedAddress(encoding: Self.testnetUnifiedAddress, network: .testnet)
        return account
    }

    private func details(status: SwapDetails.Status) -> SwapDetails {
        SwapDetails(
            amountInFormatted: nil,
            amountInUsd: nil,
            amountOutFormatted: nil,
            amountOutUsd: nil,
            fromAsset: nil,
            toAsset: nil,
            isSwap: true,
            slippage: nil,
            status: status,
            refundedAmountFormatted: nil,
            swapRecipient: nil,
            addressToCheckShield: "",
            whenInitiated: "",
            deadline: "",
            depositedAmountFormatted: nil
        )
    }

}
