# P2P Custodial Onramp — Implementation Plan (Android)

> Staged copy. **Destination: `zodl-android/docs/P2P_CUSTODIAL_ONRAMP_PLAN.md`** — where it is
> already written; this duplicate exists only so both plans sit together for review.
> All paths below are relative to `zodl-android/`.

Fiat (INR/UPI) → USDC on Base → shielded ZEC, where the **P2P order is placed by a Zapp-operated
account**, not by the user. The end user never needs KYC on the P2P network: reputation and identity
sit with the operator account, exactly as observed in production order `659007`.

Corridor at launch: **INR / UPI**. Payment model: **the user pays the merchant directly** — Zapp
never touches fiat.

---

## 1. What already exists (reuse inventory)

### 1.1 Branch `feature/p2p-onramp` (in `.git-side-work/p2p-onramp`)

A complete **non-custodial** onramp: the user's own ERC-4337 smart account places the order, gated by
ZKPassport + on-chain reputation. Decision: **keep the UI and state machine, replace the driver.**

| Path | ~LOC | Action |
|---|---|---|
| `offramp-lib/…/onramp/OnrampStatus.kt` | 98 | **Keep** — status/stage model is correct as-is |
| `offramp-lib/…/onramp/OnrampModels.kt` | 96 | **Keep + extend** (enable `ShieldedZec`, add quote/deposit) |
| `offramp-lib/…/onramp/OnrampOrchestrator.kt` | 384 | **Delete** — on-chain orchestration moves server-side |
| `offramp-lib/…/onramp/AaOnrampDriver.kt` | 65 | **Replace** with `CustodialOnrampDriver` |
| `offramp-lib/…/verification/*` (3 files) | 221 | **Delete** — reputation gating is the operator's problem |
| `ui-lib/…/screen/onramp/OnrampView.kt` | 559 | **Keep + edit** (strip verifier UI, add UPI pay screen) |
| `ui-lib/…/screen/onramp/OnrampVM.kt` | 413 | **Rewrite core**, keep shape |
| `ui-lib/…/screen/onramp/OnrampState.kt` | 56 | **Keep + edit** |
| `ui-lib/…/screen/onramp/OnrampProgressMapper.kt` | 81 | **Keep** |
| `ui-lib/…/screen/onramp/OnrampScreen.kt` | 22 | **Keep** |
| `ui-lib/…/screen/onramp/OnrampPreviews.kt` | 116 | **Keep + edit** |
| `ui-lib/…/screen/onramp/ZkPassport{Params,WebView}.kt` | 147 | **Delete** |
| `ui-lib/…/provider/OnrampCheckpointStorageProvider.kt` | 33 | **Keep** |
| `ui-lib/…/provider/OnrampVerificationMarkerProvider.kt` | 51 | **Delete** |
| `ui-lib/…/provider/VerificationHttpClientProvider.kt` | 26 | **Delete** |
| `ui-lib/…/usecase/NavigateToOnrampUseCase.kt` | 15 | **Keep** |
| `ui-lib/…/WalletNavGraph.kt` | +3 | **Keep** |
| `ui-lib/src/main/res/ui/onramp/values*/strings.xml` | 81×2 | **Keep + extend**, add missing locales |
| `ui-lib/src/test/…/OnrampProgressMapperTest.kt` | 37 | **Keep** |

Net: roughly **1,200 LOC reused, ~800 deleted, ~900 new**.

### 1.2 Already on `main` — do not rebuild

