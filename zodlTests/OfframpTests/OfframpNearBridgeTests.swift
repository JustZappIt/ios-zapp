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

        var keystoneSigning = KeystoneSigningClient.noOp
        keystoneSigning.sign = { _, _ in
            Issue.record("A software account must never be routed through the Keystone lane")
            throw KeystoneSigningError.failed
        }
        let bridge = OfframpNearBridge(
            account: account,
            swapAndPay: swapAndPay,
            sdkSynchronizer: synchronizer,
            walletStorage: .noOp,
            mnemonic: .mock,
            derivationTool: .liveValue,
            keystoneSigning: keystoneSigning,
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

    // MARK: - Keystone

    /// Same corridor from a Keystone account: the proposal goes to the device through
    /// `keystoneSigning`, the signed pair is broadcast, and the txid is handed to the provider —
    /// with no seed key ever derived.
    @Test func keystoneExecuteCorridorSignsOnTheDeviceThenBroadcastsThePair() async throws {
        let corridor = try makeKeystoneCorridor()
        let signed = KeystoneSignedPczt(pcztWithProofs: Pczt([0xA1]), pcztWithSigs: Pczt([0xB2]))
        let signRequests = LockIsolated<[AccountUUID]>([])
        let broadcasts = LockIsolated<[(Pczt, Pczt)]>([])
        var keystoneSigning = KeystoneSigningClient.noOp
        keystoneSigning.sign = { account, _ in
            signRequests.withValue { $0.append(account) }
            return signed
        }
        var synchronizer = corridor.synchronizer
        synchronizer.createAndSubmitTransactionFromPCZT = { proofs, sigs in
            broadcasts.withValue { $0.append((proofs, sigs)) }
            return .success(txIds: ["zcash-tx-id"])
        }
        let bridge = makeKeystoneBridge(corridor, synchronizer: synchronizer, keystoneSigning: keystoneSigning)

        _ = try await bridge.previewTopUp(accountAddress: corridor.destinationAddress, usdcMicros: corridor.usdcMicros)
        let preparedAddress = try await bridge.prepare(accountAddress: corridor.destinationAddress, usdcMicros: corridor.usdcMicros)
        let result = try await bridge.execute(depositAddress: preparedAddress)

        #expect(result.succeeded)
        #expect(signRequests.value == [corridor.account.id])
        #expect(broadcasts.value.count == 1)
        #expect(broadcasts.value.first?.0 == signed.pcztWithProofs)
        #expect(broadcasts.value.first?.1 == signed.pcztWithSigs)
        #expect(corridor.submittedTxIDs.value.map(\.0) == ["zcash-tx-id"])
        #expect(corridor.submittedTxIDs.value.map(\.1) == [corridor.depositAddress])
    }

    /// Rejecting on the device sends nothing, so the failure is terminal: the session clears the
    /// top-up checkpoint instead of leaving a deposit address nobody will ever fund to be resumed.
    @Test(arguments: [KeystoneSigningError.rejected, .failed, .wrongAccount, .busy])
    func keystoneRefusalIsTerminalAndBroadcastsNothing(refusal: KeystoneSigningError) async throws {
        let corridor = try makeKeystoneCorridor()
        var keystoneSigning = KeystoneSigningClient.noOp
        keystoneSigning.sign = { _, _ in throw refusal }
        var synchronizer = corridor.synchronizer
        synchronizer.createAndSubmitTransactionFromPCZT = { _, _ in
            Issue.record("Nothing may be broadcast after a refused signature")
            return .success(txIds: [])
        }
        let bridge = makeKeystoneBridge(corridor, synchronizer: synchronizer, keystoneSigning: keystoneSigning)

        _ = try await bridge.previewTopUp(accountAddress: corridor.destinationAddress, usdcMicros: corridor.usdcMicros)
        let preparedAddress = try await bridge.prepare(accountAddress: corridor.destinationAddress, usdcMicros: corridor.usdcMicros)
        let result = try await bridge.execute(depositAddress: preparedAddress)

        #expect(!result.succeeded)
        #expect(result.terminal)
        #expect(result.message?.isEmpty == false)
        #expect(corridor.submittedTxIDs.value.isEmpty)
        #expect(corridor.statusCalls.value == 0)
    }

    private struct KeystoneCorridor {
        let account: WalletAccount
        let depositAddress: String
        let destinationAddress: String
        let usdcMicros: String
        let swapAndPay: SwapAndPayClient
        let synchronizer: SDKSynchronizerClient
        let submittedTxIDs: LockIsolated<[(String, String)]>
        let statusCalls: LockIsolated<Int>
    }

    private func makeKeystoneCorridor() throws -> KeystoneCorridor {
        let account = try keystoneAccountWithPrivateAddress()
        let depositAddress = Self.testnetUnifiedAddress
        let destinationAddress = "0xBase"
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
        let submittedTxIDs = LockIsolated<[(String, String)]>([])
        let statusCalls = LockIsolated(0)

        var swapAndPay = SwapAndPayClient()
        swapAndPay.swapAssetsCatalog = {
            IdentifiedArrayOf(uniqueElements: [
                SwapAsset(provider: "near", chain: "zec", token: "ZEC", assetId: Near1Click.Constants.nearZecAssetId, usdPrice: 1, decimals: 8),
                SwapAsset(provider: "near", chain: "base", token: "USDC", assetId: usdcAssetID, usdPrice: 1, decimals: 6)
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
            getAccountsBalances: { [account.id: AccountBalance(
                saplingBalance: .zero,
                orchardBalance: PoolBalance(
                    spendableValue: Zatoshi(200_000_000),
                    changePendingConfirmation: .zero,
                    valuePendingSpendability: .zero
                ),
                ironwoodBalance: .zero,
                unshielded: .zero
            )] },
            proposeTransfer: { _, _, _, _ in .testOnlyFakeProposal(totalFee: 0) },
            createAndSubmitProposedTransactions: { _, _ in
                Issue.record("A hardware account has no seed key to create with")
                return .success(txIds: [])
            }
        )

        return KeystoneCorridor(
            account: account,
            depositAddress: depositAddress,
            destinationAddress: destinationAddress,
            usdcMicros: "2500000",
            swapAndPay: swapAndPay,
            synchronizer: synchronizer,
            submittedTxIDs: submittedTxIDs,
            statusCalls: statusCalls
        )
    }

    private func makeKeystoneBridge(
        _ corridor: KeystoneCorridor,
        synchronizer: SDKSynchronizerClient,
        keystoneSigning: KeystoneSigningClient
    ) -> OfframpNearBridge {
        var derivationTool = DerivationToolClient.noOp
        derivationTool.deriveSpendingKey = { _, _, _ in
            Issue.record("A hardware account must never derive a seed key")
            throw KeystoneSigningError.failed
        }
        return OfframpNearBridge(
            account: corridor.account,
            swapAndPay: corridor.swapAndPay,
            sdkSynchronizer: synchronizer,
            walletStorage: .noOp,
            mnemonic: .noOp,
            derivationTool: derivationTool,
            keystoneSigning: keystoneSigning,
            environment: .testnet
        )
    }

    private func keystoneAccountWithPrivateAddress() throws -> WalletAccount {
        var account = keystoneAccount()
        account.privateUA = try UnifiedAddress(encoding: Self.testnetUnifiedAddress, network: .testnet)
        return account
    }

    private func keystoneAccount() -> WalletAccount {
        WalletAccount(
            Account(
                id: AccountUUID(id: [UInt8](repeating: 0x43, count: 16)),
                name: "Keystone",
                keySource: "keystone",
                seedFingerprint: [UInt8](repeating: 0x25, count: 32),
                hdAccountIndex: Zip32AccountIndex(0),
                ufvk: nil,
                uivk: nil
            )
        )
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
            keystoneSigning: .noOp,
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
