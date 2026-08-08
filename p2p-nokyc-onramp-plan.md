# P2P On-Ramp — No-KYC Route (betmoar / PlasmaPay)

> Written in `ios-zapp` only because the write was blocked in `betmoar`.
> **Destination: `betmoar/docs/p2p-nokyc-onramp-plan.md`.** All paths below are relative to `betmoar/`.

"Add money → pay by UPI → bettable balance" for a user who has **never verified anything**.

Companion to `docs/p2p-onramp-plan.md` (the self-serve build) and `docs/p2p-integration.md` (protocol
reference — bare `§` points there). This is a **second route into the same machine**, not a rewrite.

Unverified items flagged **[CONFIRM]**.

---

## 0. Decisions

|                  | Choice                                       | Why                                                                                                                               |
| ---------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Mechanism        | **Operator places the order**                | RP lives on the placer. Move the placer and the verification wall disappears — no protocol change, no contract.                    |
| Integration path | **direct-user, from an operator EOA**        | Same path we use today (`§1`). Not `PlasmaPayCheckoutIntegrator` — that one is liveness-gated, which is the thing we are removing. |
| Fiat leg         | **User pays the merchant directly**          | Unchanged. We never touch INR — no rails, no float, no MSB posture change.                                                        |
| `recipientAddr`  | **User's Privy deposit address — unchanged** | Already a third-party address today, so this is a drop-in. Everything downstream of settlement is byte-identical.                  |
| Relay identity   | **Operator-held, server-side**               | Follows the placer. Deletes the per-device and lost-key failure modes (§4).                                                        |
| Gas              | **Operator pays**                            | Privy sponsorship leaves the ramp's critical path.                                                                                |
| Coexistence      | **Both routes ship**                         | No-KYC is the default at RP == 0; verified users keep the self-serve path and its higher RP-scaled cap.                            |
| Backend          | **New private Worker `bm-ramp`**             | We run nine Workers already; this one is different in kind — it holds a hot key. Separate repo, secrets, deploy (§5).              |
| Currency         | **INR** first                                | Unchanged.                                                                                                                        |

---

## 1. Why this is small

The only KYC in the product is one line in `src/lib/ramp/buy.ts:54`:

```ts
/** RP is zero: `placeOrder` would revert `USER_HAS_NO_REPUTATION`. */
| { readonly phase: 'needs_verification' }
```

Reputation is a property of **whoever calls `placeOrder`**. Reclaim socials, hosted KYC and Anon
Aadhaar exist only to move the *user* from RP 0 to RP > 0. If an operator account with standing RP
places the order instead, the user needs none of it.

This is a small change rather than an architecture because **we never settled to the user's own
wallet in the first place**. `recipientAddr` is already the Privy deposit address
(`p2p-onramp-plan.md §2`). The operator supplies identity; the money path does not move:

```
 today   user (RP > 0) ── placeOrder(recipientAddr = privy deposit) ──► Base ──► Polygon ──► balance
 no-KYC  operator      ── placeOrder(recipientAddr = privy deposit) ──► Base ──► Polygon ──► balance
                          └── identity only; never custodies value
```

Not theoretical: production order `659007` on the mainnet Diamond is exactly this shape — one account
at **475 RP** placing BUY orders whose `recipientAddr` is a different address every time.

**We custody nothing.** The operator is an identity, not a treasury.

---

## 2. The money path

