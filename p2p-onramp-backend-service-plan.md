# P2P Onramp Operator Service — Shared Backend

> Staged copy. **Destination: a new private repo, `p2p-onramp-operator`.**
> Companion to `p2p-custodial-onramp-plan-ANDROID.md` (Zapp) and `p2p-nokyc-onramp-plan.md` (betmoar).
> Neither app repo may host this: `zodl-android` is a public FOSS fork, and this service holds a hot key.

One service, one operator identity, two consumers: **Zapp** (Android/KMP, fiat → USDC → shielded ZEC)
and **betmoar/PlasmaPay** (React SPA, fiat → USDC → Polygon pUSD → bettable balance).

Unverified items flagged **[CONFIRM]**.

---

## 0. Decisions

|                     | Choice                                                  | Why                                                                                                                    |
| ------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Shape               | **One service, multi-tenant by `appId`**                | The order lifecycle is identical for both apps. Only `recipientAddr` differs, and that is a request parameter.            |
| Operator identity   | **One shared EOA** behind an **operator-pool interface** | What was asked. The interface means splitting per-app later is a config change, not a migration (§3.4).                  |
| Runtime             | **Cloudflare Workers + Durable Object + D1**            | betmoar already runs nine Workers. The DO is not a preference — it is the only clean answer to nonce serialisation (§3.1). |
| Signing             | **KMS / Secrets Store, never a plain var**              | The key can place orders and assert fiat receipt. It is the whole trust boundary.                                        |
| Protocol client     | **`@p2pdotme/sdk`** (TS)                                | betmoar already depends on `^1.2.8`. Zapp's Kotlin port becomes an independent parity check (§8.3).                      |
| Fiat                | **Never touched**                                       | User pays the merchant directly on both apps. The service moves no fiat and holds no float.                              |
| Custody             | **None**                                                | USDC settles to `recipientAddr`, never to us. The operator is an identity, not a treasury.                               |
| Corridor            | **INR / UPI** first                                     | Both apps chose it independently.                                                                                        |
| Screening           | **Behind a `ScreeningProvider` interface**              | Mandatory for INR and its failure is silent (§8). Which address the record binds to is unconfirmed, so both branches stay buildable. |

---

## 1. Why one service is the right call

The two apps look different and are not. Strip the UI and both reduce to the same five server actions
against the same Diamond (`0x4cad6eC90e65baBec9335cAd728DDC610c316368`, Base mainnet):

```
select circle → placeOrder(type 0, recipientAddr, pubKey) → poll accept
              → decrypt encUpi → return handle → paidBuyOrder(orderId)
```

| | Zapp | betmoar | Shared? |
| --- | --- | --- | --- |
| Corridor | INR / UPI | INR / UPI | ✅ |
| Diamond, USDC, subgraph | mainnet | mainnet | ✅ |
| Order lifecycle | identical | identical | ✅ |
| Relay key + `encUpi` decrypt | server-side | server-side | ✅ |
| Auth key | Base EOA from the Zcash seed (BIP44 `m/44'/60'/0'/0/i`) | Privy embedded wallet | ✅ both secp256k1 → one EIP-191 scheme |
| `recipientAddr` | user's own Base account | user's Privy deposit address | ⚠️ parameter, not logic |
| Post-settlement | client swaps USDC→ZEC (NEAR 1Click) | Privy bridges to Polygon | ❌ **outside the service** |
| Client language | Kotlin (KMP `commonMain`) | TypeScript | ❌ two generated clients, one spec |

The divergence is entirely *after* USDC lands. The service stops at settlement, so it does not care
which app it is serving beyond quotas and `recipientAddr` policy.

---

## 2. What sharing one EOA actually costs

Asked for and delivered, but these are the consequences and they are not small. Read this section
before §3.

### 2.1 One nonce sequence

An EOA has a single monotonic nonce. Two apps placing orders concurrently will race it, and a gap or
a duplicate nonce stalls **every** pending transaction, not just the loser's. This is the single
hardest engineering constraint in the design and it is why §3.1 exists.