- **`evm-lib`** — `EvmKeyDerivation` (BIP44 `m/44'/60'/0'/0/i` from the **Zcash mnemonic**, so the
  user's Base address is deterministic from their existing seed), `Erc4337Submitter`,
  `ThirdwebSmartAccount`, `AbiEncoder`, `BaseRpcClient`, `Ecies`.
- **`offramp-lib`** — `P2pNetworks` (mainnet Diamond `0x4cad6eC9…`, USDC, EntryPoint v0.6),
  `DiamondCalls`, `CircleRouter`, `SubgraphClient`, `OrderReadSource`, `UpiQrParser`,
  **`UpiPayUri`**, `PaymentAddressDecryptor`, `RelayIdentityStore`, `Usdc6`.
- **Swap** — `SwapRepository.requestExactInputIntoZec(amount, refundAddress, destinationAddress)`
  backed by NEAR Intents 1Click (`1click.chaindefuser.com/v0`). **This is the USDC→ZEC leg; reuse it.**
- **UI patterns** — `OfframpStepRow`, `OfframpStatusToSteps`, `UpiOfframpProgressVM`,
  `NumberTextFieldState`, Koin `viewModelOf` modules.

> Before editing any `.kt`, load `.claude/skills/zapp-style/SKILL.md` (ZappTheme, file triad, Detekt rules).

---

## 2. Architecture

### 2.1 Flow

```
User (app)                Backend (new repo)            P2P Diamond / Base        Merchant
   │                             │                              │                    │
   │ 1. POST /quote              │                              │                    │
   │◄─── rate, limits, fees ─────│                              │                    │
   │ 2. POST /orders             │                              │                    │
   │    {inrAmount, zecAddr,     │ 3. selects circle,           │                    │
   │     baseAddr, deviceSig}    │    places BUY as OPERATOR    │                    │
   │                             │    recipientAddr = §2.2 ────►│ placeOrder         │
   │                             │    pubKey = order relay key  │                    │
   │◄─── orderId, status ────────│                              │                    │
   │                             │◄─── merchant accepts ────────│◄─── accept ────────│
   │                             │ 4. decrypts encMerchantUpi   │                    │
   │◄─── UPI id + amount + QR ───│    with the relay key        │                    │
   │ 5. USER PAYS UPI ───────────┼──────────────────────────────┼───────────────────►│
   │ 6. POST /orders/:id/paid    │───► markPaid ───────────────►│                    │
   │                             │                              │◄─── confirms ──────│
   │                             │        USDC settles to recipientAddr              │
   │ 7. USDC→ZEC swap (§2.2)     │                              │                    │
   │◄─── shielded ZEC ───────────┴──────────────────────────────┘                    │
```

**Zapp never handles fiat.** The operator account supplies on-chain identity/reputation only; the
INR leg is a direct user→merchant UPI payment.

### 2.2 Routing modes — one config field, pick per environment

`recipientAddr` on the P2P order decides everything downstream.

**Mode A — direct to the user's own Base account (recommended, ship this first).**
`recipientAddr` = the user's Base address, already derivable from their Zcash seed via
`EvmKeyDerivation`. USDC settles straight into the user's self-custodied account; the app then runs
the **existing** `requestExactInputIntoZec` swap. **Zapp custodies nothing.** Step 7 is client-side
and already built. Requires the user's Base account to hold a little ETH for the swap
transaction — the app already solves this (`BridgeToBaseVM`, `PreFundedOfframpFunding`).

**Mode B — pooled treasury (what order `659007` actually does).**
Backend derives a fresh deposit EOA per order, funds its gas from a funder key, `recipientAddr` =
that EOA, then sweeps to a treasury and performs the swap server-side. Adds a hot-wallet custody
window, a sweeper, a gas funder, and a reconciliation ledger. Justified only if you need to hide
Base from the user entirely, batch swaps, or absorb swap failures centrally.

> Do **not** set `recipientAddr` directly to a 1Click deposit address. Those quotes expire on a short
> window, and a P2P order can sit for many minutes between placement, merchant acceptance, the user's
> UPI payment, and confirmation. The swap quote must be fetched **after** USDC lands, which is exactly
> why an intermediate address (the user's own account in Mode A) is required.

Build Mode A. Keep the `recipientAddr` strategy behind an interface so Mode B is a backend-only
change with **zero** Android impact.

### 2.3 Custody & liability

| Mode | Zapp holds fiat | Zapp holds USDC | New licensing exposure |
|---|---|---|---|
| A | No | No | Minimal — order placement only |
| B | No | Yes (minutes–hours) | Custody of customer crypto |

---

## 3. Backend — new private repo `zapp-onramp-service`

**It must be a separate private repo.** `zodl-android` is a public FOSS fork; operator hot keys, the
relay-key store, and per-user order data cannot live there or in its CI.

### 3.1 Components

1. **Operator account** — the reputation-bearing P2P identity that places every BUY. Single account
   at launch (the traced production operator runs one at 475 RP). Reputation is the scarce asset:
   losing it to a dispute rate spike halts the whole product. Track `reputationPoint` and alert.
2. **Relay-key service** — an ECDH keypair **per order** (not per user). The order's `pubKey` is the
   relay public key; the service decrypts `encMerchantUpi` and returns the UPI handle to the app.
   Per-order keys mean a leaked key exposes one merchant handle, not the whole book.
   Mirrors `RelayIdentityStore` / `PaymentAddressDecryptor` semantics — reuse the Kotlin logic as the
   parity reference (`ViemCalldataParityTest`, `MerchantPayloadParityTest`).
3. **Order orchestrator** — circle selection (port `CircleRouter`), `placeOrder`, poll for merchant
   acceptance, `markPaid`, watch settlement, expiry/auto-cancel.
4. **Key management** — KMS/HSM for the operator key. No plaintext keys on disk or in env vars.
5. **Ledger** — every order: user id, orderId, amounts, recipientAddr, status transitions, tx hashes.
   Needed for support and dispute defence.
6. **(Mode B only)** deposit-address deriver, gas funder, sweeper, treasury, server-side swap.

### 3.2 API contract

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/quote` | `{fiatAmount, currency, rail}` → `{usdcAmount, rate, fees, min, max, quoteId, expiresAt}` |
| `POST` | `/v1/orders` | `{quoteId, fiatAmount, recipientAddr, destination, deviceAuth}` → `{orderId, stage}` |
| `GET` | `/v1/orders/{id}` | → `{stage, orderId, paymentInstructions?, txHash?, usdcReceived?, expiresAt}` |
| `POST` | `/v1/orders/{id}/paid` | User asserts UPI payment sent |
| `POST` | `/v1/orders/{id}/cancel` | User cancels before payment |
| `GET` | `/v1/orders?cursor=` | History for the device identity |
| `GET` | `/v1/config` | Corridor enablement, limits, kill switch |

`paymentInstructions` = `{rail, paymentAddress, fiatAmount, payUri, expiresAt}` — the decrypted
merchant UPI, released **only** after acceptance.

**Auth:** sign requests with the user's existing Base EOA key (`EvmKey.signRecoverable`) over a
nonce from `/v1/config`. No accounts, no passwords, no PII. Rate-limit per recovered address.

**Abuse:** the operator's reputation is shared across all users. Enforce per-device and global
velocity caps, a per-order fiat ceiling, and a global daily cap server-side, plus a kill switch in
`/v1/config` the app must honour.

---

## 4. Android changes — complete file list

### 4.1 `offramp-lib` (KMP — also compiles for iOS; keep `commonMain`)

| File | Action |
|---|---|
| `…/onramp/OnrampStatus.kt` | Keep. Add `OnrampFailureCode`: `QUOTE_EXPIRED`, `BACKEND_UNAVAILABLE`, `LIMIT_EXCEEDED`, `CORRIDOR_DISABLED` |
| `…/onramp/OnrampModels.kt` | Set `OnrampDestination.isEnabled` true for `ShieldedZec`. Add `OnrampQuote`, `OnrampLimits`, `OnrampOrderSummary`. Extend `OnrampCheckpoint` with `quoteId`, `recipientAddr`, `swapDepositAddress?` |
| `…/onramp/OnrampStage` (in `OnrampModels.kt`) | Add `SWAPPING_TO_ZEC` between `RECEIVING_USDC` and `COMPLETED` |
| `…/onramp/OnrampDriver.kt` | Keep interface (`start`/`confirmPaid`/`resume`/`cancel` → `Flow<OnrampStatus>`) |
| **NEW** `…/onramp/CustodialOnrampClient.kt` | Ktor client for §3.2. Serializable DTOs |
| **NEW** `…/onramp/CustodialOnrampDriver.kt` | Implements `OnrampDriver`; polls `GET /orders/{id}`, maps → `OnrampStatus` |
| **NEW** `…/onramp/OnrampRequestSigner.kt` | EIP-191 request signing via `EvmKey` |
| **NEW** `…/onramp/OnrampBackendConfig.kt` | Base URL per flavour |
| **DELETE** | `OnrampOrchestrator.kt`, `AaOnrampDriver.kt`, `verification/*` |
| **NEW tests** | `CustodialOnrampDriverTest`, `OnrampRequestSignerTest`, keep `OnrampCheckpointPrivacyTest` |

### 4.2 `ui-lib` — screens (`…/ui/screen/onramp/`)

| File | Action |
|---|---|
| `OnrampScreen.kt` | Keep. `OnrampArgs` gains `destination: String` |
| `OnrampState.kt` | Remove `selectedVerifier`, `zkPassportConfig`, `verifierStatus`, `onVerifierEvent`, `onSelectVerifier`. Add `quote`, `limits`, `payUri`, `qrPayload`, `expiresAtMillis`, `zecDestination`, `onCopyUpiId`, `onOpenUpiApp`, `onShareQr` |
| `OnrampState.OnrampMode` | Drop `CONSENT`. Keep `LOADING, LANDING, AMOUNT, CONFIRMATION, PROGRESS, PAYMENT, COMPLETION` |
| `OnrampVM.kt` | Rewrite internals against `CustodialOnrampDriver`; drop ZK/verifier state; add quote refresh + countdown; keep checkpoint persist/restore |
| `OnrampView.kt` | Strip verifier/consent composables. **New** `OnrampPaymentSection`: merchant UPI id, amount, QR, "Open UPI app", "Copy UPI ID", countdown, "I've paid", "Cancel" |
| `OnrampProgressMapper.kt` | Add `SWAPPING_TO_ZEC` row |
| `OnrampPreviews.kt` | Update for new state |
| **DELETE** | `ZkPassportParams.kt`, `ZkPassportWebView.kt` |
| **NEW** `OnrampAmountSection.kt` | Amount entry + live quote + limit validation (`NumberTextFieldState`) |
| **NEW** `OnrampDestinationPicker.kt` | Base USDC vs shielded ZEC |
| **NEW** `OnrampQrCard.kt` | UPI QR render (reuse the offramp QR component) |

### 4.3 `ui-lib` — plumbing

| File | Action |
|---|---|
| `…/provider/OnrampCheckpointStorageProvider.kt` | Keep |
| **DELETE** | `OnrampVerificationMarkerProvider.kt`, `VerificationHttpClientProvider.kt` |
| **NEW** `…/provider/OnrampBackendClientProvider.kt` | Builds `CustodialOnrampClient` |
| **NEW** `…/repository/OnrampRepository.kt` | Quote cache, config/kill switch, order history |
| `…/usecase/NavigateToOnrampUseCase.kt` | Keep |
| **NEW** `…/usecase/GetOnrampLimitsUseCase.kt`, `ObserveOnrampOrderUseCase.kt` | |
| **NEW** `…/usecase/SwapOnrampProceedsToZecUseCase.kt` | Mode A step 7 — wraps `requestExactInputIntoZec` |
| `…/WalletNavGraph.kt` | Keep the 3-line `composable<OnrampArgs>` |
| `…/screen/home/HomeVM.kt` | Entry point already wired via `NavigateToOnrampUseCase` — gate on `/v1/config` |
| `di/UseCaseModule.kt` | Register new use cases |
| **NEW** `di/OnrampViewModelModule.kt` | `viewModelOf(::OnrampVM)` — mirror `OfframpViewModelModule.kt` |
| `di/*` | Register provider + repository |

### 4.4 Resources

- `res/ui/onramp/values/strings.xml` — extend; add **`values-es`, `values-pt`, `values-in`, `values-b+id`**
  (branch only has `values` + `values-es`).
- New strings: UPI payment instructions, countdown, copy/open-app actions, limit + quote-expiry
  errors, swap-to-ZEC progress, corridor-disabled notice.
- `res/ui/integrations/values*/strings.xml` — Buy entry label.

### 4.5 Tests

- Unit: `CustodialOnrampDriverTest` (stage mapping, poll backoff, expiry), `OnrampVMTest`,
  `OnrampProgressMapperTest` (extend), `OnrampRequestSignerTest`.
- Parity: reuse `ViemCalldataParityTest` / `MerchantPayloadParityTest` as the reference for
  backend relay-decrypt correctness.
- Screenshot: `ui-screenshot-test` for `PAYMENT` and `COMPLETION` modes.

---

## 5. Failure & recovery matrix

| Failure | Detection | Handling |
|---|---|---|
| No merchant accepts | `WAITING_FOR_MERCHANT` timeout | Backend cancels; app offers retry with a new circle |
| User never pays | Order expiry | Backend auto-cancels; `CANCELLED` |
| User paid, merchant disputes | Order status → disputed | `Failed(ORDER_DISPUTED)`; manual support path via ledger |
| Quote expired pre-order | `expiresAt` | Re-quote in-place; never silently re-price |
| USDC landed, swap fails (Mode A) | Swap status | **Do not fail the onramp** — USDC is in the user's own account; surface "swap again" |
| Backend down mid-order | Poll failure | `OnrampCheckpoint` in storage; resume on relaunch (already supported) |
| Operator reputation collapse | `reputationPoint` monitor | `/v1/config` kill switch disables the entry point |
| App killed during payment | Checkpoint | `resume(checkpoint)` restores `PAYMENT` with instructions |

Never auto-retry `markPaid` — a false positive burns operator reputation.

---

## 6. Milestones

1. **Contract freeze** — write §3.2 as an OpenAPI file in the new repo; generate/hand-write Kotlin DTOs. Unblocks parallel work.
2. **Backend MVP** — operator account, circle selection, place/poll/markPaid, per-order relay keys, UPI decrypt, Mode A `recipientAddr`. Base Sepolia first (`P2pNetworks.SEPOLIA` already configured).
3. **`offramp-lib` driver** — client, driver, signer + tests against a mock server.
4. **UI port** — cherry-pick the branch, delete ZK surface, wire the new driver, build the payment screen.
5. **Swap leg** — `SwapOnrampProceedsToZecUseCase`, ZEC destination end-to-end.
6. **Hardening** — limits, kill switch, velocity caps, reputation alerting, dispute runbook, localisation.
7. **Mainnet pilot** — capped daily volume, single corridor, monitored operator reputation.

---

## 7. Open items

- **Operator reputation bootstrap.** A new operator account starts at 0 RP with low limits. Plan the
  ramp (seed volume, or acquire/reuse an existing seasoned account) before the pilot — this gates launch.
- **Dispute liability.** The user pays the merchant directly, but the *operator* is the on-chain
  counterparty in a dispute. Decide who absorbs a loss and document the runbook.
- **Multi-operator sharding.** One account is a single point of failure for reputation and velocity.
  Design the ledger with an `operatorId` column now, even at one operator.
- **iOS.** `offramp-lib` is KMP and `AppleOfframpBridge` exists — keep all new onramp code in
  `commonMain` so iOS is a UI-only lift later.
- **Mode B trigger.** Define what would make us move custody server-side, so it is a deliberate
  decision rather than drift.