```
 user taps "Add money"                            RP == 0, no verify wall
   │
   ├─ POST /v1/orders  { inrAmount, recipientAddr, deviceAuth }
   │     └─ Worker: selects circle, placeOrder(type 0) as OPERATOR      §6.3
   │        recipientAddr = the user's Privy deposit address
   │        pubKey        = per-order operator relay key
   │
   ├─ poll GET /v1/orders/:id → accepted (merchant, ~20-90s)
   │
   ├─ Worker decrypts encUpi with the relay key, returns the handle
   │     └─ client renders upi://pay?pa=…&tr=<orderId>   (PayStep, unchanged)
   │     └─ USER PAYS IN THEIR UPI APP                    (unchanged)
   │
   ├─ POST /v1/orders/:id/paid → Worker calls paidBuyOrder(orderId)
   │     └─ merchant completeOrder → USDC lands at deposit_address
   │
   ├─ waitForDeposit → waitForCompletion  (Privy bridges + swaps)        unchanged
   │
   └─ invalidate queryKeys.balance()                                     unchanged
```

Zero on-chain writes from the browser. No native token, no sponsorship, no wallet signature for the
ramp itself — only the request signature in §5.3.

---

## 3. UI as it stands, and what moves

### 3.1 What exists

`src/components/ramp/AddMoneySheet.tsx` is a pure step router over the `BuyState` machine — it owns
routing "and nothing else", every step is presentational. That is why this change barely touches the UI.

| Phase                                            | Component                                                    | No-KYC route            |
| ------------------------------------------------ | ------------------------------------------------------------ | ----------------------- |
| `idle` / `checking_rp`                           | `Skeleton`                                                   | Kept, shorter           |
| `needs_verification`                             | `VerifyStep.tsx` (10.1 KB)                                   | **Skipped entirely**    |
| `amount`                                         | `AmountStep.tsx`                                             | Kept, operator cap      |
| `quoting` / `placing`                            | `WaitingStep` (`variant="placing"`)                          | Kept                    |
| `awaiting_merchant`                              | `WaitingStep`                                                | Kept                    |
| `awaiting_payment`                               | `PayStep.tsx` — QR + UPI handle + `CopyButton` + `Countdown` | **Kept verbatim**       |
| `confirming_paid`                                | `WaitingStep`                                                | Kept                    |
| `awaiting_settlement`                            | `WaitingStep`                                                | Kept                    |
| `bridging`                                       | `WaitingStep`                                                | Kept                    |
| `done`                                           | `DoneStep.tsx`                                               | Kept                    |
| `expired` / `cancelled` / `timed_out` / `failed` | `OutcomeStep.tsx`                                            | Kept, `onVerify` hidden |

Design system: Tailwind 4 over CSS custom properties in `src/styles/index.css` — `--color-bg #07090d`,
`--color-raised`, `--color-line`, `--color-muted`, `--color-faint`, `--color-brand #5b83ff`. Dark end
to end, which is why `PaymentQr` puts a white plate behind the code for scanner contrast. **No new
tokens or primitives needed.**

### 3.2 The only real UI work

1. **`AmountStep.tsx`** — an upsell row: current cap, "Verify to raise your limit" → the existing
   verification flow. The one place the two routes meet.
2. **`AddMoneySheet.tsx`** — drop `needs_verification` from `HEADINGS` on this route; `back` logic
   simplifies (no `canPlaceAlready`, no Aadhaar `locked` case).
3. **`GasNotice.tsx`** — not rendered on this route. The operator pays gas.
4. **Copy** — one line on `AmountStep` stating no ID is required, and what the cap is.

`VerifyStep.tsx`, `use-verification.ts`, `aadhaar*.ts` and `reputation.ts` all **stay** — the verified
route still uses them.

---

## 4. Relay identity — a failure mode we delete

`src/lib/ramp/relay-identity.ts` documents consequences that are load-bearing today:

- the store must be persistent (SDK default is in-memory);
- scoped per wallet;
- **per _device_** — "an order started on desktop cannot be paid on a phone";
- a corrupt value raises `RELAY_IDENTITY_CORRUPT` and is never silently regenerated.

The relay key follows the placer. With the operator placing, it lives server-side, so on this route:

- the desktop→phone restriction **disappears** — the Pay screen drops its warning;
- `RELAY_IDENTITY_CORRUPT` becomes unreachable;
- clearing site data can no longer strand an open order.