### 2.2 One reputation, shared blast radius

RP attaches to the address that calls `placeOrder`. Therefore:

- P2P scales the per-tx cap by RP (`getUserTxLimit(address, currency)`), so **both apps draw from one
  cap**. betmoar's volume shrinks what Zapp can place, and vice versa.
- A dispute spike caused by app A degrades app B within the same hour.
- A malicious user of either app is attacking the other app's availability.
- The reference operator (order `659007`) sits at **475 RP**. A fresh operator starts at zero and
  cannot place at all — bootstrap is a launch-blocking dependency for *both* products simultaneously.

### 2.3 One throughput ceiling

Two transactions per order (`placeOrder`, `paidBuyOrder`). Serialised signing on Base's 2s blocks is
comfortable at hundreds of orders/day and tight at thousands/hour. Pipelined nonces raise this, but
the ceiling is shared and arrives for both apps at once.

### 2.4 Correlation

Both apps' orders originate from one address with a fan-out of distinct recipients — the exact
signature that identified `659007`'s operator from chain data in an afternoon. Sharing an EOA
**publicly links Zapp and betmoar on-chain.** If those brands are meant to be separable, this
decision undoes that, and it is not reversible for orders already placed.

> Everything above is a reason to keep §3.4's pool interface honest, not a reason to refuse the ask.
> One EOA today, two config lines to split.

---

## 3. Architecture

```
  Zapp (KMP)        betmoar (SPA)
       │                  │        EIP-191 signed, appId-scoped
       └────────┬─────────┘
                ▼
        Worker  p2p-onramp-operator            ← stateless: auth, quota, validation
                │
        ┌───────┴────────┬──────────────┐
        ▼                ▼              ▼
   SignerDO         OrderDO(one/order)  D1
   single-writer    lifecycle poller    orders, quotas,
   nonce + signing  paid/cancel         relay keys (wrapped)
        │                │
        └────────┬───────┘
                 ▼
        Base RPC  +  P2P Diamond  +  goldsky subgraph
```

### 3.1 `SignerDO` — one instance, globally

A Durable Object is a single-threaded actor with a stable identity, which is exactly a mutex around
the operator's nonce. **All** signing funnels through one DO instance per operator.

- Allocates nonces strictly in order; never hands out two of the same.
- Holds a bounded in-flight window; on a gap, refuses new work and reconciles against
  `eth_getTransactionCount` rather than guessing.
- Owns fee policy (EIP-1559 bump on stall) so two apps cannot bid against each other.
- Never blocks on order polling — that belongs to `OrderDO`.

Without this, §2.1 becomes a production incident in week one.

### 3.2 `OrderDO` — one per order

Alarms drive the lifecycle: poll for merchant acceptance, decrypt `encUpi`, expire, cancel. A closed
browser tab or a killed Android process must not abandon an order mid-flight — this is the reason
polling cannot live in the client on either app.

### 3.3 Key custody

- Operator private key in **Cloudflare Secrets Store**, injected only into `SignerDO`.
  **[CONFIRM]** whether Workers can call an external KMS/HSM for signing rather than holding raw key
  material; prefer that if available.
- **Per-order** relay keypairs, generated server-side, wrapped at rest in D1. Per-order, not global,
  so a leak exposes one merchant handle rather than the whole book.
- No key material in `wrangler.jsonc`, env vars, logs, or error payloads.

### 3.4 Operator pool — the escape hatch

Do not hard-code one address anywhere above `SignerDO`.

```ts
interface OperatorPool {
  resolve(appId: AppId, amountUsdc: bigint): Promise<OperatorRef>;
}
```

Ship `SingleOperatorPool` (returns the one shared EOA). Splitting later — per app, or sharded for
throughput — becomes a new implementation plus a config flip. Give every D1 row an `operatorId`
column from day one; retrofitting it is a migration across live orders.

---

