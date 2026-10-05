//
//  UnifiedSendExactOutputTests.swift
//  zodlTests
//
//  Exact-output swaps on the unified send form ("They receive exactly"), Android's
//  `UnifiedSendVM.swapMode`. Pins the quote-mode switching (typing the destination → EXACT_OUTPUT,
//  the pay estimate → back to EXACT_INPUT), the derived amounts, the insufficient-funds gate on the
//  computed ZEC, the EXACT_OUTPUT request NEAR receives (the same `amount` Android's
//  `buildQuoteRequest` sends), the fail-closed quote echo check, and the review / submit typing.
//
//  `SwapAndPay.State.amount` is `_XCTIsTesting`-poisoned to 0, which is why everything exact-output
//  reads goes through `SendCoordFlow.State.destinationTokenAmount` instead.
//

import ComposableArchitecture
import Foundation
import Testing
@testable @preconcurrency import ZcashLightClientKit
@testable import zodl_internal

@Suite(.serialized, .timeLimit(.minutes(2))) @MainActor struct UnifiedSendExactOutputTests {
    private static let zcashAddress = "tmP3uLtGx5GPddkq8a6ddmXhqJJ3vy6tpTE"
    private static let recipient = "0x1111111111111111111111111111111111111111"
    private static let testnetUnifiedAddress = """
        utest1zkkkjfxkamagznjr6ayemffj2d2gacdwpzcyw669pvg06xevzqslpmm27zjsctlkstl2vsw62xrjktmzqcu4yu9zdhdxqz3kafa4j2q85y6mv74rzjcgjg8c0ytrg7d\
        wyzwtgnuc76h
        """
    private static let enUS = Locale(identifier: "en_US")

    /// USDC on Ethereum: 6 decimals, $1.25 so USD and token figures differ visibly.
    private static let usdc = SwapAsset(
        provider: "near", chain: "eth", token: "USDC", assetId: "nep141:eth-usdc.omft.near", usdPrice: 1.25, decimals: 6
    )
    private static let zec = SwapAsset(
        provider: "near", chain: "zec", token: "ZEC", assetId: "nep141:zec.omft.near", usdPrice: 50, decimals: 8
    )
    private static let btc = SwapAsset(
        provider: "near", chain: "btc", token: "BTC", assetId: "nep141:btc.omft.near", usdPrice: 100_000, decimals: 8
    )

    // MARK: - Fixtures

    private static func account() throws -> WalletAccount {
        var account = WalletAccount(
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
        account.privateUA = try UnifiedAddress(encoding: testnetUnifiedAddress, network: .testnet)
        return account
    }

    private static func swapState(
        balance: Zatoshi,
        exactOutput: Bool = false
    ) -> SendCoordFlow.State {
        var state = SendCoordFlow.State()
        state.mode = .swap
        state.sendFormState.walletBalancesState.shieldedBalance = balance
        state.swapState.walletBalancesState.shieldedBalance = balance
        state.swapState.isSwapExperienceEnabled = !exactOutput
        state.swapState.selectedAsset = usdc
        state.swapState.zecAsset = zec
        state.swapState.address = recipient
        return state
    }

    private static func makeStore(
        _ state: SendCoordFlow.State,
        configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> StoreOf<SendCoordFlow> {
        Store(initialState: state) {
            SendCoordFlow()
        } withDependencies: {
            $0.audioServices = AudioServicesClient(systemSoundVibrate: { })
            $0.derivationTool = .liveValue
            $0.exchangeRate = .noOp
            $0.locale = enUS
            $0.mainQueue = .immediate
            $0.numberFormatter = .liveValue
            $0.sdkSynchronizer = .noOp
            $0.userMetadataProvider.markTransactionAsSwapFor = { _, _, _, _, _, _, _, _, _ in }
            $0.userMetadataProvider.store = { _ in }
            $0.zcashSDKEnvironment = .testnet
            configure(&$0)
        }
    }

    private static func quote(
        amountOut: Decimal = 10,
        destinationAddress: String = recipient,
        refundAddress: String = testnetUnifiedAddress,
        destinationAssetId: String = usdc.assetId,
        amountIn: Decimal = 20_400_000,
        minAmountIn: Decimal = 20_000_000
    ) -> SwapQuote {
        SwapQuote(
            depositAddress: zcashAddress,
            destinationAddress: destinationAddress,
            refundAddress: refundAddress,
            originAssetId: zec.assetId,
            destinationAssetId: destinationAssetId,
            amountIn: amountIn,
            amountInUsd: "10.20",
            minAmountIn: minAmountIn,
            amountOut: amountOut,
            amountOutUsd: "12.50",
            timeEstimate: 60
        )
    }

    private static func request() -> ExactOutputSwap.Request {
        ExactOutputSwap.Request(
            baseUnits: "10000000",
            destinationDecimals: 6,
            originAssetId: zec.assetId,
            destinationAssetId: usdc.assetId,
            destinationAddress: recipient,
            refundAddress: testnetUnifiedAddress,
            slippageBps: 200
        )
    }

    // MARK: - Arithmetic (Android's `UnifiedSendEstimates.kt` / `buildQuoteRequest`)

    @Test func typedAmountsParseExactlyInTheirLocale() {
        #expect(ExactOutputSwap.decimal(from: "0.3", locale: Self.enUS) == Decimal(string: "0.3", locale: Locale(identifier: "en_US_POSIX")))
        #expect(ExactOutputSwap.decimal(from: "0,3", locale: Locale(identifier: "de_DE")) == Decimal(3) / 10)
        // A grouping separator is never silently dropped: "1.5" under German is not 15.
        #expect(ExactOutputSwap.decimal(from: "1.5", locale: Locale(identifier: "de_DE")) == nil)
        #expect(ExactOutputSwap.decimal(from: "1.2.3", locale: Self.enUS) == nil)
        #expect(ExactOutputSwap.decimal(from: "abc", locale: Self.enUS) == nil)
        #expect(ExactOutputSwap.decimal(from: "", locale: Self.enUS) == nil)
    }

    /// The EXACT_OUTPUT `amount` is the destination amount in base units, rounded DOWN — Android's
    /// `amount.movePointRight(decimals)` + `RoundingMode.DOWN`.
    @Test func baseUnitsMatchAndroidsNormalisation() {
        #expect(ExactOutputSwap.baseUnits(Decimal(string: "0.3", locale: Self.enUS) ?? 0, decimals: 6) == "300000")
        #expect(ExactOutputSwap.baseUnits(10, decimals: 6) == "10000000")
        #expect(ExactOutputSwap.baseUnits(Decimal(string: "1.2345678", locale: Self.enUS) ?? 0, decimals: 6) == "1234567")
        #expect(ExactOutputSwap.baseUnits(Decimal(string: "1.5", locale: Self.enUS) ?? 0, decimals: 18) == "1500000000000000000")
        #expect(ExactOutputSwap.baseUnits(Decimal(string: "0.0000001", locale: Self.enUS) ?? 0, decimals: 6) == nil)
        #expect(ExactOutputSwap.baseUnits(0, decimals: 6) == nil)
    }

    @Test func estimatesConvertThroughUsdAndRefuseMissingPrices() {
        // 10 USDC at $1.25 = $12.50 = 0.25 ZEC at $50.
        #expect(ExactOutputSwap.estimateZec(token: 10, tokenUsdPrice: 1.25, zecUsdPrice: 50) == Decimal(25) / 100)
        #expect(ExactOutputSwap.estimateToken(zec: 1, zecUsdPrice: 50, tokenUsdPrice: 1.25) == 40)
        #expect(ExactOutputSwap.estimateZec(token: 10, tokenUsdPrice: 0, zecUsdPrice: 50) == nil)
        #expect(ExactOutputSwap.estimateZec(token: 10, tokenUsdPrice: 1.25, zecUsdPrice: 0) == nil)
    }

    // MARK: - Quote mode switching

    /// Typing the destination amount makes the swap exact-output and the destination authoritative.
    @Test func typingTheDestinationSwitchesToExactOutput() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))
        #expect(!store.isExactOutput)

        store.send(.destinationAmountChanged("10"))

        #expect(store.isExactOutput)
        #expect(!store.swapState.isSwapExperienceEnabled)
        #expect(!store.swapState.isInputInUsd)
        #expect(store.destinationTokenAmount == 10)
        #expect(store.swapState.amountText == "10")
        #expect(store.exactOutputZecEstimate == Decimal(25) / 100)
        #expect(store.state.exactOutputZecEstimateText(locale: Self.enUS) == "0.25")
        #expect(store.primaryButton == .review)
    }

    /// Emptying the destination keeps exact-output with no amount yet (Android): Review disables
    /// instead of the field refilling itself with an estimate.
    @Test func clearingTheDestinationStaysExactOutputAndDisablesReview() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))

        store.send(.destinationAmountChanged("10"))
        store.send(.destinationAmountChanged(""))

        #expect(store.isExactOutput)
        #expect(store.destinationTokenAmount == nil)
        #expect(store.swapState.amountText.isEmpty)
        #expect(store.primaryButton == .disabled)
    }

    /// The pay estimate is the only way back: it returns to exact-input carrying the ZEC estimate,
    /// in the pay side's own currency.
    @Test func tappingThePayEstimateReturnsToExactInputWithTheEstimate() {
        var state = Self.swapState(balance: Zatoshi(100_000_000))
        state.swapState.isInputInUsd = true
        let store = Self.makeStore(state)

        store.send(.destinationAmountChanged("10"))
        #expect(!store.swapState.isInputInUsd)

        store.send(.payEstimateTapped)

        #expect(!store.isExactOutput)
        #expect(store.swapState.isSwapExperienceEnabled)
        // The pay side was in USD before: 0.25 ZEC at $50 comes back as $12.50.
        #expect(store.swapState.isInputInUsd)
        #expect(store.swapState.amountText == "12.5")
        #expect(store.destinationText.isEmpty)
        #expect(store.swapState.exactOutputBaseUnits == nil)
    }

    /// In exact-input the destination field carries the estimate of what the pay amount buys.
    @Test func exactInputShowsTheDestinationEstimate() {
        var state = Self.swapState(balance: Zatoshi(100_000_000))
        state.swapState.amountText = "1"
        let store = Self.makeStore(state)

        // 1 ZEC = $50 = 40 USDC.
        #expect(store.state.destinationFieldText(locale: Self.enUS) == "40")
        #expect(store.destinationUnit == "USDC")

        store.send(.destinationCurrencySwapped)

        #expect(store.state.destinationFieldText(locale: Self.enUS) == "50")
        #expect(store.destinationUnit == "USD")
        #expect(!store.isExactOutput)
    }

    /// A USD-denominated destination requests the token amount it converts to, truncated to the
    /// asset's precision.
    @Test func aUsdDestinationRequestsTheConvertedTokenAmount() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))

        store.send(.destinationCurrencySwapped)
        store.send(.destinationAmountChanged("25"))

        #expect(store.isDestinationTypedInUsd)
        #expect(store.destinationTokenAmount == 20)
        #expect(store.swapState.exactOutputBaseUnits == "20000000")
    }

    /// Flipping the display never re-derives the typed figure, so a round trip cannot drift.
    @Test func flippingTheDestinationCurrencyDoesNotDrift() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))

        store.send(.destinationAmountChanged("10"))
        store.send(.destinationCurrencySwapped)
        #expect(store.state.destinationFieldText(locale: Self.enUS) == "12.5")

        store.send(.destinationCurrencySwapped)
        #expect(store.state.destinationFieldText(locale: Self.enUS) == "10")
        #expect(store.destinationTokenAmount == 10)
        #expect(store.swapState.exactOutputBaseUnits == "10000000")
    }

    /// A figure finer than the asset can settle is never requested short: Review disables.
    @Test func tooPreciseADestinationDisablesReview() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))

        store.send(.destinationAmountChanged("1.1234567"))

        #expect(store.isExactOutput)
        #expect(store.destinationTokenAmount == nil)
        #expect(store.swapState.exactOutputBaseUnits == nil)
        #expect(store.primaryButton == .disabled)
    }

    /// Android's `clearTokenAmount` on an asset change.
    @Test func changingTheAssetReturnsToExactInput() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))

        store.send(.destinationAmountChanged("10"))
        store.send(.swapAssetSelected(Self.btc))

        #expect(!store.isExactOutput)
        #expect(store.swapState.amountText.isEmpty)
        #expect(store.destinationTypedAmount == nil)
    }

    /// A destination token amount is never carried into ZEC mode as if it were ZEC.
    @Test func switchingToZecDoesNotCarryTheTokenAmount() async {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))

        store.send(.destinationAmountChanged("10"))
        store.send(.zecAssetSelected)
        await Task.yield()

        #expect(store.mode == .zec)
        #expect(store.sendFormState.zecAmountText.data.isEmpty)
        #expect(store.swapState.isSwapExperienceEnabled)
    }

    // MARK: - Insufficient funds on the computed amount

    /// 10 USDC needs ≈ 0.25 ZEC; with 0.1 ZEC spendable the CTA becomes Top Up (Android's
    /// `!hasFunds` in exact-output, checked against the un-padded estimate).
    @Test func insufficientBalanceForTheComputedZecBlocksReview() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(10_000_000)))

        store.send(.destinationAmountChanged("10"))

        #expect(store.isInsufficientFunds)
        #expect(store.primaryButton == .topUp)
    }

    @Test func enoughBalanceForTheComputedZecAllowsReview() {
        let store = Self.makeStore(Self.swapState(balance: Zatoshi(25_000_000)))

        store.send(.destinationAmountChanged("10"))

        #expect(!store.isInsufficientFunds)
        #expect(store.primaryButton == .review)
    }

    // MARK: - The request NEAR receives

    /// The quote is requested as EXACT_OUTPUT for the destination amount in base units — the
    /// `amount` Android's `buildQuoteRequest` sends — with the slippage in bps, the typed recipient and
    /// the private UA as refund address.
    @Test func exactOutputRequestsTheDestinationBaseUnits() async throws {
        struct Call: Sendable {
            let mode: SwapQuoteMode
            let slippage: Int
            let toAssetId: String
            let refundTo: String
            let destination: String
            let amount: String
            let isSwapToZec: Bool
        }
        let calls = SignalledRecords<Call>()
        let account = try Self.account()

        try await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Self.swapState(balance: Zatoshi(100_000_000))
            state.swapState.$selectedWalletAccount.withLock { $0 = account }
            let store = Self.makeStore(state) {
                $0.swapAndPay.quote = { _, isSwapToZec, mode, slippage, _, toAsset, refundTo, destination, amount in
                    calls.record(Call(
                        mode: mode,
                        slippage: slippage,
                        toAssetId: toAsset.assetId,
                        refundTo: refundTo,
                        destination: destination,
                        amount: amount,
                        isSwapToZec: isSwapToZec
                    ))
                    throw SwapAndPayClient.EndpointError.message("stop")
                }
            }

            store.send(.destinationAmountChanged("0.3"))
            store.send(.swap(.getQuote))
            await calls.countReached(1)

            let call = try #require(calls.values.first)
            #expect(call.mode == .exactOutput)
            #expect(call.mode.rawValue == "EXACT_OUTPUT")
            #expect(call.amount == "300000")
            #expect(call.slippage == 200)
            #expect(call.toAssetId == Self.usdc.assetId)
            #expect(call.destination == Self.recipient)
            #expect(call.refundTo == Self.testnetUnifiedAddress)
            #expect(!call.isSwapToZec)
            #expect(store.swapState.exactOutputRequest == ExactOutputSwap.Request(
                baseUnits: "300000",
                destinationDecimals: 6,
                originAssetId: Self.zec.assetId,
                destinationAssetId: Self.usdc.assetId,
                destinationAddress: Self.recipient,
                refundAddress: Self.testnetUnifiedAddress,
                slippageBps: 200
            ))
        }
    }

    /// The JSON body field names and values for EXACT_OUTPUT match Android's `QuoteRequest`.
    @Test func exactOutputRequestBodyMatchesAndroidsWireFormat() throws {
        let body = SwapQuoteRequest(
            dry: false,
            swapType: SwapQuoteMode.exactOutput.rawValue,
            slippageTolerance: 200,
            originAsset: Self.zec.assetId,
            depositType: "ORIGIN_CHAIN",
            destinationAsset: Self.usdc.assetId,
            amount: "300000",
            refundTo: Self.testnetUnifiedAddress,
            refundType: "ORIGIN_CHAIN",
            recipient: Self.recipient,
            recipientType: "DESTINATION_CHAIN",
            deadline: "2026-10-04T12:00:00Z",
            referral: "zapp",
            quoteWaitingTimeMs: 3000,
            appFees: []
        )
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])

        #expect(Set(json.keys) == [
            "dry", "swapType", "slippageTolerance", "originAsset", "depositType", "destinationAsset", "amount",
            "refundTo", "refundType", "recipient", "recipientType", "deadline", "referral", "quoteWaitingTimeMs", "appFees"
        ])
        #expect(json["swapType"] as? String == "EXACT_OUTPUT")
        #expect(json["amount"] as? String == "300000")
        #expect(json["slippageTolerance"] as? Int == 200)
    }

    // MARK: - Quote echo (Android's `requestExactOutput` validation)

    @Test func aMatchingQuoteSatisfiesTheRequest() {
        #expect(ExactOutputSwap.quote(Self.quote(), satisfies: Self.request()))
    }

    @Test func aQuoteThatDeliversLessOrElsewhereIsRejected() {
        #expect(!ExactOutputSwap.quote(Self.quote(amountOut: Decimal(string: "9.999999", locale: Self.enUS) ?? 0), satisfies: Self.request()))
        #expect(!ExactOutputSwap.quote(Self.quote(destinationAddress: "0x2222222222222222222222222222222222222222"), satisfies: Self.request()))
        #expect(!ExactOutputSwap.quote(Self.quote(refundAddress: "utest1other"), satisfies: Self.request()))
        #expect(!ExactOutputSwap.quote(Self.quote(destinationAssetId: Self.btc.assetId), satisfies: Self.request()))
        // Worst-case input beyond amountIn × (1 + 2%).
        #expect(!ExactOutputSwap.quote(Self.quote(amountIn: 20_000_000, minAmountIn: 20_400_001), satisfies: Self.request()))
        #expect(ExactOutputSwap.quote(Self.quote(amountIn: 20_000_000, minAmountIn: 20_400_000), satisfies: Self.request()))
    }

    /// A mismatched echo never reaches a proposal: the quote is dropped and the unavailable sheet shown.
    @Test func aMismatchedQuoteIsNeverProposed() async throws {
        let proposals = SignalledRecords<Zatoshi>()
        let account = try Self.account()

        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Self.swapState(balance: Zatoshi(100_000_000), exactOutput: true)
            state.swapState.$selectedWalletAccount.withLock { $0 = account }
            state.swapState.exactOutputRequest = Self.request()
            let store = Self.makeStore(state) {
                $0.sdkSynchronizer.proposeTransfer = { _, _, amount, _ in
                    proposals.record(amount)
                    return .testOnlyFakeProposal(totalFee: 10_000)
                }
            }

            store.send(.swap(.swapQuoteLoaded(Self.quote(amountOut: 9))))

            #expect(store.swapState.quote == nil)
            #expect(store.swapState.isQuoteUnavailablePresented)
            #expect(store.swapState.quoteUnavailableErrorMsg == String(localizable: .swapQuoteUnavailable))
            #expect(proposals.isEmpty)
        }
    }

    /// A matching echo is proposed for exactly `amountIn` to the deposit address (Android's
    /// `createProposal`), and the quote sheet opens on the Pay Now variant.
    @Test func aMatchingQuoteProposesAmountIn() async throws {
        let proposals = SignalledRecords<Zatoshi>()
        let account = try Self.account()

        await withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            var state = Self.swapState(balance: Zatoshi(100_000_000), exactOutput: true)
            state.swapState.$selectedWalletAccount.withLock { $0 = account }
            state.swapState.exactOutputRequest = Self.request()
            let store = Self.makeStore(state) {
                $0.sdkSynchronizer.proposeTransfer = { _, _, amount, _ in
                    proposals.record(amount)
                    return .testOnlyFakeProposal(totalFee: 10_000)
                }
            }

            store.send(.swap(.swapQuoteLoaded(Self.quote())))
            await proposals.countReached(1)

            #expect(proposals.values == [Zatoshi(20_400_000)])
            #expect(store.swapState.quote == Self.quote())
        }
    }

    // MARK: - Review / submit

    /// The review sheet shows the promised amount unrounded (Android: `setScale(decimals, DOWN)`),
    /// not the 0.5%-tolerance `simplified` figure an exact-input estimate gets.
    @Test func theReviewShowsTheExactDestinationAmount() {
        var state = SwapAndPay.State.initial
        state.selectedAsset = Self.usdc
        state.quote = Self.quote(amountOut: Decimal(string: "10.123456", locale: Locale(identifier: "en_US_POSIX")) ?? 0)
        state.exactOutputRequest = Self.request()

        let separator = Locale.current.decimalSeparator ?? "."
        #expect(state.tokenToBeReceivedInQuote == "10\(separator)123456")
    }

    /// Confirming an exact-output quote submits as a CrossPay payment: the result screens use the
    /// "pay" copy and the swap history records it as not exact-input.
    @Test func confirmingAnExactOutputQuoteSubmitsAsAPayment() async {
        let exactInputFlags = SignalledRecords<Bool>()
        var state = Self.swapState(balance: Zatoshi(100_000_000), exactOutput: true)
        state.swapState.proposal = .testOnlyFakeProposal(totalFee: 10_000)
        state.swapState.quote = Self.quote()
        let store = Self.makeStore(state) {
            $0.localAuthentication.authenticate = { true }
            $0.userMetadataProvider.markTransactionAsSwapFor = { _, _, _, _, _, _, exactInput, _, _ in
                exactInputFlags.record(exactInput)
            }
        }

        store.send(.swap(.confirmButtonTapped))
        await exactInputFlags.countReached(1)

        #expect(exactInputFlags.values == [false])
        guard case .sending(let confirmation) = store.path.first(where: { $0.is(\.sending) }) else {
            Issue.record("expected sending to be pushed")
            return
        }
        #expect(confirmation.type == .pay)
        #expect(confirmation.amount == Zatoshi(20_400_000))
    }

    /// Keystone signs the same exact-output proposal through the PCZT chain, typed as a payment.
    @Test func keystoneConfirmOfAnExactOutputQuoteIsTypedAsAPayment() {
        var state = Self.swapState(balance: Zatoshi(100_000_000), exactOutput: true)
        state.swapState.proposal = .testOnlyFakeProposal(totalFee: 10_000)
        state.swapState.quote = Self.quote()
        let store = Self.makeStore(state)

        store.send(.swap(.confirmWithKeystoneTapped))

        guard case .confirmWithKeystone(let confirmation) = store.path.first else {
            Issue.record("expected confirmWithKeystone to be pushed")
            return
        }
        #expect(confirmation.type == .pay)
    }

    // MARK: - CrossPay info (Android's `CrossPayInfoArgs`)

    @Test func theCrossPayInfoOpensInSwapModeOnly() {
        let swapStore = Self.makeStore(Self.swapState(balance: Zatoshi(100_000_000)))
        swapStore.send(.crossPayInfoTapped)
        #expect(swapStore.isCrossPayInfoPresented)
        swapStore.send(.crossPayInfoDismissed)
        #expect(!swapStore.isCrossPayInfoPresented)

        let zecStore = Self.makeStore(SendCoordFlow.State())
        zecStore.send(.crossPayInfoTapped)
        #expect(!zecStore.isCrossPayInfoPresented)
    }
}