Use a **per-order** operator keypair, not one global key: a leak then exposes one merchant handle
rather than the whole book. `isRelayStorageAvailable()` gating on `AmountStep` is unnecessary here.

---

## 5. Backend — `bm-ramp` (new private repo)

We run nine Workers already (`bm-gamma`, `bm-clob`, `bm-data`, `bm-relayer`, `bm-bridge`, `bm-ws`,
`bm-live`, `bm-geo`, `bm-fraud`, `bm-reclaim`). Those are stateless proxies. This one holds a hot key
and per-user order rows, so it does **not** belong in `workers/api-proxy` or in the app repo.

### 5.1 Endpoints

| Method | Path                    | Purpose                                                                                    |
| ------ | ----------------------- | ------------------------------------------------------------------------------------------ |
| `GET`  | `/v1/config`            | Cap, corridor enablement, kill switch, auth nonce                                          |
| `POST` | `/v1/quote`             | `{inrAmount}` → `{grossUsdc, netUsdc, rate, fees, min, max, quoteId, expiresAt}`            |
| `POST` | `/v1/orders`            | `{quoteId, recipientAddr, deviceAuth}` → `{orderId, phase}`                                |
| `GET`  | `/v1/orders/:id`        | `{phase, paymentInstruction?, txHash?, expiresAt}` — handle released only after acceptance |
| `POST` | `/v1/orders/:id/paid`   | Calls `paidBuyOrder`                                                                       |
| `POST` | `/v1/orders/:id/cancel` | Pre-payment cancel                                                                         |

`paymentInstruction` reuses the existing `PaymentInstruction` union from
`src/lib/ramp/payment-intent.ts`, so `PayStep` needs no new shape.

### 5.2 Keys and state

- Operator EOA in **Cloudflare Secrets Store**, never in `wrangler.jsonc` or a plain var.
  **[CONFIRM]** whether Workers can reach a KMS for signing, or whether signing needs a separate
  signer service.
- Per-order relay keys and order rows in **D1**; nonce/idempotency in **KV**.
- Order polling via a **Durable Object** or Cron trigger — a browser tab closing must not abandon an
  order mid-flight.
- The Worker is the only writer of `paidBuyOrder`. **Never auto-retry it**: a false positive burns
  operator reputation, the asset this whole route rests on.

### 5.3 Auth without accounts

Sign requests with the user's existing Privy wallet over a nonce from `/v1/config`. The recovered
address is the rate-limit key. No email, no phone, no PII — otherwise we reintroduce by the back door
exactly what this route removes. Reuse `bm-fraud` and `bm-geo` for velocity and jurisdiction.

---

## 6. Client changes — file by file