## 4. API — one spec, two generated clients

`GET /v1/config` · `POST /v1/quote` · `POST /v1/orders` · `GET /v1/orders/:id` ·
`POST /v1/orders/:id/paid` · `POST /v1/orders/:id/cancel` · `GET /v1/orders`

| Field | Notes |
| --- | --- |
| `appId` | `zapp` \| `betmoar`. In the signed payload, not just the header — otherwise a signature from one app replays on the other. |
| `recipientAddr` | Supplied by the client, validated per §5.2. The only app-shaped input. |
| `paymentInstruction` | Union `{upi, qr, fields, plain}` — matches betmoar's existing `payment-intent.ts`, so `PayStep.tsx` needs no new shape. Zapp maps it to `MerchantPaymentInstructions`. |
| `phase` | Server-authoritative. Mirrors betmoar's `BuyState` phases and Zapp's `OnrampStage` — deliberately a superset of both so neither client invents transitions. |

Author it as **OpenAPI first** and generate both clients (`src/lib/ramp/operator.ts`;
`offramp-lib/…/onramp/CustodialOnrampClient.kt`). Two hand-written clients drifting against one
server is the predictable failure mode of a shared backend.

---

## 5. Auth and the `recipientAddr` control

### 5.1 Auth

Nonce from `/v1/config` → client signs `{appId, nonce, method, path, bodyHash}` (EIP-191) → server
recovers the address and rate-limits on it. Both apps already hold a secp256k1 key, so this is one
scheme. No accounts, no email, no PII — reintroducing identity here would defeat the point of the
route.

### 5.2 `recipientAddr` binding — the control that matters

The service lends its reputation to whoever calls it. Unbound, `recipientAddr` lets an authenticated
user route USDC anywhere using our RP. We lose no money (the user pays the fiat), but we become a
routing service of unknown purpose, on our identity. Bind it per app:

- **Zapp** — must equal the authenticated address, or its deterministic smart-account address. The
  integrator design already pins user == recipient; enforce the same server-side.
- **betmoar** — must be the Privy deposit address for the authenticated wallet.
  **[CONFIRM]** this is verifiable server-side via a Privy API; if it is not, that is a real gap and
  needs a compensating control (allowlist on first use + per-address velocity caps) before launch.

Reject anything else. This check is not optional and should fail closed.

---

## 6. Quotas and isolation

Because §2.2 makes the apps each other's noisy neighbour:

- **Per-app budget** — each `appId` gets a share of the operator's daily volume and order count. One
  app cannot consume the shared RP cap.
- **Per-user cap** well beneath the operator's protocol cap, enforced server-side; client limits are
  advisory only.
- **Per-device / per-IP velocity**, reusing betmoar's `bm-fraud` and `bm-geo`.
- **Independent kill switches** per `appId`, plus a global one, surfaced through `/v1/config` and
  honoured by both clients.
- **Circuit breaker on dispute rate** — trips automatically and halts placement before RP is spent.

---

## 7. `paidBuyOrder` is the crown jewel

`placeOrder` risks gas. `paidBuyOrder` asserts *the user has paid fiat*, and a false assertion makes
the merchant release USDC having received nothing — a dispute, RP loss, and a real counterparty loss.

- Idempotent, keyed on `orderId`. Exactly-once semantics, enforced in `OrderDO`.
- **Never auto-retried** on ambiguity. A stuck order escalates to a human; it does not re-fire.
- Callable only by the authenticated owner of that order, only from `awaiting_payment`.
- Rate-limited independently of placement.
- Every call written to an append-only audit log with the recovered signer address.

---

## 8. Screening (fraud engine) — mandatory for INR, and load-bearing

Not optional and not a compliance nicety. Per betmoar's `docs/p2p-integration.md §1`: **the merchant
app rejects any order with no screening record.** The failure is silent — an unscreened order places,
routes and assigns merchants normally, then expires untouched, indistinguishable from "nobody wanted
it". Measured over 65h on circles 1+2: **91%** of BUY orders network-wide were accepted, against
**1 of 20** from betmoar before screening was wired. Once screened, a $2.05 order was accepted in 14s.