| File                                        | Change                                                                                                                                                                                      |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/lib/ramp/buy.ts`                       | Add `route: 'self' \| 'operator'` to `BuyContext`. On `operator`, `begin` → `amount` directly; `reputation_missing` unreachable. Phase union otherwise **unchanged**.                         |
| **NEW** `src/lib/ramp/operator.ts`          | Typed client for §5.1 (`neverthrow` `Result`, matching `orders.ts`)                                                                                                                          |
| **NEW** `src/lib/ramp/route.ts`             | Route choice: RP > 0 and verified → `self`; else `operator` if enabled                                                                                                                       |
| `src/lib/ramp/use-ramp.ts`                  | Branch each transition on `route`; on `operator` swap `placeOrder` / `getOrder` / `paidBuyOrder` / `decryptPaymentAddress` for Worker calls. Polling, checkpoints and timeouts reused as-is. |
| `src/lib/ramp/orders.ts`                    | No change — the operator path does not call it                                                                                                                                              |
| `src/lib/ramp/sdk.ts`                       | Skip `relayIdentityStore` construction on the operator route                                                                                                                                |
| `src/lib/ramp/checkpoint.ts`                | Persist `route` and `orderId`; resume must not re-derive a local relay key                                                                                                                  |
| `src/lib/ramp/errors.ts`                    | New codes: `OPERATOR_UNAVAILABLE`, `OPERATOR_CAP_EXCEEDED`, `ROUTE_DISABLED`, `QUOTE_EXPIRED`                                                                                                |
| `src/lib/ramp/config.ts`                    | `isOperatorRouteConfigured()`, `OPERATOR_API_URL`, cap constants                                                                                                                            |
| `src/lib/ramp/preflight.ts`                 | Cap from `/v1/config` instead of `getUserTxLimit` on this route                                                                                                                             |
| `src/components/ramp/AddMoneySheet.tsx`     | §3.2                                                                                                                                                                                        |
| `src/components/ramp/steps/AmountStep.tsx`  | Cap display + "verify to raise your limit"                                                                                                                                                  |
| `src/components/ramp/steps/OutcomeStep.tsx` | Hide `onVerify` when `route === 'operator'`                                                                                                                                                 |
| `src/components/ramp/steps/PayStep.tsx`     | Drop the device-mismatch warning on this route                                                                                                                                              |
| `.env.example` / `.env.mainnet`             | `VITE_OPERATOR_API_URL`, route flag                                                                                                                                                         |

Tests: extend the `buy.ts` reducer suite for `route: 'operator'`; mock-server tests for `operator.ts`;
an `AddMoneySheet` routing test asserting `needs_verification` is never entered.

---

## 7. Limits and abuse

The operator's RP is **shared across every no-KYC user**, and P2P scales the per-tx cap by RP
(`getUserTxLimit(address, currency)`). Therefore:

- Per-user cap must sit **well under** the operator's protocol cap, enforced server-side.
- Per-device, per-IP and global daily velocity caps. Client-side limits are advisory only.
- Monitor `reputationPoint` on the operator. A dispute-rate spike degrades every user at once.
- Kill switch in `/v1/config` the client must honour.
- Give the D1 schema an `operatorId` column now, even at one operator — sharding later is otherwise
  a migration.

---

## 8. Risks

**Operator RP is a single point of failure.** One account carries every no-KYC user. Losing it halts
the route for everyone, and a fresh account starts at low limits with no history. Plan the RP ramp
before launch. **[CONFIRM]** whether we bootstrap a new operator or season one first.

**Dispute liability sits with the operator.** The user pays the merchant directly, but the *operator*
is the on-chain counterparty. Decide who absorbs a loss and write the runbook before the pilot.

**Success is the trigger.** `docs/no-kyc-cards-research.md §1` reaches this conclusion about card
programmes and it transfers directly: at low volume this is invisible; at material volume the
operator account becomes worth attacking, by fraud rings and by the protocol's own governance alike.
Do not plan for the route to scale indefinitely on one account.

**Concentration is legible.** Every no-KYC order is one account fanning out to distinct recipients —
the exact signature `659007`'s operator was identified by from chain data in an afternoon. Assume it
is observable and attributable to us.

**Jurisdiction.** This route changes who the counterparty is, not where the user is. Keep `bm-geo`
enforcement on it, and get the licensing position reviewed before the mainnet pilot rather than after.

---

## 9. Phasing

1. **Contract freeze** — write §5.1 as OpenAPI in the new repo; generate client types. Unblocks parallel work.
2. **Worker MVP** — operator account, circle selection, place/poll/paid, per-order relay keys, UPI decrypt. Sepolia first.
3. **`route.ts` + `operator.ts`** — client against a mock server; reducer tests.
4. **`use-ramp` branching** — operator route end-to-end on Sepolia, UI untouched.
5. **UI polish** — `AmountStep` cap + upsell, sheet routing, copy.
6. **Hardening** — caps, kill switch, fraud/geo wiring, RP alerting, dispute runbook.
7. **Mainnet pilot** — low per-user cap, capped global daily volume, monitored operator RP.