An operator route that skips this ships a product where nothing fills and the logs look fine.

### 8.1 How it works today

`createFraudEngine({ apiUrl, encryptionKey, seonRegion })`, then:

```ts
fraud.processBuyOrder({
  signer: { address, signerAddress?, signMessage },   // address = "tracked subject"
  orderDetails, userDetails, orderSource,
  placeOrder: async () => orderId,                    // ⚠ called from INSIDE the engine
})
```

Three properties decide the design:

1. **`placeOrder` is invoked by the engine**, explicitly so the resulting order id is linked to the
   activity record. Screening and placement are one operation, not two.
2. **The signature covers `action:address:timestamp`** and never the path — which is why betmoar's
   `bm-fraud` hostname-rewriting proxy is safe.
3. **It is browser-only.** In Node it produces empty device signals, "which the backend degrades or
   rejects". SEON fingerprinting needs a real browser.

Fail-open on API error; only an explicit `rejected` blocks. Non-INR skips entirely.

### 8.2 The open question, and why the interface is right

> **[CONFIRM with P2P]** Does the merchant match the screening record to the order's **placer** (the
> operator) or to the **linked `orderId`**?

- **If `orderId`** — the client-signed flow works as-is. The client runs `processBuyOrder` with
  `signer.address` = the user and `placeOrder: () => POST /v1/orders`. The engine's callback is async
  and returns the id as a string, so our backend placing the order fits the existing contract
  unchanged. The record is then created against the user's address and linked to an order the
  operator placed.
- **If placer address** — the client forwards signals and the service signs `action:address:timestamp`
  as the operator.

Building it behind an interface either way is correct. But the branches are **not** symmetric, and
the second is the expensive one:

```
ScreeningProvider
  ├─ ClientSignedScreening    (browser runs the engine; backend is just the placeOrder callback)
  └─ OperatorSignedScreening  (backend signs; needs §8.3 to be solved first)
```

`ClientSignedScreening` is a thin shim. `OperatorSignedScreening` requires the SDK to accept
externally-supplied device signals — otherwise a Worker-side call carries empty signals and lands in
exactly the "degrades or rejects" path. **[CONFIRM]** whether the SDK exposes that; if it does not,
the operator-signed branch is not implementable as a module swap and the answer to §8.2 becomes
launch-blocking rather than an implementation detail.

Worth raising with P2P in the same conversation: `signerAddress` already exists so an AA subject can
differ from the key that signs. That is precedent for subject ≠ signer, and the natural question is
whether an operator-placed order can declare the user as subject.

### 8.3 Zapp has no browser — this is a real blocker

betmoar is a browser SPA, so screening is where it already is. **Zapp is a native Android app.**
There is no `window.location.origin`, no SEON fingerprint, no DOM. On the evidence above, an
unscreened Zapp order does not fail loudly — it silently never fills.

Options, in order of preference:

1. **Hidden WebView running the fraud engine.** `feature/p2p-onramp` already ships a WebView for
   ZKPassport (`ZkPassportWebView.kt`), so the pattern, the plumbing and the review precedent exist.
   Keeps signals genuine.
2. **Negotiate a native path with P2P** — a documented signal set Android can produce, or an
   exemption for the operator route.
3. **Operator-signed from the Worker** — only viable if §8.2's signal-forwarding question resolves
   yes, and even then the signals describe a datacentre, not the user.

This applies to Zapp regardless of which way §8.2 resolves, so it is not blocked on that answer and
should be scoped now.

---

## 9. Data, ops, verification

### 9.1 D1 schema (minimum)

`orders(id, appId, operatorId, orderId, userAddr, recipientAddr, inrAmount, usdcAmount, phase,
placeTx, paidTx, createdAt, updatedAt)` · `relay_keys(orderId, wrappedKey)` ·
`quotas(appId, window, used)` · `audit(ts, actor, action, orderId, detail)`

`operatorId` and `appId` present from the first migration (§3.4).

### 9.2 Monitoring

Operator RP (the leading indicator for both products), ETH balance on Base, nonce gap depth,
in-flight order count per app, merchant-acceptance latency, dispute rate per app, `paidBuyOrder`
failure rate. Alert on RP delta, not just absolute value.

**Acceptance rate is the screening canary.** §8's failure mode is silent, so track accepted/placed
per app against the ~91% network baseline and alert on a sustained drop. A screening regression looks
identical to weak merchant liquidity from every other signal.

### 9.3 A free correctness check

Zapp hand-ports the protocol to Kotlin and keeps parity tests (`ViemCalldataParityTest`,
`MerchantPayloadParityTest`); the service uses the TS SDK. Two independent implementations of the
same calldata and payload encoding — wire the Kotlin vectors into this repo's CI as a cross-check on
SDK upgrades. It is nearly free and would catch an encoding regression before it reaches a merchant.

---

## 10. Phasing

0. **Ask P2P §8.2 and §8.3 first.** Both answers change module boundaries, and one of them decides
   whether Zapp's onramp fills at all. Cheap to ask, expensive to discover late.
1. **OpenAPI freeze** + generated clients. Unblocks all three repos in parallel.
2. **`SignerDO`** with nonce serialisation and a fake signer; property-test the nonce invariant under
   concurrency before any real key exists.
3. **`OrderDO` + lifecycle** on Base Sepolia; place/poll/decrypt/paid end-to-end, no UI.
4. **`ScreeningProvider`** — `ClientSignedScreening` first; `placeOrder` callback → `POST /v1/orders`.
5. **betmoar integration** — the smaller lift (`route.ts`, `operator.ts`, phases already match, and
   its screening already works in a browser).
6. **Zapp integration** — `CustodialOnrampDriver`, plus whichever §8.3 option wins.
7. **Quotas, kill switches, circuit breaker, audit log.**
8. **Mainnet pilot, betmoar first**, low caps, monitored RP **and acceptance rate**. Add Zapp only
   after the shared cap behaviour is observed under real load.

---

## 11. Open items

- **[CONFIRM with P2P] Screening subject** (§8.2). Does the merchant match the screening record to the
  order's placer (the operator) or to the linked `orderId`? If `orderId`, the client-signed flow works
  as-is. If the placer address, the client sends signals and the service signs the screening call as
  the operator — same architecture, one module swapped, so it is built behind an interface either way.
  Ask in the same thread whether the SDK accepts externally-supplied device signals, since the
  operator-signed branch is only a module swap if it does.
- **[CONFIRM] Screening from Android** (§8.3). The engine is browser-only and Zapp is native. Decide
  between a hidden WebView (precedent exists in `feature/p2p-onramp`) and a negotiated native path.
  Independent of the question above, and it gates whether Zapp orders fill at all.
- **[CONFIRM] Screening beyond INR** — still open in betmoar's own doc. Decides whether adding a
  corridor is config or a new integration.
- **Operator bootstrap.** A new operator has 0 RP and cannot place at all. Season an account or
  acquire one before either app can pilot — this now gates **both** products on one dependency.
  **[CONFIRM]** which.
- **Dispute liability.** The user pays the merchant, but the operator is the on-chain counterparty.
  Decide who absorbs a loss, and whether it differs by app, before the pilot.
- **§2.4 correlation.** Confirm that publicly linking Zapp and betmoar on-chain is acceptable. If not,
  the pool must resolve per-app from day one and §2 stops being a trade-off.
- **`recipientAddr` verification for betmoar** (§5.2) — the one control I could not confirm is
  implementable.
- **KMS-vs-Secrets-Store** for signing (§3.3).
- **Throughput target.** Nobody has stated orders/hour. It decides whether `SingleOperatorPool`
  survives launch or needs sharding immediately.
