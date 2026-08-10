# Upstream Parity Gap — `ios-zapp` vs `zodl-ios`

**What this is.** The post-port status and historical audit for everything upstream (`zodl-inc/zodl-ios`) shipped between the fork point and release 3.8.1. It supports the fork's standing policy: *we own the UI and Zapp-specific features; for wallet plumbing and correctness we defer to upstream.*

**Current as of 2026-08-10, re-verified after PR #35 and published in PR #36.** The app-source audit compares `upstream/main = 512fa1c8` with **the Zapp source snapshot at `862672ab`**, the merge commit for PR #35. PR #36 adds only this document. Upstream `main` has not moved; Zapp `main` includes the recurring-server-error fix and the adapted stuck-`Sending…` hardening.

> **Verification pass, 2026-08-10.** Every section below was re-checked against the two refs. The **parity conclusion held** — of the 156 files upstream touched since BASE, 70 are now byte-identical to ours, 86 are non-identical (85 present-but-different plus the one deliberate absence at `Features/Home/PoolBalancesSheet.swift`), and we have deleted zero upstream files. The earlier pass corrected the §5.2 merge-conflict table (**57 files, not 30**), §5.2/§5.3/§5.4's both-sides and add/add counts (147 / 100 / 24, not 63 / 16 / 7), §4.5's trailing-newline row, §4.4's completed rows, §8's migration-overlap figure (51, not 36), and Appendix B's LOC meaning. PR #35 then closed the one functional regression that pass found (§4.2, #1948) and ported the non-duplicated final behavior from `upstream/fix/stuck-sending-tx`. PRs #33 and #34 remain the completed 3.8.1 parity program; PR #35 is post-parity correctness hardening.

**Delta since the prior refresh:** `agent/fix-main-e2e` advanced to `9128e8fe` (5 ahead / 0 behind). It now experiments with an exact Slipstream SDK checkout, locally built matching FFI and CI package-resolution retries; it is no longer merely the remote-pin confirmation seen at `8d87521f`. Do not port that moving CI/SDK shape into Zapp. `chp-re-enable` remains at `792b76c6` (245 ahead / 0 behind) and remains planning-only. Neither branch is merged into `upstream/main`.

| Merge | Port commit | What landed |
|---|---|---|
| PR #33 · `e040da26` | `0758cb47` | SDK 2.8.0-rc.1, stale-wallet fast-path heal, account-switch history, send refresh, Keystone #1920, Ironwood accounting/memos, MOB-1535 store, MOB-1475, housekeeping and regression suites |
| PR #34 · `b52c8459` | `ab13b850` | live pool-balance UI, Ironwood announcement/gate, #1948 live diagnostics, localization, and Voting compiled out behind undefined `VOTING_ENABLED` |
| PR #35 · `862672ab` | `c1c9bdf7` | recurring #1948 error re-arm plus MOB-1581 event filtering, foreground resubscription, pending-Zcash reconciliation and lifecycle tests |

> **How to read the rest of this file.** §1 and §8 are the current source of truth. Sections §3–§7 retain the original pre-port investigation because they contain safety rationale and merge traps that must survive future upstream work. In those sections, an explicit **Post-merge status** line overrides historical wording such as “we have none” or “still owed.” Old line numbers are evidence from the audit snapshot, not current navigation aids.

---

## 1. TL;DR

| | Current state |
|---|---|
| **Wallet parity through upstream 3.8.1** | ✅ Complete on `origin/main` |
| **SDK** | ✅ Remote exact `2.8.0-rc.1` at `64e1d590…`; no local SDK checkout |
| **MOB-1512 safety heal** | ✅ Probe plus `.seedNotRelevant` and thrown `initializerSeedMismatch` fast paths |
| **Ironwood readiness** | ✅ Pool accounting, empty-memo filter, live pool sheet and one-time announcement |
| **Correctness ports** | ✅ Account provenance, send refresh, Keystone import failure and #1948 diagnostics |
| **Voting under NU6.3** | ✅ Compiled out in 54 files; `VOTING_ENABLED` intentionally undefined |
| **Focused validation** | ✅ PR #34: 68 tests in 11 suites. PR #35: clean app/test compile and 14 tests in 2 suites. |
| **Byte-convergence with upstream** | ✅ 70 of upstream's 156 touched files are now byte-identical; 86 differ; 1 upstream file absent (deliberate); 0 upstream files deleted |
| **Live functional defect** | ✅ None found in the audited parity surface; PR #35 fixed the recurring #1948 error and ported stuck-`Sending…` hardening |
| **Changelog hygiene** | ⚠️ MOB-1593 and the Keystone account-switch fix still lack dedicated `CHANGELOG.md` entries; PR #35 added MOB-1581 |
| **This document** | ✅ Added to the repository in docs-only PR #36 |
| **Hosted CI** | ⚠️ PRs #34 and #35 could not start jobs because the GitHub account's payment/spending limit blocks Actions |
| **Post-merge review follow-up** | ⚠️ Verify/publish the Zapp Ironwood guide URL and await both RestoreWallet test effects |
| **Remaining upstream-main housekeeping** | `d7121bec`, Zapp-versioned What's New data, `35dd58bb`; judge `2c72d041` separately |
| **Stuck-Sending hardening** | ✅ Adapted from `upstream/fix/stuck-sending-tx` in PR #35, without duplicating the landed completion refresh |
| **Next correctness candidate** | Bound and test the fork-only offramp swap-status poller |
| **New upstream SDK signal** | `agent/fix-main-e2e` now tests exact Slipstream SDK + locally built FFI and CI retries; watch, do not port |
| **Coinholder Polling** | Still compiled out; `chp-re-enable` is planning-only and sits on the unmerged migration stack |
| **Full migration** | ⏸️ Not on upstream `main`; prepare for it, do not merge the moving branch yet |

Six current takeaways:

1. **The original parity program is complete.** Do not re-port the 3.8.1 wallet changes or replay their upstream commits; PRs #33/#34 adapted the final behavior to Zapp's live surfaces, and PR #35 closed the two post-parity correctness follow-ups.
2. **The next release task needs a Zapp version decision.** The project is `1.0.1`, while `secant/Resources/WhatsNew/whatsNew*.json` still tops out at the inherited `3.7.3`. Do not import upstream's `3.7.4/3.8.0/3.8.1` version numbers blindly; generate one Zapp entry for the chosen next version (`1.0.2` or `1.1.0`).
3. **The remaining live correctness risk is fork-specific hardening, not missing 3.8.1 parity.** The clearest next candidate is the offramp poller's unbounded `EXPIRED`/`PROCESSING` behavior.
4. **Pre-pay the migration merge with two isolated refactors:** closure-based `ZashiSheetModifier` content and stable `RootStore.Path`/`RootCoordinator` ordering.
5. **Keep the safety rationale below.** The code is now present, but future upstream merges can still silently lose PIN reset, chat/offramp teardown, unified-send Keystone coverage, live Zapp UI wiring or the `Localizable.xcstrings` byte-format constraints.
6. **Do not reactivate Voting from the new CHP branch yet.** Its only CHP-specific commit is a 461-line starting-point document, not app/SDK integration, and it explicitly carries unresolved SDK/crate selection and security questions.

---

## 2. Method

**Post-merge status (2026-08-10).** The original audit compared the refs below before the parity ports. The authoritative app-source refs for this pass are `upstream/main = 512fa1c8` and Zapp at `862672ab`; upstream has not advanced since the audit, while Zapp contains app-source PRs #33–#35 plus docs-only PR #36. Counts and line numbers in the historical sections intentionally describe the pre-port merge surface.

```
git fetch upstream && git fetch origin
BASE=$(git merge-base origin/main upstream/main)   # 0d3b93ad, 2026-07-08
git log --no-merges $BASE..upstream/main           # 105 commits
git diff --name-only $BASE upstream/main           # 156 files
```

Every "we don't have this" claim below was verified by grep **against `origin/main`, not the working tree** (`git grep -n '<pattern>' origin/main -- secant zodlTests`), and every "this is how upstream did it" claim by reading the actual diff — not the commit subject. Where a claim was checked two ways and disagreed, the disagreement is noted.

> The first draft was grepped against a checked-out `main` that later fell 11 commits behind `origin/main`, which made five completed items read as "0 hits — we have none of it". If a claim here looks wrong, check which ref you are on before believing it.

**Naming.** Upstream's app is ZODL; ours is Zapp. Expect large cosmetic string/asset diffs from the rebrand — those are not gaps. Where the rebrand makes a port *harder*, it's called out.

---

## 3. The resolved blocker: ZcashLightClientKit

**Post-merge status: complete in PR #33.** Zapp now uses the clean-clone-safe remote `exactVersion 2.8.0-rc.1` pin at revision `64e1d590a9f6113ff6ac56ffb3dab32bde5997dc`. `prepareWith` returns `Initializer.InitializationResult`; both `.seedNotRelevant` and thrown `initializerSeedMismatch` reach the stale-wallet heal, and the required package graph resolved from `Package.resolved`. The analysis below is retained as the safety rationale for that implementation.

**New upstream experiment:** `upstream/agent/fix-main-e2e` has moved past its temporary remote-pin confirmation. At `9128e8fe` it checks out an exact Slipstream SDK revision, builds the matching FFI locally, and retries package resolution after Xcode failures. Zapp's clean-clone-safe remote `2.8.0-rc.1` package shape remains correct for this repository; do not import the branch's moving CI/SDK setup.

### 3.1 What upstream did

Four commits over six days, all by Michal Fousek:

| Commit | Date | State |
|---|---|---|
| *(fork point)* | — | remote pin, `exactVersion 2.6.0-alpha.6` ← **we are still here** |
| `42f732a2` | 07-22 | remote, pinned to raw revision `74cdbbc0` |
| `1d23dffb` | 07-25 | **local** `XCLocalSwiftPackageReference "../zcash-swift-wallet-sdk"` |
| `f9748f00` | 07-28 09:05 | remote, `exactVersion 2.8.0-rc.1` ← **this is the shape we want** |
| `55e41f5a` | 07-28 21:21 | **local** again — final state on `main` |

Upstream's `Package.resolved` today has **no `zcash-swift-wallet-sdk` entry at all**. `main` cannot be built from a clean clone without a sibling checkout, and there is no CI step or doc anywhere in the repo that sets one up. The local reference is an artifact of their Ironwood dev workflow, not a requirement.

### 3.2 What actually blocks us — three symbols

| Symbol | In our `2.6.0-alpha.6` | In `2.8.0-rc.1` | Used by |
|---|---|---|---|
| `AccountBalance.ironwoodBalance: PoolBalance` | ❌ | ✅ | `AccountBalanceExtensions.swift`, `WalletBalancesStore` |
| `Initializer.InitializationResult.seedNotRelevant` | ❌ (2-case enum) | ✅ | MOB-1512 heal, 11 sites |
| `ZcashError.initializerSeedMismatch` (`ZINIT0006`) | ❌ | ✅ | `RootInitialization.swift:369` |

Everything else in upstream's SDK-facing diff compiles against our current pin unchanged. Empirically confirmed at the time: `9556aa6b` landed the whole MOB-1512 heal without touching any of the three.

> ⚠️ **The sentence that used to end this paragraph — "the pin on `origin/main` is still `exactVersion 2.6.0-alpha.6` (`project.pbxproj:1587-1590`, `Package.resolved` revision `4303068e`)" — is false and has been removed.** It was written in the present tense about `origin/main` and directly contradicted §3's own post-merge header and §1's SDK row. `origin/main` pins `kind = exactVersion; version = "2.8.0-rc.1"` at `project.pbxproj:1585-1592`, with `Package.resolved` revision `64e1d590a9f6113ff6ac56ffb3dab32bde5997dc`. All three blocking symbols are live in our tree. The `←` markers in §3.1's commit table are stale for the same reason: we are at the `f9748f00` shape, not the fork-point row.

**Verified directly** against a shallow clone of the tag (`HEAD = 64e1d590a9f6113ff6ac56ffb3dab32bde5997dc`):

```
Sources/ZcashLightClientKit/Model/WalletSummary.swift:25   public let ironwoodBalance: PoolBalance
Sources/ZcashLightClientKit/Initializer.swift:105-109      case success / seedRequired / seedNotRelevant
Sources/ZcashLightClientKit/Error/ZcashErrorCode.swift:25  case initializerSeedMismatch = "ZINIT0006"
Sources/ZcashLightClientKit/Constants/ZcashSDK.swift:14-16 enum NetworkType { case mainnet; case testnet }   ← still 2 cases
```

Two useful details from that check:

- **`AccountBalance.init` defaults `ironwoodBalance: PoolBalance = .zero`.** So the bump does *not* break our existing `AccountBalance(...)` test fixtures — they keep compiling and silently read Ironwood as zero. That's convenient for the bump but means **the fixtures will not tell you the aggregation is wrong**; the Ironwood assertions in `BalancesTests` / `WalletBalancesTests` / `SmartBannerTests` are what catch it. Take them with `95042d8f`.
- **`NetworkType` still has exactly two cases at this tag**, confirming the `.regtest` churn in §3.4 must be skipped.

`2.8.0-rc.2` (`1f4e12ba`) also exists and leaves `ironwoodBalance` unchanged, if a slightly newer pin is preferred. Do **not** reach for the SDK's own `release-baseline-2026-08-08` — `AccountBalance` is restructured there and it is not a drop-in.

### 3.3 Recommendation

**Bump the remote pin to `exactVersion = "2.8.0-rc.1"` (revision `64e1d590a9f6113ff6ac56ffb3dab32bde5997dc`). Do not adopt the local-package reference.**

That is literally reverting `55e41f5a` back to `f9748f00`'s state — a shape upstream themselves shipped 3.8.1 build 1 on. It keeps our repo buildable from a clean clone, which matters more for us than upstream because we *already* require one sibling checkout (`../zappMessaging/ios`, pinned in `.zapp-deps`); adding a second would mean extending `Scripts/bootstrap-zappmessaging.sh` and `.github/actions/bootstrap-zappmessaging` before CI could resolve packages at all.

**Two things to sanity-check after the bump:**

- The non-SDK `Package.resolved` delta rides along: swift-log 1.13.1→1.14.0, swift-nio 2.101.0→2.101.3, swift-nio-http2 1.44.0→1.45.0, swift-nio-ssl 2.37.1→2.37.2, swift-protobuf 1.38.0→1.38.1, swift-system 1.6.5→1.7.5. Confirm ZappMessaging's transitive gRPC/NIO graph still resolves.
- The `prepareWith` signature change (§4.1.1) is mandatory once you bump: the bumped SDK surfaces a seed/DB mismatch **two** ways where the pinned one surfaces it not at all — `Initializer.initialize` returns `.seedNotRelevant` (`Initializer.swift:451-452`) *and* `validateSeedAgainstExistingAccounts` throws `ZcashError.initializerSeedMismatch` (`:525`). If we bump without handling both, a user restoring a different seed over a stale DB gets a **hard, unrecoverable initialization failure**. That is a regression we would be introducing ourselves.

### 3.4 Two traps in the middle of the window

Upstream churned against an unpinned working copy and reverted twice. Do **not** replay these commits:

- **`ab109d8e`'s `NetworkType.regtest` arm** (`ParserContext.from`, `ironwoodActivationHeight`) — fully removed again by `2acef3c0`. No published SDK tag has `.regtest`. Our `URIParserInterface.swift` is *already byte-identical to upstream/main*; it's the only net-zero file in the whole range.
- **`4d7fdeee`'s `sentNoteCount`/`receivedNoteCount` fallback** — fully reverted by `8a822be7` (MOB-1580) as device- *and* time-dependent: the same self-transfer reads 1/1 before its block is scanned and 0/0 after, so the displayed amount changed on confirmation and disagreed across devices. Our current `netValue` already matches upstream's end state.

Take the **final upstream file state**, not the commit sequence, everywhere in this document.

---

## 4. The gap inventory

Ordered by what it costs us to keep not having it.

### 4.1 P0 — Funds-safety and data-integrity

#### MOB-1512 — Stale wallet database from a foreign seed — **LANDED probe-only** (`9556aa6b`)

**Post-merge status: core safety path complete across PRs #33 and #34.** PR #33 landed the SDK fast paths, reprepare success check, both mismatch signals, wipe/heal reachability tests, and per-test shared-storage isolation; PR #34 added the voting-override assertion. Some hardening items in the residual list remain: delete-path coverage, explicit Flexa/preferences/offramp ordering assertions, a view-only-database explanation, and manual alert-presentation verification. They are no longer blockers to upstream 3.8.1 parity, but are tracked in §8.

**Upstream commits:** `68a9699b`, `a9933325`, `a5155e9a`, `4394adbc`, `d254e77e`, `72b962fa`, then `998ca6e8` (SDK maintenance).
**We have:** all of it except the SDK fast path. `Root.reconcileWalletDatabaseWithSeed` `RootStore.swift:686`, `WalletDatabaseHealError` `:672`, `clearDeviceScopedWalletState` `:721`, `AlertState.staleWalletDatabaseHealed()` `:919`, heal block `RootInitialization.swift:374-413`. Tests: `WalletDatabaseSeedReconcileTests.swift` (197 lines, pins the call order), `RootInitializeSDKHealTests.swift` (324).

The scenario it closes, from upstream's own commit message: a device backup restore drops wallet A's `Documents/data.db` onto a fresh device, while the `ThisDeviceOnly` keychain seed does *not* migrate. "Restore existing wallet" then stores seed B on top of it. The SDK silently accepts the mismatched DB — account creation is skipped because accounts already exist — so **the app displayed wallet A's addresses and balance while signing with seed B**, and shielding failed with `ZRUST0002` (`ZcashErrorCode.rustCreateToAddress`). Anything received at those addresses was unrecoverable, off an ordinary user action.

**The rationale below is recorded here because the port did not carry it into the code.** All three comment blocks that used to explain these clears — upstream's own, inherited by us at the merge base and still at `upstream/main:RootStore.swift:665-668`, `:671-674`, `:681-685` — were dropped in the extraction: `git grep -n 'third-party host the previous owner' origin/main` → 0 hits. Because they sit at the merge base *and* upstream keeps them, a three-way merge will honour our deletion silently. This document is now the only place the *why* exists. Do not delete it as "already done".

1. **The view-only guard.** `hasSeedDerivedAccount` (`RootStore.swift:686-714`) refuses to wipe a database whose accounts are all imported/view-only — those can never be recovered from any seed, so wiping destroys the user's only copy. It is what stops the heal **destroying a Keystone-only wallet's database**. Nothing in the code says so.

2. **The voting override is the sharp clear.** `clearDeviceScopedWalletState` drops `votingConfigOverrideURL` (`RootStore.swift:737`), `votingCustomChains` (`:738`), `voting.sqlite3`, and the `voting.voteRecord.*` / `voting.draftVotes.*` sweep. Left behind, the override **silently keeps routing the *new* wallet's voting traffic through a third-party host the previous owner chose.** This is the standing rule for every device-scoped store we add later.

3. ✅ **The silent-security-drop hazard did not fire.** The extraction kept our three fork-only lines: `userDefaults.remove(.appAuthenticationMethod)` / `.failedPINAttempts` / `.pinLockoutEndTimestamp` at `RootStore.swift:734-736`, reachable from both callers (`RootInitialization.swift:385` heal, `:633` delete). Verify with `git grep -n failedPINAttempts origin/main -- secant/Sources/Features/Root`.

   ⚠️ **But succeeding inverted the trap.** Upstream's `ab109d8e` opens `#if VOTING_ENABLED` immediately after `udLeavesScreenOpen` (`upstream/main:RootStore.swift:662`) and closes it after the voting sweep (`:691`) — and our three PIN lines now sit exactly inside that span. It will **not** land mechanically: `git apply --check` of that commit's `RootStore.swift` hunks against `origin/main` fails (the hunk context is upstream's voting comments, which this port deleted), GNU `patch` places the `#if` with fuzz but *fails* the `#endif` hunk (leaving an unbalanced `#if` that will not compile), and `git merge-tree` puts the whole block into a conflict. **So the hazard is a bad manual resolution, not a silent apply** — and the shapes are now close enough that taking upstream's `#if`/`#endif` verbatim is the obvious resolution. `VOTING_ENABLED` is defined in no build configuration, so that resolution **compiles the PIN-lockout reset out of every build**, with nothing failing and no test catching it. If the §4.5 voting decision ever goes "follow upstream", lift the three PIN lines above the `#if` first.

4. **One ordering invariant moved and its comment did not follow.** The port put the `chatContacts.resetAccount(...)` loop *inside* the helper (`RootStore.swift:757`) — the opposite of what the first draft prescribed, and the better call, since it gives the heal chat-contact reset for free. The constraint survives only because the helper is still invoked before `walletStorage.clearEncryptionKeys` (`RootInitialization.swift:633` before `:653`); `resetAccount` resolves its file path through those keys and silently `try?`s on failure, so a reordering leaves wallet A's encrypted chat graph on disk with no compile error and no failing test. **The comment stating this is orphaned at `RootInitialization.swift:651`, where it now sits above `clearEncryptionKeys` and reads as if that must run before itself.** Move it to `:633`.

**Residuals — what MOB-1512 still owes:**

- **The delete path has no test at all.** `git grep -n 'resetZashiSDKSucceeded\|clearDeviceScopedWalletState' origin/main -- zodlTests` → 0 hits. The PIN assertions (`RootInitializeSDKHealTests.swift:163-165`) cover the heal path only.
- **Two teardown-order assertions are still absent.** Upstream's `clearsDeviceScopedStateBeforeWipingOnHeal` asserts `flexaSignOut < wipe` and `userPrefsRemoveAll < wipe`; our stubs record both but no assertion reads them. PR #34 restored the third original omission, `removedKeys.contains(.votingConfigOverrideURL)`, and deliberately keeps that reset unconditional even though Voting is now compiled out. Add the two remaining ordering assertions when hardening the heal suite.
- **The offramp leg is unasserted.** `$0.offramp.invalidateSession` is stubbed (`RootInitializeSDKHealTests.swift:74`) and never checked, `clearZappWalletScopedState` (`RootInitialization.swift:478-482`) has no test, and with `exhaustivity = .off` you can delete `await offramp.invalidateSession()` at `:395` and the whole handler and leave all 8 tests green.
- **The view-only refusal is a dead end with no copy.** `WalletDatabaseHealError.viewOnlyDatabase` and `.wipeUnavailable` are not caught specifically — only `.reprepareFailed` is (`RootInitialization.swift:461-465`) — so both fall to the generic `catch` at `:466` and surface as an opaque `initializationFailed`. A Keystone-only user with a foreign DB is correctly *not* wiped and then stranded with no explanation. No string shipped for it.
- **Neither Root suite pins `defaultInMemoryStorage`**, in breach of §7 convention 2, while both mutate `@Shared(.inMemory(.walletStatus))`. `@Suite(.serialized)` serialises within a suite, not between the two.
- **The heal costs one extra SDK round-trip on every cold launch** — `isSeedRelevantToAnyDerivedAccount` always runs (`RootInitialization.swift:377`), and `reconcileWalletDatabaseWithSeed` short-circuits on a relevant seed (`RootStore.swift:695-702`) before the second probe. Only on a mismatch do the further calls fire: `walletAccounts()` inside `hasSeedDerivedAccount` (`:379`) and again inside `clearDeviceScopedState` (`:383`). `knownStale: true` skips all of them once the fast path lands.
- **`prepareWith` now has two app call sites** (`RootInitialization.swift:363` and the heal's reprepare closure at `:405`) and **two test call sites** (`RootInitializeSDKHealTests.swift:77`, `RootInitializeSDKSingleFlightTests.swift:111`), plus the stubs in `SDKSynchronizerTest.swift`. The bump's compile sweep is bigger than the first draft promised — see §8 step 6.

Upstream-merge notes for this area: `RootDestination.swift` is **no longer clean** (we edit `:59-60`); our `newWalletSuccessfullyCreated` double-`l` spelling survived at `RootInitialization.swift:815` and must keep winning over upstream's typo; our helper signature deliberately diverges from upstream's (we take `chatContacts` + `walletAccounts`, and our `clearDeviceScopedState` closure is `async throws` where upstream's is `async`) — keep ours in all four hunks.

##### 4.1.1 Historical probe-only stage and the SDK contract now connected

**Resolved in PR #34.** This subsection records why changing only the call site would have been unsafe. Interface, Live, Test, both app call sites, and both test call sites now preserve and act on the SDK initialization result.

Upstream's heal has two entry paths: a **probe** (`isSeedRelevantToAnyDerivedAccount` returns false → heal) and a **fast path** (`prepare` returns `.seedNotRelevant`, or throws `initializerSeedMismatch` on newer SDKs → `knownStale: true`, skip both probes). Only the fast path needs the new SDK, and only the probe shipped.

**Why the probe is the only signal available on `2.6.0-alpha.6`** — and this is live rationale, not history. On the pinned SDK `Initializer.InitializationResult` has just `.success` and `.seedRequired`; `DbInitResult.seedNotRelevant` *is* public, but `Initializer.initialize` tests only `if case .seedRequired`, so a stale-DB open returns `.success`. The mismatch is invisible to the return value by construction. The three collaborators the probe needs all exist today: `isSeedRelevantToAnyDerivedAccount` (`SDKSynchronizerInterface.swift:77` / `Live.swift:164`), `walletAccounts()` (`:83`), `zip32AccountIndex` (`Models/WalletAccount.swift:48`).

**What shipped:** `knownStale: false` is hardcoded at `RootInitialization.swift:375`, with a `TODO` at `:371-373`. **No switch was introduced** — `SDKSynchronizerInterface.swift:41` still declares `prepareWith` returning `Void`, and `SDKSynchronizerLive.swift:62-69` still collapses every non-`.success` into `throw ZcashError.synchronizerNotPrepared`. The heal runs only *after* a successful `prepareWith`.

⚠️ **That last fact contradicts a comment in our own source.** `RootStore.swift:684-685` claims "keeping the final algorithm shape here makes the later SDK-contract update isolated to the call site." It is not. Wiring `knownStale: true` at the call site alone leaves `.seedNotRelevant` swallowed at `Live.swift:69`, rethrown as `synchronizerNotPrepared`, caught generically at `RootInitialization.swift:466` → `.initializationFailed`. That is verbatim the `998ca6e8` dead-code regression, and our fork is *more* exposed to it than upstream because of the Void collapse. **At the bump, change `Interface.swift:41` + `Live.swift:62-69` + the `SDKSynchronizerTest.swift` stubs + both app call sites (`:363`, `:405`) — and fix that comment in the same change.**

One compile-safety trap for whoever does it: `seedNotRelevant` is a live identifier today on the wrong type (`DbInitResult`), so a wrong-type wiring will not necessarily fail to build.

> **Standing rule to record:** the heal's reachability is coupled to the SDK's error/status contract. After **any** future SDK bump, re-verify that a seed/DB mismatch still reaches `reconcileWalletDatabaseWithSeed` and does not dead-end in `.initializationFailed`. `998ca6e8` exists precisely because an SDK upgrade silently turned the whole heal into dead code.

##### 4.1.2 The deferred alert — a standing invariant, not a port

All three holes are closed (`a5155e9a`, `4394adbc`, `d254e77e` → `RootStore.swift:73/95/794-803`, `RootDestination.swift:58-61`, `RootInitialization.swift:484-492`, `:495-497`, `:815-820`). **Kept here because the port dropped all four of upstream's in-code explanations** — the comments at `RootDestination.swift`, the direct-assignment arm, the `.staleWalletDatabaseHealed` handler and the 17-line helper doc are 3 lines total in our tree. This is now the only record of the invariant, and the next person to add a destination-assignment site has no other signal.

**The invariant:** whenever `isStaleWalletHealedAlertPending` is set and the destination is `.home`, a delivery must be scheduled — *regardless of ordering*. There are three ways to reach home and all three must hook it:

1. via `updateDestination` (`RootDestination.swift:59-60`);
2. via the two arms that assign the destination directly and bypass `updateDestination` — `.phraseDisplay(.finishedTapped)` / `.onboarding(.newWalletSuccessfullyCreated)` at `RootInitialization.swift:815` (note **our** double-`l` spelling; upstream's typo is un-greppable here);
3. via a heal that arrives *after* home already settled (`RootInitialization.swift:484-492`).

Two rules inside it are counterintuitive and uncommented in our source, so they are easy to "tidy up" into bugs:

- The cancel ID must stay **dedicated** (`staleWalletHealedAlertCancelId`, `RootStore.swift:73`) — never a shared or general-purpose one. `Root.State` carries 15 cancel IDs, two of them fork-only, so the reuse temptation is higher here than upstream.
- On a failed destination check the flag is **deliberately left set** (`RootInitialization.swift:495-497` is a bare `guard … else { return .none }` with no note) so a later return to home still delivers. Only the test name `leavingHomeBeforeDeliveryKeepsAlertPending` hints at it.

⚠️ **Cross-reference:** the Ironwood announcement port (§4.3) adds a **third** direct destination assignment — upstream guards it with a 10-line comment (`upstream/main:RootInitialization.swift:893-902`) reasoning explicitly about this hook. Wire it into the invariant when that lands.

**Two residuals, both open:**

- **Presentation is still unverified.** *(Corrected: `RootView.swift` is **not** byte-identical to the pre-port tree — `ab13b850` added the 11-line `case .ironwoodAnnouncement:` branch at `:422-431`, which pushed `.alert(` from `:432` to `:443`. `case .home:` `:112`, `ZappTabsView` `:116` and the `store.path` overlay `:404` are all still accurate. The "untouched" framing mattered because it is the sentence a reader uses to decide the file needs no re-inspection.)* The substantive residual stands: `.alert(` at `:443` is attached to the container **wrapping** the destination switch, so it presents regardless of branch, and every heal test asserts reducer state only — none can prove SwiftUI presents it. Run it once by hand.
- **The `store.path` axis is unchecked.** Delivery re-checks only `destination == .home` (`RootInitialization.swift:495`); it never checks `state.path == nil`. `Root.State.path` is a second navigation axis we inherited from upstream and then extended — **74** `state.path = ` sites in our `RootCoordinator.swift` (46 non-nil) against upstream's 45 — so a foreground-triggered heal while the user sits in Settings presents the notice over Settings. Upstream's delivery guard checks the destination and nothing else, exactly like ours, so this is the same class of bug `4394adbc` closed on the destination axis, still open on **both** sides — with more surface on ours.

---

#### #1943 — Single-flight wallet initialization — **LANDED** (`ce9b8c4c`)

**Post-merge status: complete on `origin/main`.** PR #33 retained the single-flight behavior while updating the SDK interface and kept isolated regression coverage; latch release remains a standing invariant on every terminal path.

Closed the ghost-account race (upstream's branch: `fix/ghost-account-issue`). Latch at `RootStore.swift:92`, guard at `RootInitialization.swift:348`, `= true` at `:360` after the synchronous preamble, releases at `:475` / `:503` / `:848`. `zappMessaging.resume()` stays outside the latch (`:66`) — messaging lifecycle is deliberately independent of wallet prepare. Regression test: `RootInitializeSDKSingleFlightTests.swift`.

The ordering trap the first draft flagged was honoured: the `catch reprepareFailed` route sends `.initializeSDKFinished` (`:464`) **before** `.checkWalletInitialization` (`:465`), added by the MOB-1512 commit with the reason commented at `:462-463`.

> ⚠️ **Standing rule, for every future terminal path.** Any new `catch` arm or early exit inside the `.run` at `RootInitialization.swift:361` must release the latch, and any re-entry sent from inside it must send `.initializeSDKFinished` **first** or the re-entry's own `.initializeSDK` is swallowed by the guard. A stranded latch is unrecoverable: that effect carries no `.cancellable(id:)`, so `.cancelAllRunningEffects` cannot reach it and wallet initialization is bricked until relaunch.
>
> Acceptance check: `git grep -n isInitializingSDK origin/main -- secant` — expect exactly one `guard`, one `= true`, and one `= false` per terminal path.

**Residuals:** the recovery re-entry is asserted nowhere end-to-end — `reprepareFailureReleasesLatchBeforeRecoveryReentry` pins the *send order* of the two actions but, with `.noOp` database/storage stubs, `.checkWalletInitialization` resolves to `.uninitialized` rather than the `.filesMissing` arm that actually re-prepares, so no test proves a second `prepareWith` happens. Inherited from upstream and unrecorded there: the guard drops re-entries regardless of `WalletInitMode`, and if `prepareWith` never returns (hung gRPC/Tor) the latch stays set for the process lifetime.

---

#### MOB-1510 — Keystone minimum-firmware gate at signing — **LANDED** (`4a773dfc`)

**Post-merge status: complete across every shipping signing surface.** PR #33 kept the four upstream corridors and fixed/tested the fork-only unified-send address residual in §6.2; PR #34 compiled the unsupported Voting flow out of normal builds.

**Upstream commits:** `7a60320b`, `86c6ad14`, `1b35c254`, `8ce0b527`, `c0de0468`, `1e2506aa`, `31931c16`, `0df8c7bb`, `6e6fe320` — all nine, taken as the end state. (`31931c16` is the test half of the 3.0.3→3.0.1 revert and is easy to miss.)

Firmware below 3.0.1 returns a PCZT this app cannot extract; the send died inside `createTransactionFromPCZT`, at `extractAndStoreTxFromPCZT` with `MissingSpendAuthSig`, **before anything reached the network** — surfacing to the user as a generic failure. The gate byte-scans the signed PCZT for the proprietary key `keystone:fw_version` (KeystoneSDK 0.8.6 exposes no firmware API) and refuses to broadcast below the minimum, including when the stamp is absent entirely. The +10 internal-major offset is contained by two types bridged only by `fromStamp(_:)` (`KeystoneFirmwareVersion.swift`), and the mechanism is now documented in that file — no need to repeat it here. All four `foundPCZT` corridors are gated: `SendCoordFlowCoordinator.swift:197`, `SwapAndPayCoordFlowCoordinator.swift:146`, `ScanCoordFlowCoordinator.swift:148`, `SignWithKeystoneCoordFlowCoordinator.swift:86`.

**Two rules from `6e6fe320` that outlive the port and are only half-encoded in comments:**

- **`UserMetadataProviderInterface` has no unmark API** (`markTransactionAsSwapFor` at `:44`, nothing to reverse it). That is what makes "write swap metadata only *after* the gate accepts" permanent and un-revertable, at `SwapAndPayCoordFlowCoordinator.swift:159` and the fork-only `SendCoordFlowCoordinator.swift:211-215`. A blocked swap that wrote metadata leaves a phantom record forever, and later ordinary payments to that address get misclassified in history.
- **`SendConfirmationStore.swift:478` sets `isKeystoneCodeFound = true` before the gate runs**, so the rescan-after-update path depends entirely on the coordinator-level Close handlers clearing it (`Send:224`, `SwapAndPay:190`, `Scan:165`, `SignWithKeystone:96`). `KeystoneFirmwareUpdateView` is `.navigationBarBackButtonHidden()`, so Close is the only exit. **Any fifth signing surface added later must reset that flag or the user is stuck after updating firmware.** Nothing enforces this but the comments.

> ⚠️ **Known residual — and it is now ours alone, not "upstream has it too".** The Voting flow's Keystone signing path (`VotingCoordFlowCoordinator.swift:600`, `.foundVotingDelegationPCZT` → `reduceKeystoneScanFound`) bypasses `SendConfirmation.foundPCZT` and reads no firmware stamp, so it is **the only ungated Keystone signing surface left in the app** — feeding `votingAPI.submitDelegation` and `delegateShares`, two of the guard-protected broadcasts. Upstream's copy of that file opens with `#if VOTING_ENABLED`, a flag defined in no upstream build configuration, so **upstream ships this hole in zero builds and we ship it in every build. No upstream fix is coming for it.** See §4.5.

---

#### PRO-325 — swap statuses — **LANDED for `FAILED`** (`e2dab641`); the offramp poll loop is still unbounded

Upstream's `92320ace` mapping landed byte-identical, extracted as `Near1Click.swapStatus(from:isSwapToZec:)` (`Near1Click.swift:221-243`) with `FAILED` → `.failed` and `PROCESSING` → `.processing` in **both** directions, plus five tests in `Near1ClickTests.swift`. Badges no longer stick on "Swapping"/"Paying" for a provider-side failure.

**The fork-specific coupling this closed — recorded because nothing in the code links the two files.** `secant/Sources/Dependencies/Offramp/OfframpNearBridge.swift:356` calls `swapAndPay.status(depositAddress, false)` — the non-ZEC arm — inside an unbounded `while !Task.isCancelled` loop (`:354`) with a 5-second sleep (`:376`) and no deadline. Its only `terminal: true` branch is `case .failed, .refunded, .expired, .incompleteDeposit` (`:361`); `case .success` (`:359`) is the other exit. So `Near1Click.swift:238` (the `else` arm's `case SwapConstants.failed`) is what lets a provider-side `FAILED` reach that branch at all — pre-port it was reachable only via `REFUNDED` / `INCOMPLETE_DEPOSIT`. `git grep -n 'Near1Click\|swapStatus' origin/main -- secant/Sources/Dependencies/Offramp` finds one unrelated hit; `Near1Click.swift` contains zero occurrences of "offramp". **Do not "simplify" that arm on a future upstream sync.**

⚠️ **The residual is narrower than the first draft's, and still live.** `SwapConstants.expired = "EXPIRED"` (`Swaps.swift:17`) is in **neither** arm of the ported mapper, so a provider `EXPIRED` — and any status outside the six mapped strings — falls to `default: .pending` and the loop takes `case .pending, .pendingDeposit, .processing: break` (`:367`) and spins forever. A stuck `PROCESSING` does the same. The mapper is upstream's, so this is shared, not fork drift; the *consequence* is ours alone, since upstream has no offramp. The only non-status exit is `deterministicFailures >= 3` (`:371-374`), reset on every successful fetch, so it trips only on three consecutive **throws** and cannot rescue a provider that keeps answering.

> **Still owed: verify `OfframpNearBridge.poll` end-to-end.** `poll` has zero test coverage (`OfframpTests.swift` covers the store and `OfframpBridgeQuoteValidator`, never `poll`), we are its only caller, and upstream never exercises it — `git ls-tree -r upstream/main secant/Sources/Dependencies/Offramp` is empty, so every future upstream change to that mapping arrives untested against our loop. The port also made a previously-dead branch live on the funds-sending path: `execute` calls `poll` (`:298`) immediately after the deposit broadcast (`:283`) and hands `AppleBridgeExecution` to the out-of-repo ZappOfframp SDK. This cannot be discharged by a unit test — run the corridor.

---

#### MOB-1593 — Empty memo artifacts *(dormant until NU6.3, then universal)*

**Post-merge status: complete in PR #33.** Transaction details now remove exactly empty decoded memo strings, retain whitespace-only memos, and have focused all-zero ZIP-302 coverage.

**Commit:** `7723c8c2` — one line of app code plus a new 38-line `zodlTests/TransactionDetailsTests/TransactionDetailsMemosTests.swift` pinning the ZIP-302 premise; take both. **We have:** the unfiltered form at `TransactionDetailsStore.swift:423`, and no such test.

Post-NU6.3, transactions spending Orchard notes carry fabricated zero-value outputs whose on-chain memo field is all-zero bytes. Per ZIP-302 those decode as a *text* memo whose string is empty — so transaction detail renders an extra empty message bubble, and the same array feeds the **"Send again" prefill**, which picks the empty artifact instead of the real message.

Upstream's fix is `.filter { !$0.isEmpty }` (whitespace-only memos are deliberately *not* filtered — only the exactly-empty artifact). Same trigger class as the Ironwood balance under-count: silent today, fires on **every Orchard-spending transaction** the moment the upgrade activates.

**Both symptoms are worse in our fork:**

- The empty bubble is *more* visible here. Our rewritten `messageViews()` (`TransactionDetailsView.swift:721-770`) wraps every memo in `.padding(12)` + `ZappColors.surface` + a `Rectangle().strokeBorder(ZappColors.border…)`, so the artifact renders as a **visibly bordered, tappable empty box** rather than blank text.
- The "Send again" prefill silently blanks. `RootCoordinator.swift:688` reads `state.transactionMemos[transactionState.id]?.first ?? ""`. The fabricated empty output sorts ahead of the real memo, so `.first` is `""` and the resend form opens with **the user's original message dropped**.
- Secondary: `onAppear` sets `areMessagesResolved = !state.memos.isEmpty`, so once the artifact is cached a revisit short-circuits `resolveMemos` and can never self-correct.

**Chat blast radius checked, not assumed.** The SDK memo read (`getMemos`) has exactly one consumer, `TransactionDetailsStore.swift:412`. `grep -rn "memo" secant/Sources/Features/Chats` matches only `ChatMessagePayloads.swift` / `ChatSplitBillStore.swift` / `ChatSplitBillSheet.swift` / `ChatPaymentRequestBubble.swift` (the other hits are the word "memory" in comments), where `memo` is a **JSON field of a ChatPaymentRequest carried over ZappMessaging** — not a Zcash memo. The single chat↔memo bridge is write-only in the other direction (`RootCoordinator.swift:355-357` prefills the send form from `request.memo`). The filter cannot affect messaging.

Also verified no test breakage: `TransactionDetailsLogicTests.swift:105` seeds `transactionMemos` directly, bypassing the `.memosLoaded` arm.

Must-take; bundle it with the Ironwood work, not with "small fixes".

---

### 4.2 P1 — Correctness fixes we should take

#### Keystone / account-switch transaction history

**Post-merge status: complete in PR #33.** Transaction payloads carry `AccountUUID`, stale results are dropped whole, cancellation is ordered ahead of refetch without `cancelInFlight`, identical accepted payloads clear invalidation, and every fork-specific chat/offramp/Flexa teardown survived. The adapted ten-test suite covers provenance, starvation, metadata, and switch signaling.

**Commits:** `103b9689`, `8d3ad9dd`, `0c3ce592`, `9e6bf000`, `3b6a7130`. **We are at the exact pre-fix baseline** — `RootTransactions.swift:61` still sends the single-payload `.fetchedTransactions(transactions)`.

The bug: the fetch resolved `selectedWalletAccount?.id` at dispatch time but returned an **anonymous** payload the handler wrote unconditionally. Both `eventStream()` and `stateStream()` re-dispatch the fetch, throttled to 0.2s. Switch from the Zapp account to a Keystone account while a `getAllTransactions` for the old account is still in flight, and last-writer-wins: you see account A's history while account B is selected. Privacy-adjacent, not just cosmetic.

Four things in the fix that matter and are easy to get wrong:

- The payload carries the `AccountUUID` and a stale one is **dropped whole**, never merged — the swap decoration that follows is account-scoped.
- The cancel id is deliberately **without `cancelInFlight`**. `8d3ad9dd` proves `cancelInFlight` starves the list for an *entire sync* on any wallet where `getAllTransactions` exceeds the 0.2s event throttle. **Never take `103b9689` alone** — it is strictly worse than what we have today.
- The cancel is `.concatenate`d ahead of the refetch, not `.merge`d — otherwise the switch cancels its own refetch.
- `0c3ce592` unsticks the loading placeholder when a refetch returns an *identical* list (switching between two empty accounts — i.e. the literal first-run Keystone experience). **This is worse for us:** `ZappPayView.swift:155` gates on `transactionListState.isInvalidated`, and the Pay tab is persistent, so a stuck flag is visible for as long as the tab is.

**Port cost:** medium. `RootTransactions.swift` is untouched by us and auto-merges clean. `RootCoordinator.swift` needs five hand-resolved hunks.

> ⚠️ **Silent-merge hazard, verified with `git merge-tree`.** Git grafts our `.send(.loadChatContacts)` onto upstream's *new* `.keystoneDeviceReady(.accountImportSucceeded)` arm and **silently drops it** from our existing `.accountHWWalletSelection(.accountImportSucceeded)` arm. Correct resolution: `.send(.loadChatContacts)` on **all five** post-merge account-switch arms — `.home(.walletAccountTapped)`, upstream's new `.keystoneDeviceReady(.accountImportSucceeded)`, `.accountHWWalletSelection(.accountImportSucceeded)`, `.keystoneConnected(.closeTapped)` and `.settings(…accountHWWalletSelection(.accountImportSucceeded))` — our chat contact list is account-scoped exactly like `addressBookContacts`.

Also don't let `accountSwitchedEffect` extraction silently drop our fork-only `.send(.offramp(.cancelAll))` and the MOB-1352 `.cancel(id: state.CancelFlexaId)` teardown from `.home(.walletAccountTapped)`.

---

#### MOB-1581 — Send-completion refresh and stuck-`Sending…` hardening

**Post-merge status: complete across PRs #33 and #35.** PR #33 made all final Send, Scan, Sign-with-Keystone, Swap, and transaction-detail completion shapes refetch immediately; `sendFailed(_, false)` remains deliberately silent. PR #35 then adapted the final non-duplicated behavior from `upstream/fix/stuck-sending-tx`: transaction events are filtered before throttling, foregrounding resubscribes the transaction stream, and a 30-second reconciliation poll refreshes locally pending Zcash transactions until they leave the pending state. Backgrounding cancels both effects, fetch failures are logged, and the poller excludes swaps. Five focused lifecycle and reconciliation tests cover the added behavior.

**Commit:** `97c0bdd6`. **We have:** the four `transactionDetails(.closeDetailTapped)` arms still `return .none`; no `sendDone`/`sendPartial`/`sendFailed(_, true)` arms exist at all.

A sent transaction is in the local DB the instant creation succeeds, but the list only refetched on sync events — and an idle wallet emits none until the next block, **~75 seconds**. So the "Sending" row could be invisible for over a minute after the user sent money.

**This lands harder in our fork.** `RootCoordinator.swift:376` gates the chat transaction bubble on `state.transactions.index(id: txId) != nil`. After a chat-initiated send we post an `application/zec-transaction` receipt — so **the sender taps their own freshly posted receipt bubble and gets `transactionUnavailable` for up to ~75s**. That's a broken interaction upstream cannot see.

Note the `Bool` in `sendFailed(ZcashError?, Bool)` means "a transaction was stored" — the arms match `sendFailed(_, true)` deliberately; `false` stored nothing and must stay silent.

---

#### #1920 — Keystone connection/import failure handling

**Post-merge status: complete in PR #33.** The failure sheet, safe localized error payload, support routing, re-entry guard, spinner reset, late-failure suppression, and both RestoreInfo/Keystone progress states are landed. The final upstream test files were ported/adapted.

**Commits:** `fecdd4a2`, `cb20883e`, `7fccabe3`, `b5ba4963`, `79bccccd`, `767553a1`, `33d4b66f`, `2102e47a`.
**We have:** the bare `// TODO: error handling`, a payload-less `case accountImportFailed`, and an **uncaught `try await sdkSynchronizer.walletAccounts()` whose throw TCA silently swallows**. A failed Keystone connection is a dead end whose only exit is force-quitting.

What upstream built: a coordinator-level "Connection Failed" sheet (Contact Support + Cancel; Try Again was shipped then deliberately *removed* because its retry handler was itself a duplicate-import trigger), an `isImportingAccount` re-entry guard, `ProgressView` feedback on both connect buttons, and a rule that drops any failure arriving after `.keystoneConnected` is on the stack.

**Security detail worth preserving verbatim:** the payload is `error.localizedDescription` **only** — for `ZcashError` that is the static `"<code>: <message>"` form. The raw Rust error string, which for an import failure can embed the UFVK, is never interpolated. Anyone re-implementing this with `String(describing: error)` silently reintroduces a **key-disclosure channel into an email the user is being told to send**.

**Port cost:** low. Every Swift file this touches is byte-identical to the fork point in our tree. Only the xcstrings keys and CHANGELOG need hand work.

Two ordering traps: `33d4b66f` alone ships a stuck-spinner bug that `2102e47a` fixes by moving the `isProcessing` clear loop *above* the suppression check — take them together. And any test touching `SupportDataGenerator` must override `walletStorage` (`6a6e16a1`) or it fails at **runtime**, not compile time.

---

#### #1948 — Incompatible-server sync diagnostics

**Post-merge status: complete across PRs #34 and #35, including the live Zapp surface.** All five errors are classified, consensus IDs use fixed-width unsigned hex, replacement errors refresh correctly, support data carries the diagnostics, and `ZappPayView`/`ZappSyncErrorSheet` gate Switch Server and render the current message. The historical warning about dead upstream views is resolved by the fork rewrite in §6.3.

> ✅ **RECURRING-ERROR REGRESSION RESOLVED IN PR #35.** The fork keeps its recovery clear, but now resets both `lastKnownErrorMessage` and `lastKnownErrorIsIncompatibleServer` on a non-error snapshot. A later identical incompatible-server error therefore differs from the empty cached message and reclassifies correctly. `recurringIncompatibleServerErrorRearmsTheFlag` pins error → recovery → same error; the nine-test SmartBanner suite was part of PR #35's clean 14-test focused run.

**Commits:** `c62e33b1`, `4ab62a83`, `28a2e1ee`, `06ec70c5`. **Historical pre-port state:** none — `ZcashError+DetailedMessage.swift` was still the 19-line fork-point version.

Three separable pieces:

- **(a) Diagnostics** — classify five `ZCBPEO*` cases as "incompatible server", replace the raw enum dump with written copy naming the connected lightwalletd host, and render both consensus branch IDs in hex (`0x37a5165b`) instead of decimal (`933566043`). `ConsensusBranchID` is `Int32`, so plain interpolation renders decimal *and* high-bit IDs render negative; `String(format: "0x%08x", UInt32(bitPattern:))` fixes both. The same string goes into the support report.
- **(b) "Switch server" shortcut** gated on the new `lastKnownErrorIsIncompatibleServer` flag.
- **(c) `isDifferentError`** — **the standalone gem.** `SyncStatus`'s `Equatable` has `case (.error, .error): return true`, so SmartBanner's guard can never fire when one error replaces another, and `lastKnownErrorMessage` **freezes at the session's first error forever**. In our fork that means the red text under the Pay tab header *and the body of every support email* describe the first error of the session, not the current one.

> **On the transaction guard:** upstream's shortcut is pure navigation to `path = .serverSwitch` and never touches `switchWaiting`/`switchIfIdle`. `Root.State.isServerSetupVisible` already covers `path == .serverSwitch`, so arriving via the new row already suppresses the automatic `applySwitch`. And the whole TransactionGuard/AutoServerSelection architecture our `CLAUDE.md` documents is **upstream's, not ours** — all seven files are present at the merge base. No fork-specific guard hazard here.

**Port cost:** (c) is a 5-line, conflict-free must-take with immediate user-visible benefit. (a) is clean code but its text lands in dead views — see §6.3.

---

### 4.3 P1 — Features

#### Ironwood (NU6.3) pool accounting

**Post-merge status: complete in PR #33.** All eleven production sapling+orchard arithmetic sites, including fork-only `OfframpNearBridge`, use the pool-agnostic helpers and include Ironwood. Focused tests cover totals, spendability, banner behavior, and storage isolation.

**Commits:** `95042d8f`, `793a98c1`, `5b792a8d`. **We have:** nothing — `git grep -ci ironwood origin/main -- secant zodlTests` → **0 hits**, and all **ten** hand-summed shielded-balance sites are still live (`BalancesStore` ×4, `WalletBalancesStore` ×2, `SmartBannerStore` ×2, `RootInitialization` ×2), plus the fork-only eleventh at `OfframpNearBridge.swift:226` (§6.1). *(The first draft said six; it undercounted, which is the wrong direction for a funds-visibility item.)*

A new `secant/Sources/Utils/AccountBalanceExtensions.swift` gives `AccountBalance` four pool-agnostic accessors (`shieldedSpendableValue`, `shieldedTotal()`, `shieldedChangePendingConfirmation`, `shieldedValuePendingSpendability`), each summing sapling + orchard + **ironwood**. Every hand-summed expression is replaced across `BalancesStore`, `WalletBalancesStore`, `SmartBannerStore` and `RootInitialization`'s Flexa handoff.

Once Ironwood activates (mainnet height **3,428,143**), any ZEC in that pool is invisible to us: home total, balance breakdown, shielding banner, Flexa handoff all under-report. Not merely cosmetic — `WalletBalancesStore`'s spendability and `BalancesStore`'s `everythingCondition` derive from `shieldedBalance`, so an **Ironwood-only wallet reads as zero-spendable**, and `SmartBannerStore.evaluatePriority8` treats it as an empty wallet.

Three of the four modified files are untouched by us and apply clean; only `RootInitialization.swift` conflicts, and none of our hunks touch the Flexa block.

**Take `5b792a8d`'s `defaultInMemoryStorage` pin with the test** — our suite set is much larger than upstream's, so the parallel-clobber risk it guards is strictly higher for us.

---

#### MOB-1535 — "Total Balance Across Pools" sheet

**Post-merge status: complete in PR #34 on the live `ZappPayView` surface.** The store preserves raw transparent spendability semantics, the displayed pool total includes awaiting-resolution funds, and the Zapp-token sheet supports full precision, fiat, hidden-value masking, accessibility, and a balance tap that remains active when fiat is unavailable or sensitive content is hidden.

**Commits:** nine, `5f959c3e` → `c31d9903`. New file `Features/Home/PoolBalancesSheet.swift` plus per-pool state on `WalletBalances`.

`WalletBalances.State` gains `saplingPoolBalance` / `orchardPoolBalance` / `ironwoodPoolBalance` / `awaitingResolutionBalance` (all added *outside* the memberwise init, so existing construction sites keep compiling), plus a display-only `transparentPoolBalance = transparentBalance + awaitingResolutionBalance`. The split is the subtle part: folding `awaitingResolution` into `transparentBalance` would change auto-shielding and spendability. Invariant pinned by test: `sapling + orchard + ironwood + transparentPool == totalBalance` exactly.

Note `4c70ed71` **reversed** the initial design — the balance stays tappable while balances are hidden (the sheet just masks every value). Gating on `isSensitiveContentHidden` would be an Android-parity divergence.

> ⚠️ **This lands in a screen no Zapp user can reach.** `RootView.swift:116` renders `ZappTabsView` for `destination == .home`; `HomeView(` appears exactly once in our tree — inside its own `#Preview`. So MOB-1535's tap target, sheet and `HomeStore` plumbing are **dead code for us** unless re-homed onto `ZappPayView`. Take the store half (`1e7c7a34`) regardless — it's the regression surface for the Ironwood aggregation — and decide the UI separately.

---

#### Ironwood announcement screen

**Post-merge status: implementation complete in PR #34, with two review follow-ups.** The gate, keychain persistence, debug reset, Root wiring, stale-heal handoff, and Zapp-token view are landed. Before release, verify or publish `https://www.justzappit.xyz/ironwood`: the configured Zapp endpoint returned HTTP 429 during this 2026-08-10 audit, while upstream's Zodl guide returned 200. Also await the `Store.send(...).finish()` tasks in both RestoreWallet announcement-flag tests so late effects cannot escape their assertions. The implementation preserves upstream's retry behavior: an unacknowledged attempt blocked by presentation state may re-read on a later tick; the once-per-session short circuit applies after acknowledgement or presentation.

**Commits:** `a28e2add`, `ac0dc8eb`, `be57b5ca`, `5c32ebc2`, `8bb3c18a`, `5847f151`, `e7b5a879`.

A one-time full-screen announcement once Ironwood activates on-network. The gating logic is where the correctness lives, and each guard is load-bearing:

1. `ironwoodAnnouncementResolved` — in-memory, **per-session, deliberately not persisted** (so force-quitting on the screen without acknowledging shows it again).
2. `tip > 0 && tip >= ironwoodActivationHeight()` — checked **before any keychain access**; `tip > 0` is the "no server round-trip yet" sentinel.
3. Keychain read at most once per session; the flag is tri-state and only exactly `true` counts as acknowledged.
4. `canPresentIronwoodAnnouncement` — re-checked every call and **does not consume the latch when it blocks**, so a blocked attempt retries later instead of being lost for the session.

The keychain flag is deliberately **excluded from `resetZashi()`** — it must survive a wallet reset and app reinstall. Note the contrast with the *other* announcement flag: **both** repos delete `zcashStoredZodlAnnouncementFlag` there (upstream `WalletStorage.swift:197`, ours `:194`) and we add `zcashStoredPINHash` (`:193`) on top — so "announcement flag goes in `resetZashi`" is the established habit on both sides, which makes this exception easy to get wrong on merge.

`5c32ebc2` reverted an earlier "pre-acknowledge on wallet creation" — that made *fresh install → create wallet*, the most obvious way to test the feature by hand, the one path where it could never appear.

Merge simulation — **stale, and it understates the cost now.** `RootDestination.swift` and `RootInitialization.swift` were listed clean; MOB-1512 landed `+3` and `+90/−40` in them respectively (+103/−41 counting the whole port series), and both are conflicts today. Re-run the simulation against `origin/main` before starting.

⚠️ **Two corrections to the "still holding" line, both verified 2026-08-10 against merge-tree `79b80fdb`:**

- **"The three `ZcashSDKEnvironment*` and both `AdvancedSettings*` files are clean" is false — four of those five conflict today.** `ZcashSDKEnvironmentInterface.swift` (1 hunk), `ZcashSDKEnvironmentLiveKey.swift` (1), `AdvancedSettingsStore.swift` (1) and `AdvancedSettingsView.swift` (3). Only `ZcashSDKEnvironmentTestKey.swift` is genuinely clean. Cause: `ab13b850` reimplemented `ironwoodActivationHeight` and the debug reset in our own comment wording instead of taking upstream's text. Every hunk is content-free — comment rewrap plus `{ .max }` vs `{ BlockHeight.max }`, with the activation heights identical on both sides (3_428_143 mainnet / 4_134_000 testnet) — so the resolution is keep-ours throughout. But budget for them; "clean" tells a reviewer not to look.
- **"`WalletStorage*` … adjacent-insert, take-both" is the wrong instruction, and this is a SILENT hazard.** Both sides declare `static let zcashStoredIronwoodAnnouncementFlag` in `WalletStorage.Constants`, at *disjoint* positions — ours above `zcashStoredPINHash`, upstream's after `zcashStoredZodlAnnouncementFlag`. Because the insert points don't overlap, git auto-merges **both** with **no conflict marker** (merged lines 33 and 41; the first marker in that file is at 450). Swift rejects the result with *invalid redeclaration*, so a straight merge yields a non-compiling keychain file and nothing flags it for a human. After any upstream merge run `grep -c 'static let zcashStoredIronwoodAnnouncementFlag'` and delete one copy, keeping ours. The genuinely *marked* conflicts in that file are only the `importIronwoodAnnouncementFlag` parameter name (`acknowledged` vs `enabled` — keep ours) and our PIN-hash block (keep ours).

> ⚠️ **This port adds the third direct destination assignment** (`be57b5ca`, upstream `RootInitialization.swift:903`), which upstream guards with a 10-line comment (`RootInitialization.swift:893-902`) reasoning about the deferred stale-wallet-healed alert. Wire it into the §4.1.2 invariant in the same change.

> ⚠️ **Historical rebrand landmine, now resolved.** Upstream's `ironwoodAnnouncement.continue` was `"Go to Zodl"` / `"Ir a Zodl"`, and its copy test pinned the English value exactly. PR #34 changed the Zapp catalogue and adapted assertion together; keep them coupled on future copy changes.
>
> Also decide on `ironwoodAnnouncementFAQURL`, which points at `support.zodl.com` — a single `private let` in the view.

> ⚠️ **Stack-budget note.** Our fork split `Root.core` into `coreBase`/`coreChat`/`coreFlows`/`coreLogic` because a single `@ReducerBuilder` holding all of them overflowed the 1 MB main-thread stack. The chunks hold **46** elements today (11 + 10 + 13 + 12); the new `IronwoodAnnouncement` Scope makes it **47**. Put it at the end of `coreFlows` and re-check the budget. (The in-code comment at `RootStore.swift:389-390` still says 43 — correct it in the same change.)

---

### 4.4 P2 — Small, cheap, take them

**Post-merge status.** MOB-1475, LICENSE, the Zapp-aware `CLAUDE.md`, and the porting/testing conventions landed in PR #33; PR #34 completed the catalogue union and final byte-format check. The remaining release-housekeeping work is deliberately small: port `d7121bec`, write Zapp-versioned What's New entries after choosing the next marketing version, merge the `35dd58bb` `xcbeautify` prerequisite into our forked release doc, and evaluate `2c72d041` against our Ruby version instead of copying its lockfile blindly. MOB-140 remains a deliberate skip.

| Item | Commit | Cost | Note |
|---|---|---|---|
| ~~**MOB-1475** refund copy~~ | `569be171` | **DONE** | ✅ **Landed in PR #33 — this row is stale and its instructions are now actively wrong.** `origin/main`'s catalogue already carries the fixed English string ("…returned to your wallet in the source currency on the same network…"), byte-identical to upstream's, and `CHANGELOG.md` has its MOB-1475 entry. Re-applying `569be171` would be a no-op at best. Row retained only so the ordinal references elsewhere still resolve. |
| ~~**MOB-140** Sapling shield badge~~ | `9c02a882` | **skip** | **Superseded — do not port.** Both hunks patch a private `addressBlock(...)` helper that our rewritten Receive screen deleted wholesale along with the entire per-address-row layout. `grep -rn "addressBlock" secant/Sources` → **0 hits**. Nothing to fix. *(Two independent agents confirmed this; an earlier draft of this document wrongly listed it as a 4-line take.)* If we ever want the shielded/unshielded distinction visible on Receive — Android shows it, and our `AddressSegment.isShielded` already carries the flag unused for display — that is **new design work** against the Zapp design system, needs agreement per `CLAUDE.md`, and should be tracked separately. |
| **`d7121bec`** update-whatsnew skill | 1 commit | clean cherry-pick | `add` now **replaces** an existing version entry instead of exiting 3; adds `--refresh-date` and a string-aware brace scanner. Our copies are the old exit-3 versions and are otherwise unmodified. |
| ~~**`58b8793d`** LICENSE~~ | 1 commit | **DONE** | ✅ **Landed in PR #33 — the compliance problem this row describes no longer exists.** `origin/main`'s LICENSE carries the `MIT License` header and `Copyright © 2026 Znewco, Inc. (d/b/a Zcash Open Development Lab)`. We additionally **retain** `Copyright 2020 Electric Coin Company`, which upstream dropped — a deliberate superset, not drift, and the correct call for a fork of ECC-derived code. That extra line is why the file still shows as differing from upstream; do not "fix" it. |
| ~~**`a1eae5b8`** CLAUDE.md~~ | 1 commit | **DONE** | ✅ **Landed in PR #33** (`0758cb47` — *not* PR #34; see §7 item 6, which mis-attributes it). All three sites are resolved on `origin/main`: there is no `## App name` section, the Project Overview line reads "Zapp (formerly Zashi)", and the Strings bullet carries no "(Per **App name** …)" clause. The `:9-12` / `:7` / `:93` anchors above are pre-port. |
| **What's New 3.7.4 / 3.8.0 / 3.8.1** | `19cea826`, `52d69414`, `681b942b`, `e2e06bb1` | — | Our catalogue tops out at 3.7.3. These are ZODL release notes; write our own Zapp-voiced entries rather than importing them. |
| **`2c72d041`** Gemfile.lock | 1 commit | judgement | fastlane 2.236.1→2.237.0 etc. Note `.ruby-version`: upstream `4.0.5`, ours `3.3.0` (deliberate Homebrew-ruby divergence), so their lock's Ruby assumptions aren't automatically ours. |
| **`35dd58bb`** release-automation doc | 1 commit | 1 hand merge | Adds `brew install xcbeautify` as a **required** step ("xcpretty predates Swift Testing and would silently swallow its test output"). Lands in the exact block we rewrote for Homebrew ruby. The substance should survive. |

---

### 4.5 Needs a decision, not a port

#### `ab109d8e` — Voting compiled out

**Post-merge status: decision made and complete in PR #34.** Voting is compiled out behind undefined `VOTING_ENABLED`. The audited fork shape is 54 guarded files: 49 production and 5 tests, comprising 47 whole-file guards and 7 partial call-site guards. PIN/authentication/lockout clears and common Flexa/preferences/chat cleanup remain active outside the flag; no build configuration defines it.

**New upstream signal — not yet an implementation.** `upstream/chp-re-enable` is 245 commits ahead / 0 behind `upstream/main`, but its CHP-specific tip `792b76c6` only adds `CHP.md`; it changes no shipping code. The plan confirms three independent off-switches: the app's undefined compilation condition, absent Swift voting wrappers in its selected SDK line, and disabled Rust voting compilation/dependency wiring. It also records unresolved voting-crate selection plus standing transport, endpoint-authenticity, hotkey-storage, and draft-storage security questions. Because the branch is based on the unmerged migration stack, Zapp should keep Voting compiled out and revisit the decision only when upstream lands a buildable, tested final app+SDK state.

Upstream wrapped **56 files** in `#if VOTING_ENABLED` — and defined `VOTING_ENABLED` in **no** build configuration. Coinholder Polling is dead code in every upstream build today. Their stated reason: *"Voting is parked behind an undefined VOTING_ENABLED compilation condition rather than ported to zcash_voting 1.0."*

**We ship it live.** `SettingsView.swift:56` sends `.coinholderPollingTapped`; the full Voting tree, four Voting dependency clients and `zodlTests/VotingTests/` are all present. So a Zapp user can enter a flow that performs voting-service discovery, authenticates rounds, and calls `votingAPI.submitVoteCommitment` / `submitDelegation` / `delegateShares` — three of the six transaction-guard-protected broadcast closures — against infrastructure upstream has decided is on an unsupported protocol version.

**Measured cost if we follow suit:** 35 of the 42 Voting files are **byte-identical to the merge base**; the 7 view files we edited total 28 insertions / 43 deletions of pure rebrand. So the mechanical part is cheap. The friction is in five files we *have* diverged on (three call sites, one test, one scan checker):

- `SettingsView.swift` (+167/−105) — we rewrote the settings list from `ActionRow` to `ZappRow`/`ZappRowDivider`. Upstream's hunk wraps an `ActionRow` block that no longer exists, and a naive wrap of just our row leaves an orphan divider. The `#if` must cover the row **and** its adjacent divider.
- `RootStore.swift` (+270/−7) — ⚠️ **the reset-helper hunk still conflicts, and the trap is in how it gets resolved.** `git apply` of `ab109d8e`'s RootStore hunks against `origin/main` fails on both the `#if` and the `#endif` fragments (our port dropped upstream's comment blocks, and we have a blank line before `flexaHandler.signOut()`), and `git merge-tree` conflicts in that exact span. But both sides' *shape* is now close enough that taking upstream's `#if VOTING_ENABLED` verbatim is the obvious resolution — and our three PIN-lockout removes at `RootStore.swift:734-736` sit inside that span, so that resolution silently compiles the PIN-lockout reset out of every build. Lift those three lines above the `#if` first. See §4.1 point 3.
- `RootInitialization.swift` (+165/−41) — upstream wraps `votingMetadata.resetAccount(...)` / `votingMetadata.reset()` inside `.resetZashiSDKSucceeded`, a region MOB-1512 reshaped.
- `zodlTests/UtilTests/RootInitializeSDKHealTests.swift` — upstream's `ab109d8e` wraps a `removedKeys.contains(.votingConfigOverrideURL)` assertion that our version of the file does not contain at all (§4.1 residuals).
- `ScanChecker.swift` (+17) — we added `ChatPublicKeyScanChecker` (`id = 6`) immediately after the voting checker, so upstream's `#endif` lands exactly where our struct begins.

**Recommendation:** get a straight answer on what specifically breaks in voting under NU6.3 before deciding. The commit message asserts incompatibility without evidence, and hiding a shipped feature is a bigger product cost for us than for upstream. If we do follow: add nothing to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` — leaving the flag undefined *is* the mechanism.

---

#### `Localizable.xcstrings` format — **fixed** (`06c07757`), then regressed by one byte

**Post-merge status: complete in PR #34.** The catalogue is Xcode-style JSON, ends in `}` with no newline, contains the adapted parity strings without ZODL branding, and the exact formatting rule is documented in `CLAUDE.md`.

Upstream commit `5cc43c51` exists because someone removed one key using a Python script that loaded and re-dumped the whole catalogue, producing a five-figure line diff for a ~17-line change. We made the identical mistake in `aab15ccd` (2026-07-13) — 12,152 insertions / 12,121 deletions flipping the catalogue from Xcode's serialization to Python's — and `06c07757` reversed it as a standalone, code-free commit. Verified semantically clean: 1,642 keys before and after, zero added, zero removed, zero values changed at any depth.

**The payoff is real and measured.** The two string-touching ports that followed produced surgical hunks (35 and 51 lines) instead of whole-file conflicts; whole-file conflicts on the catalogue fell 8 → 2; and `569be171`'s hunk now `git apply`s cleanly (§4.4), where it did not before.

**Conformance checklist** — what "Xcode's format" means, and where we stand on `origin/main`:

| | Xcode writes | `json.dump` writes | Status |
|---|---|---|---|
| Separator | `"sourceLanguage" : "en"` (space **before** the colon) | `"sourceLanguage": "en"` | ✅ 18,341 spaced, 0 unspaced |
| Empty objects | brace, blank line, closing brace | `{}` collapsed | ✅ 0 collapsed |
| Key order | Xcode's collation (`"%@ · "` sorts before `"%@ / %@"`) | codepoint sort | ✅ our shared keys are in upstream's exact order |
| Trailing newline | none — file ends `}` | one | ✅ **correct** — see below |
| Non-ASCII | literal | `\uXXXX` escapes | ✅ 1,214 literal, 0 escaped |

✅ **The trailing-newline row previously read "❌ regressed". That was wrong, and it contradicted this section's own post-merge header.** Verified 2026-08-10: `origin/main`, `upstream/main` and the working tree all end with bytes `22 0a 7d` — `"` newline `}` — i.e. `}` with **no** trailing newline. The `9556aa6b` regression was real when observed and was fixed before this document was written; the table was simply never updated. Reproduce with `git show origin/main:secant/Resources/Localizable.xcstrings | tail -c 3 | xxd`.

The two positive magnitudes were also stale (they were pre-PR-#34 numbers, taken when the catalogue held 1,647 keys rather than today's 1,673) and are corrected above. Both ✅ verdicts — 0 unspaced, 0 escaped — reproduce exactly.

**What the formatting commit alone did not fix.** At that point the catalogue still needed a key-level union and older remote branches still carried the Python format. PR #34 completed the audited union. Any surviving branch based before `06c07757` should still be rebased or have its semantic string changes re-taken by hand.

**~~Still owed~~ — done.** The rule *is* written down: `CLAUDE.md`'s Strings bullet carries "Never round-trip the catalogue through `json.dump`, and never append a trailing newline; it must end with `}` and no `\n`." The cited grep (`git grep -i 'json.dump' origin/main -- CLAUDE.md`) returns a hit, not zero. This paragraph contradicted both this section's own post-merge header and §7 item 1.

---

## 5. The merge surface

> **Historical snapshot.** This section explains why the ports required hand resolution; it is not a list of remaining conflicts. PRs #33 and #34 have already integrated the audited upstream range. Preserve the skip-list and fork-specific rationale when reviewing a future upstream advance, but recompute all counts from the new merge base.

### 5.1 What's already ours

`git patch-id --stable` over both ranges yields **exactly 7 matches** — the oldest 7 commits on our branch *are* upstream's, replayed under new SHAs (the whole MOB-1472 curated-swap series plus `030df8ab`). `SwapAsset.swift`, `SwapAndPayInterface.swift`, `SwapAndPayLiveKey.swift`, `AddressBookStore.swift` and `SwapAndPayAssetFilterTests.swift` are **character-for-character identical to `upstream/main` today**. There is no collision in the swap-asset area at all.

### 5.2 The both-sides files, classified

> ⚠️ **Recount 2026-08-10: it is 147 both-sides files, not 63.** The 63 was measured at `60ca5dde`. Against the unchanged merge base, the both-sides set grew 47 → **147** as PRs #33/#34 landed, so the class counts below (14/19/26/4 ≈ 63) describe a surface that no longer exists. Roughly 40 of the newly-contended paths are Voting files from the PR #34 compile-out; even excluding those, 60 files newly became both-sides. Re-derive before relying on any classification:
> `comm -12 <(git diff --name-only $BASE upstream/main|sort) <(git diff --name-only $BASE origin/main|sort) | wc -l`
>
> The counterweight, measured the same day: of the **156** files upstream touched since BASE, **70 are now byte-identical to ours** and 86 still differ. Convergence is real — the both-sides count grew because we *changed* files to match upstream, not because we drifted.

| Class | Count at `60ca5dde` | Meaning |
|---|---|---|
| **AUTO** | 14 | Identical both sides (MOB-1472, plus files the ports brought byte-identical to upstream) — resolves itself |
| **TRIVIAL** | ~19 | Disjoint regions; mostly our Zapp design tokens vs upstream's `#if VOTING_ENABLED` wraps |
| **MECH** | ~26 | Conflicts, but resolution is mechanical (adjacent inserts, keep both) |
| **HARD** | **4** | `RootStore.swift`, `RootInitialization.swift`, `RootCoordinator.swift`, `project.pbxproj` |

**Measured `git merge-tree` conflict hunks, before the ports → after:**

| File | 60ca5dde | c8c3e942 (PR #32) | **Zapp source snapshot (862672ab)** |
|---|---:|---:|---:|
| `RootStore.swift` | 4 | 14 | **17** |
| `RootInitialization.swift` | 1 | 9 | **15** |
| `RootCoordinator.swift` | 6 | 6 | **12** |
| `RootTransactions.swift` | 0 | 0 | **3** |
| `RootDestination.swift` | 0 | 1 | 1 |
| `RootView.swift` | 0 | 0 | 0 |
| `project.pbxproj` | 22 | 22 | 22 |
| `Localizable.xcstrings` | 8 | 2 | **8** |
| **conflicting files, whole merge** | **24** | **30** | **57** |

> ⚠️ **Corrected 2026-08-10.** The column previously labelled `origin/main` was a snapshot of `c8c3e942` — the PR #32 merge, i.e. *before* the very ports whose effect the caption claims to measure. Every value in it (30 / 14 / 9 / 6 / 22 / 2) reproduces exactly at `c8c3e942`. The true post-port numbers are in the last column: the whole-merge surface is **57 files, not 30**, `RootCoordinator.swift` **doubled** rather than staying flat, and `Localizable.xcstrings` went **back up to 8**, not down to 2. `RootTransactions.swift` newly conflicts (3 hunks) because PR #33 rewrote upstream's three rationale comment blocks in our own shorter wording — its *code* is identical to upstream's, so all three hunks are prose.
>
> Dependent prose elsewhere inherits the stale figures and is wrong by the same amount: §5.2's "`RootStore.swift` … 4 of the 14 hunks", §5.2's "`RootCoordinator.swift` — unchanged at 6 conflicts", §5.4's "`RootStore.swift` went from 4 hunks to 14", and §7 item 8's "ten extra conflict hunks" (it is thirteen).
>
> **Shell footgun that produced the original miscount.** In zsh — this repo's shell — `git show "$TREE:secant/…"` is parsed as a `:s` history modifier, git receives a mangled argument, and the `grep -c` prints `0`. Always brace it: `git show "${TREE}:secant/…"`. See Appendix D.
>
> Twenty-seven conflicting paths the table never mentioned are wallet-plumbing files, not UI: `Package.resolved`, all four `WalletStorage*`, both `ZcashSDKEnvironment*`, `SharedStateKeys.swift`, `CHANGELOG.md`, and the fifteen `zodlTests/` add/add collisions in §5.3.

The four hard ones:

- **`RootStore.swift`** — we added 11 `Path` cases, 12 feature states, 18 Action cases, 4 dependencies, and split `core` into four `@ReducerBuilder` chunks for the stack budget. What upstream still adds here is `CancelTransactionsFetchId`, `ironwoodAnnouncement*`, and the **widened `case fetchedTransactions`** (one associated value → two). `isInitializingSDK`, `isStaleWalletHealedAlertPending` and the heal statics are now on *both* sides, in different wording — see §5.4. Four of the 14 hunks are our deliberate signature divergence on `clearDeviceScopedWalletState`; keep ours.
- **`RootInitialization.swift`** — new to this list. Most of the 9 hunks are doc-comment and case-ordering divergence around code that behaves identically (e.g. `presentStaleWalletHealedAlert` / `staleWalletDatabaseHealed` declared in opposite order). Resolution is "keep ours" throughout, but that is nine hand-resolutions where there was one.
- **`RootCoordinator.swift`** — **12** conflicts (it doubled, it did not stay at 6), one of them a 317-line block. Our 299-line chat/offramp/unified-send insert sits at old line 254; upstream inserts at 254 *and* 314/353. Plus the `.send(.loadChatContacts)` silent-merge hazard (§4.2). The growth is ours: the parity ports added +109/−15 to this file (`0758cb47` +95/−15 for the MOB-1581 send-completion arms, `ab13b850` +14), which also falsifies §8's claim that it "stayed at its fork-point divergence".
- **`project.pbxproj`** — 22 conflict hunks, but **18 are version-number noise** (9× `MARKETING_VERSION`, 9× `CURRENT_PROJECT_VERSION`, all "keep ours"). The 4 real ones are ZcashLightClientKit entries sitting adjacent to our Firebase/ZappMessaging/ZappOfframp entries.

Plus a new category the first draft had no reason to anticipate: **seven add/add paths** where both sides independently created a file at the same path — `KeystoneFirmwareUpdateView.swift`, `KeystoneFirmwareVersion.swift` and five test files (§5.4). Those are not textual resolutions; they are keep-ours / take-theirs / union decisions.

### 5.3 What is *not* a problem

- **`project.pbxproj` file registration.** Both repos use `PBXFileSystemSynchronizedRootGroup`. Upstream's new test and source files need **zero pbxproj surgery** — dropping the directories in is sufficient. Now confirmed rather than predicted: the five landed ports added seven files with a **zero-line `project.pbxproj` diff**.
- **`Localizable.xcstrings` semantics.** Base 1,107 keys → ours **1,647** (+540, −0), upstream 1,138 (+31). Of upstream's 31 new keys we now hold **5** (the MOB-1512 and MOB-1510 strings) — and all five are either byte-identical to upstream or differ *only* by the ZODL→Zapp rebrand, so it is still **zero semantic collisions**. English values we changed: 70. **26** keys left to transplant, and since `06c07757` they three-way-merge normally instead of needing hand transplantation. Still: do a key-level union, never a text merge.
- **`zodlTests/` — no longer true, and the corrected figure is ~4× larger.** Our **43** test additions (not 28) now collide by path with **all 19** of upstream's new test files (not 5). Four self-resolve because the blobs are byte-identical on both sides — `AddKeystoneHWWalletCoordFlowTests`, `ZcashAccountsTestFixture`, `ModelsTests/TransactionStateTests`, `SendTests/KeystoneFirmwareTests` — leaving **15 genuine add/add conflicts**, not four:

  | File | Hunks |
  |---|---:|
  | `UtilTests/RootInitializeSDKHealTests` | 19 |
  | `RootTransactionsTests/RootTransactionsAccountSwitchTests` | 13 |
  | `UtilTests/IncompatibleServerDiagnosticsTests` | 11 |
  | `UtilTests/WalletDatabaseSeedReconcileTests` | 10 |
  | `UtilTests/RootInitializeSDKSingleFlightTests` | 9 |
  | `RootTransactionsTests/RootSendCompletionRefreshTests` | 8 |
  | `UtilTests/RootIronwoodAnnouncementGateTests` | 8 |
  | `SendTests/KeystoneFirmwareCoordFlowTests` | 3 |
  | *(+7 more, 1–3 hunks each)* | |

  These are two independently written suites at one path; a textual resolution produces a suite that compiles and tests neither design. Decide keep-ours / take-theirs / union per file. See §5.4.
- **Assets.** Upstream added **zero** image or color assets since the fork point, and the only `Sources/Generated/` change is the one `SharedStateKeys.swift` line (`swapAssetsCatalog`) **we already have**. No port in this document needs a new PNG or colorset.
- **Our string catalogue is a strict superset of the base** — 1,647 = 1,107 base + 540 fork-only. We dropped no upstream keys.
- **Everything else.** Upstream changed **nothing** under `.github/`, `Scripts/`, `fastlane/`, `xctemplates/`, or in `Rakefile`, `.swiftlint*.yml`, `SWIFTLINT.md`, `CODE_STRUCTURE.md`, `CODE_REVIEW_GUIDELINES.md`, `README.md`, `CONTRIBUTING.md`, `BACKGROUND_SYNCING.md`, `CONDUCT.md`, `.xcode-version`, any `.entitlements` or any `Info.plist` since the fork point — so **none of them can conflict**. Note the first draft's trailing claim that they are "byte-identical in our tree too" was wrong when written: we have diverged on ~27 of those paths (CI bootstrap, the ZappMessaging/Firebase scripts, fastlane, every `Info.plist` and `.entitlements`) for the rebrand. Harmless for the merge, but do not use that sentence to justify a blind `--ours`/`--theirs` sweep.
- **`docs/`.** `Architecture.md`, `CODING_GUIDELINES.md`, `voting-service-discovery.md`, `testing/*` and `docs/README.md` are all **IDENTICAL** between the two repos. There is nothing to port from upstream's docs except `release-automation.md`.

> **Two `project.pbxproj` gotchas if you copy upstream's SDK block wholesale:** (1) upstream `main` carries a defect — `zodl-internal` lists ZcashLightClientKit **twice** in `packageProductDependencies` and links it twice in its Frameworks phase, an orphan from `42f732a2` that survived three rewrites. (2) Upstream has **four** `ZcashLightClientKit` product-dependency entries and only **one** carries a `package =` line — and that one points at the local `../zcash-swift-wallet-sdk` reference we are deliberately not adopting (§3.3). The other three would **silently under-link**.

### 5.4 Do not double-apply — the ports were reimplementations, not cherry-picks

This is the one structural fact the first draft could not have: PRs #28–#32 re-expressed upstream's end state in our own wording instead of `git cherry-pick -x`. The behaviour matches; the text does not. Consequences:

1. **A straight `git merge upstream/main` would try to apply MOB-1512 and MOB-1510 a second time.** The upstream commits are now present in adapted form and need an explicit skip list: `2561efaf` (#1943); `92320ace` (PRO-325); `68a9699b`, `a9933325`, `a5155e9a`, `4394adbc`, `d254e77e`, `72b962fa`, `998ca6e8` (MOB-1512 + SDK follow-up); `7a60320b`, `86c6ad14`, `1b35c254`, `8ce0b527`, `c0de0468`, `1e2506aa`, `0df8c7bb`, `6e6fe320` (MOB-1510).
2. **~~Sixteen~~ one hundred files moved from "clean, we never touched it" to "both sides changed it."** The both-sides set grew 47 (`60ca5dde`) → 147 (`origin/main`) against the unchanged base. The sixteen the original draft named — the `SendConfirmation` Keystone set (3), six CoordFlow files, `RootDestination.swift`, `SDKSynchronizerTest.swift` and five test files — are a strict subset, not the total. Statements elsewhere in this document that those files are clean were true when written and are false now.
3. **~~Seven~~ twenty-four paths are add/add conflicts** (§5.2, §5.3): `KeystoneFirmwareUpdateView.swift` and `KeystoneFirmwareVersion.swift`, plus **all 19** colliding test files. Four self-resolve byte-identically (`KeystoneFirmwareVersion`, `KeystoneFirmwareTests`, `AddKeystoneHWWalletCoordFlowTests`, `ZcashAccountsTestFixture`, `TransactionStateTests`); the rest need a keep-ours / take-theirs / union decision each.
4. **~~`SDKSynchronizerTest.swift` is the SDK-bump tripwire.~~ Discharged.** Both sides now declare `prepareWith … async throws -> Initializer.InitializationResult`, and the file is **byte-identical to `upstream/main`** (blob `e8cfe63f`) — it does not appear in the merge-tree conflict list at all. There is no hunk left to resolve and no fast path left to reconnect; §4.1.1 completed that work in PR #34. This point also wrongly listed the file among the newly-conflicting sixteen in point 2.

**Rule going forward:** port with `git cherry-pick -x` wherever the patch applies, and reserve rewrites for files we have genuinely diverged on. Every rewrite buys a conflict we pay for at merge time — `RootStore.swift` went from 4 hunks to 14 for zero behavioural gain.

---

## 6. Fork-only work upstream cannot do for us

These are gaps upstream's diff will never show, because the code only exists here. Each must ship **in the same change** as its upstream counterpart.

### 6.1 `OfframpNearBridge` under-counts Ironwood → hard user-visible failure

**Post-merge status: fixed in PR #33.** `OfframpNearBridge` now uses `shieldedSpendableValue`; this section remains as the reminder to audit fork-only arithmetic on every future pool addition.

`secant/Sources/Dependencies/Offramp/OfframpNearBridge.swift:226` computes
`let spendable = balance.saplingBalance.spendableValue + balance.orchardBalance.spendableValue`
and gates the NEAR top-up against it **twice** — once before proposing the transfer and once after `proposeTransfer` returns the fee.

After Ironwood activates, a user whose funds have migrated is told `insufficientSpendableBalance` and **blocked from a top-up they can actually afford**. The SDK would happily build the proposal; our own pre-flight guard rejects it first. This is the one Ironwood under-count that produces a hard failure rather than a wrong number.

**Fix:** with `AccountBalanceExtensions.swift` landed, replace line 226 with `balance.shieldedSpendableValue`.

> This site is **invisible to every upstream diff and to the compiler**. `AccountBalance.init` defaults `ironwoodBalance` to `.zero`, so nothing here fails to build — it just quietly under-reports. Grep our own tree for `saplingBalance`/`orchardBalance` when porting `95042d8f`; there are **16** such hits, and this is the only one upstream cannot fix for us.

### 6.2 The unified send flow is a **fifth** Keystone signing surface — gated and corrected

**Post-merge status: fixed in PR #33.** A quoted empty `depositAddress` is treated as absent and falls back to `swapState.address`; a non-empty quoted deposit address wins. Tests now record and assert the actual metadata address, cover nil/empty/non-empty quote cases, and prove blocked firmware records nothing. The fifth-surface invariant below remains standing.

Upstream gates four Keystone signing surfaces because upstream has four. Our unified-send rewrite created a fifth, and MOB-1510 covered it: the gate is at `SendCoordFlowCoordinator.swift:197`, `markSwapTransaction` was moved out of `.scan(.foundPCZT)` and deferred to `.confirmWithKeystone(.keystoneFirmwareAccepted)` (`:211-215`), the Close handler clears `detectedKeystoneFirmware` / `isKeystoneCodeFound` (`:223-224`), and `KeystoneFirmwareCoordFlowTests` adds two unified-send cases upstream has no equivalent for.

**Why this section stays.** Of the five Keystone signing surfaces, four are now byte-identical to upstream (`SwapAndPayCoordFlowCoordinator`, `SignWithKeystoneCoordFlowCoordinator`, `SendConfirmationStore`, and `ScanCoordFlowCoordinator` bar an unrelated 3-line delta) — and **exactly one diverges: ours**. Upstream has two Keystone entry points in `SendCoordFlowCoordinator`; we have a third at `:452` (`.swap(.confirmWithKeystoneTapped)`). So every future upstream Keystone commit will `git apply` clean on the other four and **silently miss this one**. That is §6's whole premise, and it is a standing rule, not a discharged task.

**Standing invariant:** `.swapSendAuthorized` (`:437`) is the non-Keystone corridor and must keep its own timing. There are now two `markSwapTransaction` call sites in one file with deliberately different timing — `:214` gated, `:438` ungated — sharing a helper at `:592`. A future "dedup these" refactor reintroduces the phantom-swap bug.

The former address-selection residual is closed. Keep the tests asserting address values rather than weakening them back to call counts: metadata corruption here is permanent and is invisible to upstream's four-surface suite.

### 6.3 Upstream's sync-error work lands in views we don't mount

**Post-merge status: fixed in PR #34.** The diagnostics were re-expressed in the live Zapp surfaces: the current message is rendered, Switch Server is limited to incompatible-server errors, retry behavior is gated appropriately, and support reports receive the same detail. Do not replace this with upstream's dead `HomeView`/`SmartBannerView` presentation on a future sync.

`SmartBannerView` is mounted only by `HomeView`, whose sole remaining reference is its own `#Preview`. Our live surface is `ZappSyncErrorSheet` / `ZappPayView`. Two consequences:

- `ZappSyncErrorSheet.swift:34` declares `let errorMessage: String` and **never uses it** — so #1948's new 5-line diagnostic message would reach the support report but never the screen.
- `ZappSyncProgressRow` renders the message as `Text(detail).lineLimit(1)` — only the first sentence survives.
- Our sheet already offers "Switch server" for **every** sync error. So for us upstream's logic is **inverted**: the row exists and needs *restricting* to the incompatible-server family, and the "Try Again" row is the one that should hide, since retrying is what cannot work.

**Fix:** thread `lastKnownErrorIsIncompatibleServer` through `ZappPayView.syncErrorSheet()`, render the message body in `ZappSyncErrorSheet`, and gate both rows. Use Zapp tokens (`ZappColors`/`ZappTextStyle`), not upstream's `Design.*` — load the `zapp-ui-standards` skill first.

### 6.4 The heal clears *our* device-scoped state — across three sites, not one

Done, but **not where this section originally said to put it**, and the split is now the thing to know. Teardown lives in three places with different obligations:

| Site | What | Constraint |
|---|---|---|
| `RootStore.swift:721` `clearDeviceScopedWalletState` | UserDefaults incl. the three PIN keys, voting DB + sweep, Flexa, cached prefs, read-transaction storage, **and the chat-contacts loop** | **synchronous on purpose** — see its doc comment; must run before `walletStorage.clearEncryptionKeys` |
| `RootInitialization.swift:382-397` (heal only) | `offramp.invalidateSession()`, `zappMessaging.wipe()` | async; must **not** wipe the keychain — seed B has to survive |
| `RootInitialization.swift:603`, `:684-687` (delete only) | the same async teardown on the delete path | — |

So "extend `clearDeviceScopedWalletState` to cover chat history and offramp" is wrong advice today: those two have async teardown APIs and deliberately live outside the synchronous helper. A reader who greps the helper, finds no chat history, and adds an `await` into it will not compile.

**The cost of the split:** every future device-scoped store must be added in **two** places, and only two of the four current items would fail a test if the heal side were missed (§4.1 residuals). One artefact already: the heal clears `.appAuthenticationMethod` / `.failedPINAttempts` / `.pinLockoutEndTimestamp` but never `removePINHash()` — `zcashStoredPINHash` is deleted only by `WalletStorage.resetZashi()`, which the heal correctly never calls. `AppSecurityLiveKey` falls back to `.biometric`, so it is not a lockout, but an orphaned PIN hash stays in the keychain.

**One thing a heal still leaves behind, by design:** wallet A's encrypted address-book file stays on disk *and* in the user's iCloud remote storage. After the re-prepare the SDK mints a new `AccountUUID`, so it is orphaned rather than readable under wallet B — not a leak, but nobody had written it down.

### 6.5 Restore-path SDK initialization was relocated — and a three-way merge keeps our deletion silently

*(Added 2026-08-10. This divergence was undocumented anywhere; it is the kind §6 exists to catch.)*

BASE (`0d3b93ad`) and `upstream/main` both dispatch `.initialization(.initializeSDK(.restoreWallet))` as the **first element of the `.concatenate`** in `.onboarding(.path(.element(id: _, action: .restoreInfo(.gotItTapped))))`. Our commit `191b0810` ("feat: add Android-aligned wallet onboarding") **deleted that line** — `RootCoordinator.swift:660-674` keeps every flag write but returns only `.checkBackupPhraseValidation` + `.batteryStateChanged` — and moved restore-time SDK init to a fork-only action `.onboarding(.walletProvisioned(.restored))` (`RootStore.swift:669`), sent from `RestoreWalletCoordFlowCoordinator.swift:93` immediately after `walletStorage.importWallet`.

**Consequence.** `prepareWith(.restoreWallet)` and `sdkSynchronizer.start` now run **several screens earlier** — before chat-username, identity derivation and app-lock — and therefore *before* `isRestoringWallet`, `udIsRestoringWallet`, `udLeavesScreenOpen` and `walletStatus = .restoring` are written by the `restoreInfo` arm. That is the **inverse** of upstream's ordering. Since `checkRestoreWalletFlag` only clears the restoring state on `state.isRestoringWallet && syncStatus == .upToDate` (`RootInitialization.swift:198-199`), a fast restore that reaches `.upToDate` before the user taps "Got it" leaves `walletStatus = .restoring` set until the next sync tick. **Worth verifying by hand.**

**Merge hazard.** Base has the line and upstream never changed it, so a three-way merge honours our deletion **silently** — same shape as the §4.1 rationale-comment trap. Anyone "restoring" it would double-initialize.

### 6.6 UI ports that are rewrites, not copies

**Post-merge status: both remaining rewrites landed in PR #34.** `PoolBalancesSheet` and `IronwoodAnnouncementView` use the Zapp token layer and are wired to reachable Zapp surfaces. The guidance below is retained as a future merge guard.

**Two** upstream views had to be **re-expressed** in the Zapp token layer rather than copied — they compile as-is upstream but look nothing like their Zapp siblings:

- `PoolBalancesSheet.swift` — written entirely against Zashi primitives (`zashiSheet`, `Design.Radius._2xl`, rounded cards). Treat as a rewrite against the same store shape.
- `IronwoodAnnouncementView.swift` — `zFont` / `ZashiButton` / `Design.Text.*` / `Design.Spacing.*` throughout, plus `Asset.Assets.zashiLogo` (`:50`). Rewrite against `ZappTextStyle` / `ZappButton` / `ZappColors` and a Zapp brandmark; take it with §4.3's rebrand decisions.

> **`KeystoneFirmwareUpdateView.swift` is done — and is now a merge guard, not a task.** Ours has the 148pt illustration (`:15`), `.zappFont(.display, style: ZappColors.text)` (`:34`), `.multilineTextAlignment(.center)` (`:35` — the whole point of `0df8c7bb`, and deliberately a one-off on the *title*: `PreSendingFailureView` centres only its body text (`:42`), never its title, so nothing structural defends it), `ZappButton` (`:45`) and `ZappColors.bg` (`:52`). Upstream created a file at the same path, so this is an **add/add conflict** (§5.4) and a "take theirs" resolution silently restores `ZashiButton`, `.zFont(.semiBold, size: 28, style: Design.Text.primary)` and `.applyFailureScreenBackground()`. **Ours wins on this path.** One conscious decision remains: upstream splits out a store-less `KeystoneFirmwareUpdateContent` so a presentation without its own `SendConfirmation` store can reuse the copy; we collapsed it, and nothing upstream consumes it today.
- The #1920 failure sheet in `AddKeystoneHWWalletCoordFlowView.swift` is new UI too, though it needs less work — our rebrand set `Design.Radius._xl = 0`, so it renders square like the rest of the app automatically.

---

## 7. Conventions upstream encoded in commits, not docs

**Post-merge status: incorporated in PR #33.** `CLAUDE.md` now records the live/dead surfaces, catalogue byte format, shared-state test isolation, deterministic async tests, support-data dependency override, cherry-pick-first rule, and rationale-preservation rule. The new/adapted suites apply those conventions. The list below is retained as the source rationale.

We defer to upstream on plumbing conventions, and several of these are not written down anywhere — they only exist as commit messages. Worth adding to our `CLAUDE.md`:

1. **Never round-trip `Localizable.xcstrings` through `json.dump`, and never let a tool append a trailing newline** (`5cc43c51`; and our own one-byte regression in `9556aa6b`). The file must end `}` with no `\n`. See §4.5. **Now documented in `CLAUDE.md`.**
2. **Pin `defaultInMemoryStorage` per test** (`5b792a8d`). Swift Testing runs suites in parallel; a concurrent suite nilling `@Shared(.inMemory(.selectedWalletAccount))` made a regression test pass *vacuously*. The affected Root, WalletBalances, SmartBanner, restore, settings, and announcement suites now create state/store inside fresh in-memory storage.
3. **Never gate a regression test on the wall clock** (`3b6a7130`). The original starvation test mocked a 300ms fetch, re-dispatched every 50ms and asserted in a 1s window — green in isolation, red under the parallel run, and un-widenable because a stretched interval makes the *broken* implementation pass too. Gate on explicit signals.
4. **Never assert a value equal to a property's default** (`2d76f83d`). The note-count assertions checked the counts equalled `0`, restating the defaults — so they held even with the SDK wiring deleted.
5. **Any test touching `SupportDataGenerator` must override `walletStorage`** (`6a6e16a1`) — it reads `@Dependency(\.walletStorage)`, which swift-dependencies refuses to resolve live in a test context. Fails at **runtime**, not compile time.
6. **Keep the stale `## App name` rule out of `CLAUDE.md`** (`a1eae5b8`) — it was removed in **PR #33** (`0758cb47`, merged as `e040da26`) because it told agents to write "ZODL" into Zapp strings. *(Corrected: this previously said PR #34, which never touched `CLAUDE.md` — `0758cb47` is the file's only commit since BASE. Appendix A repeats the same wrong attribution.)*
7. **Document what's dead in this fork.** `HomeView` and `SmartBannerView` are unreachable; `ZappTabsView`/`ZappPayView`/`ZappSyncErrorSheet` are the live surfaces. Multiple independent reviewers rediscovered this the hard way; it costs porting time every time.
8. **Port with `git cherry-pick -x`, not by rewriting** (learned from PRs #28–#32). Where upstream's patch applies, take it verbatim; reserve rewrites for files we have genuinely diverged on. Re-expressing upstream's logic in our own wording cost `RootStore.swift` ten extra conflict hunks and `RootInitialization.swift` eight, for zero behavioural gain. See §5.4.
9. **When a port extracts our code into an upstream helper, carry the comments too.** The early MOB-1512 extraction kept every fork-specific *line* and dropped its explanations; PR #34 restored the live/dead-surface and safety rationale in code/docs. Lines survive review; the reasons they exist do not unless we deliberately preserve them.

---

## 8. What to do next

Core parity through upstream 3.8.1 is complete. PR #33 landed the first safety tranche; PR #34 landed the SDK bump, remaining correctness work, Ironwood, live Zapp UI adaptations, tests, strings, and Voting compile-out; PR #35 closed the recurring-server regression and adapted the upstream stuck-`Sending…` hardening. Upstream `main` has not advanced beyond the audited `512fa1c8`, so there is no new upstream-main feature batch to port today.

The newly fetched upstream branches do not change that conclusion. `agent/fix-main-e2e` is now a moving exact-Slipstream/local-FFI CI experiment, not an app correctness port. `chp-re-enable` is a planning checkpoint on the migration stack, not a finished Coinholder Polling implementation.

### Recommended next sequence

*(Re-verified 2026-08-10 against `upstream/main = 512fa1c8` and the Zapp app-source snapshot at `862672ab`; all six branch positions in the watch table below reproduce exactly. PR #35 is the newest app-source PR; PR #36 is docs-only.)*

0a. ✅ **Fix the incompatible-server flag regression — completed in PR #35** (§4.2, #1948). Recovery now clears the cached message together with the flag, so a recurring identical error re-arms correctly; a dedicated regression test covers the full sequence.

0b. **Backfill two missing dedicated `CHANGELOG.md` entries.** MOB-1593 (empty-memo filter) and the Keystone account-switch history fix still lack dedicated lines. PR #35 added the MOB-1581 entry while landing the final transaction-refresh hardening.

0c. ✅ **Commit this document — completed in docs-only PR #36.** The standing fork policy and its audited status now live in the repository.

1. **Clear the two post-merge review follow-ups.** Verify/publish the configured first-party Ironwood guide (the endpoint returned HTTP 429 during this audit), and make both `RestoreWalletAnnouncementFlagTests` await their `Store.send` tasks through `.finish()` so no late wallet-provisioning effect can evade the invariant assertion.
2. **Restore hosted CI.** GitHub Actions for PRs #34 and #35 never started because the account payment/spending limit blocked jobs. This is operational rather than a source defect, but it is the only missing validation channel; PR #34's focused local matrix passed 68 tests across 11 suites, and PR #35 compiled cleanly and passed 14 tests across 2 suites.
3. **Finish release housekeeping.** Port `d7121bec`; choose Zapp's next marketing version (`1.0.2` versus `1.1.0`) before editing `secant/Resources/WhatsNew/whatsNew*.json`; write Zapp-owned notes rather than importing upstream's 3.7.4/3.8.x version numbers; merge `35dd58bb`'s required `xcbeautify` step into our forked release document; evaluate `2c72d041` against Zapp's Ruby 3.3 toolchain.
4. ✅ **Port the non-duplicated stuck-Sending hardening — completed in PR #35.** The adapted port retains Zapp's battery-conscious lifecycle, adds event-filter-first handling, foreground resubscription and pending-Zcash reconciliation, and keeps the final swap-only exclusion.
5. **Harden the fork-only offramp poller — the next live correctness candidate.** Define terminal/deadline behavior for provider `EXPIRED`, indefinitely `PROCESSING`, and unknown statuses, then add end-to-end poll tests. The shared mapper fix for `FAILED` is already landed; the unbounded consequence exists only in Zapp.
6. **Close the remaining stale-wallet hardening gaps.** Add delete-path coverage; assert Flexa/preferences/offramp teardown ordering rather than merely recording calls; add actionable copy for the protected view-only-database refusal; and manually verify the deferred alert over the live Root overlay/path combinations.
7. **Pre-pay two migration conflicts.** Independently change `ZashiSheetModifier.sheetContent` to closure-based content with `WithPerceptionTracking`, then stabilize the ordering of fork-only `RootStore.Path`/`RootCoordinator` chat and offramp cases.
8. **Do not merge the full migration or re-enable CHP yet.** Both remain absent from upstream `main` and moving. Re-audit when the migration gate stabilizes and CHP has a final app+SDK+Rust dependency graph; then bring the migration subsystem in dark before making a separate product/security decision about polling.

### Current branches worth watching

| Branch | Current state | Decision |
|---|---|---|
| `upstream/agent/fix-main-e2e` | 5 ahead / 0 behind, tip `9128e8fe` | No port: exact Slipstream SDK checkout, locally built matching FFI and CI retry experiment. Watch whether upstream stabilizes it. |
| `upstream/fix/stuck-sending-tx` | 3 ahead / 10 behind, tip `15f37964` | Ported/adapted in PR #35; retain as provenance and watch only. |
| `upstream/kris/behavior-based-migration-gate` | 233 ahead / 0 behind, tip `c9e8acc2` | Best signal for the migration's final gate and broadcast behavior. |
| `upstream/migration/gardening-test` | 247 ahead / 0 behind, tip `4eae0b8c` | Active integration branch; too broad and too mobile to merge now. |
| `upstream/migration/rebuild` | 225 ahead / 0 behind, tip `2e53b536` | Historical migration baseline, not the current target. |
| `upstream/chp-re-enable` | 245 ahead / 0 behind, tip `792b76c6` | Planning-only CHP checkpoint based on the migration stack; keep Voting off until code and dependency decisions land. |

### Historical migration analysis

### Should we wait for the Ironwood migration branch?

**No.** There is a tag `release-baseline-2026-08-08` (`2e53b536`) sitting **225 commits ahead of `upstream/main` and 0 behind**, on `migration/rebuild` and `migration/gardening-test`. It is the Orchard→Ironwood wallet-migration flow: **208 files, +42,704/−693**, built in 11 days, adding ~18.8k lines of new app source across `Features/Migration/` (41 files), `Dependencies/MigrationManager/` (7), `Models/Migration/` (10), plus a brand-new `UserNotifications` dependency client the app never had.

Waiting doesn't help, for three reasons:

1. **The expensive part is already on `main` today.** The SDK jump is orthogonal to the migration and costs the same whether we do it now or in a month.
2. **The migration was still moving** at audit time and remains off upstream main. Current fetched branch counts are recorded above; the historical tag-relative counts and stacked `pacu/*` branches below explain why it was deferred.
3. **The delta was already large before the ports.** The pre-port audit measured 105 upstream-main commits; the parity work is now landed, but the migration branch itself remains a much larger moving delta.

And when it does land, it's cheaper than the line count implies: roughly two-thirds are brand-new files (142 of 208, carrying 80% of the inserted lines). It's also gated behind a compile-time `FeatureFlags.migration` that ships **testnet-only** — so we can merge the whole subsystem dark and enable it on our own schedule.

> ⚠️ **Two corrections here, both measured 2026-08-10.**
>
> - **The overlap is 51 files, not 36.** Under this document's own definition — the tag's 208 files intersected with the 680 files our fork changed since BASE — the count was 29 at `60ca5dde` and exactly 36 at `c8c3e942` (which is why "29 … the five ports added seven" checked out), but PR #33 raised it to 47 and PR #34 to 51. PR #35 changed one additional non-overlap source file and PR #36 added this non-overlap document, so the overlap held. Under the alternative reading (files currently differing between the Zapp app-source snapshot and `upstream/main`) it is 42. The contended surface includes `RootStore.swift`, `RootCoordinator.swift`, `RootInitialization.swift`, `RootTransactions.swift`, `SmartBannerStore.swift`, `Localizable.xcstrings`, `project.pbxproj`, `SendConfirmationStore.swift`, `ZashiSheet.swift` and `FeatureFlags.swift`.
> - **"`SmartBannerStore.swift` and `SDKSynchronizerInterface/Live.swift` are files we have never touched" is wrong** — all three have commits on `origin/main` since BASE, and the claim contradicts §4.3, which lists `SmartBannerStore` among the Ironwood rewrite sites. The *consequence* survives for two of the three: `SDKSynchronizerLive.swift` is now byte-identical to upstream and `SDKSynchronizerInterface.swift` differs by one trailing blank line, because our edits were **convergence onto upstream's own** `prepareWith → Initializer.InitializationResult` change — so the migration branch's hunks would indeed port clean there. Only **`SmartBannerStore.swift` is genuinely contended** (+32/−6 since BASE; 12/12 vs upstream today; +812/−91 on the migration tag). Treat it as a high-density conflict, not a clean port.

Two things worth pre-paying now, while the tree is open, because they cost almost nothing extra and are dramatically cheaper outside a 42k-line merge:

- The migration branch changes `ZashiSheetModifier.sheetContent` from `SheetContent` to `() -> SheetContent` and wraps the body in `WithPerceptionTracking`. We have **49** `.zashiSheet(` call sites (vs upstream's 43; the migration tag has 55), including two fork-only files — `OfframpView.swift` ×2 and `ZappUnifiedSendView.swift` ×6. Land it as its own commit.
- Reconcile `RootStore.Path` / `RootCoordinator` so our chat/offramp cases sit in a stable order — reduces the density of the later conflict. **More valuable now, not less.** *(Correction: the claim that `RootCoordinator.swift` "stayed at its fork-point divergence" is wrong — the parity ports added +109/−15 to it, and its conflict count doubled from 6 to 12. The two files' densities have converged, not drifted apart; both are now top-three conflicts.)* Our `Path` enum still interleaves fork-only cases with upstream's, and `offramp` sits out of alphabetical order immediately before `currencyConversionSetup` — exactly where the migration tag inserts `migrationCoordFlow`.

### Historical branch notes

| Branch | State | What |
|---|---|---|
| `upstream/fix/stuck-sending-tx` | 3 ahead / 10 behind | MOB-1581 hardening — transactions stuck at "Sending…". **Ported/adapted in PR #35** with a 310-line focused five-test suite. |
| `upstream/kris/behavior-based-migration-gate` | 233 ahead | Where the migration is actually headed. Note `ddb62c62` "Take the transaction guard in the migration-broadcast shim" — migration broadcasts join the `transactionGuard` FIFO mutex. |
| `upstream/michal/orchard-spend-warning-sheet` | 5 ahead / 10 behind | **Superseded** — the tag ships a more precise proposal-driven version. Ignore. |
| `upstream/r12/send-priority-wip` | 130 ahead | Commit subject literally says *"PARKED, do not merge without danny's pacing review"*. Ignore. |
| `upstream/michal/MOB-1580-…-superseded` | 5 ahead | Branch name says superseded; final commit reverts its own core filter. Abandoned. |
| `upstream/pacu/MOB-1666 · 1668 · 1670 · 1671` | +13…+16 on the migration tag | Migration-UI polish (split-balance layout/spacing and row icon, Keystone logo background, Migration-complete padding). They land *inside* the 42k-line merge, not before it — evidence for reason 2 above, not new work. `pacu/dependabot-json-2.21.2` is a lockfile security bump, relevant to §4.4's `2c72d041` row. |

### Historical proposed order — completed by PRs #33 and #34; post-parity hardening in PR #35

> The core parity portions of all 17 steps below are discharged. They are retained because later sections cross-reference their original ordinal and because the order explains which safety invariants were coupled. Release housekeeping and the still-live hardening items are promoted to the current sequence above.

*Step numbers are kept stable — later steps cross-reference them by ordinal.*

**Phase 0 — cheap unblocking, no behaviour change** — ✅ **DONE**
1. ✅ `06c07757` — catalogue re-serialised into Xcode's format, standalone and code-free. **Residuals:** the trailing newline reintroduced by step 4, and the `CLAUDE.md` rule still unwritten (§4.5).

**Phase 1 — funds safety, *without* waiting for the SDK** — ✅ **DONE**

None of these needed the SDK bump. That was the key sequencing finding, and it held: all four landed on the `2.6.0-alpha.6` pin, which is untouched.

2. ✅ `ce9b8c4c` — `#1943` single-flight init.
3. ✅ `e2dab641` — `PRO-325`. **Residuals:** it unhangs the offramp poll loop for provider `FAILED` only — `EXPIRED`, a stuck `PROCESSING` and any unmapped status still poll unbounded (`Near1Click.swift:240`, `OfframpNearBridge.swift:354/367`). **`OfframpNearBridge.poll` is still unverified end-to-end**: zero tests reference it, we are its only caller, upstream never exercises it.
4. ✅ `9556aa6b` — `MOB-1512` in probe-only form, with the `clearDeviceScopedWalletState` extraction (our PIN-lockout reset survived), the deferred-alert trio, and the `initializeSDKFinished`-before-`checkWalletInitialization` line. **Residuals:** three dropped upstream assertions including the voting-override clear; the offramp leg and the entire delete path untested; the view-only refusal has no user-facing copy; alert presentation unverified by hand; the `store.path` axis unchecked (§4.1, §4.1.2).
5. ✅ `4a773dfc` — `MOB-1510` firmware gate plus our fork-only fifth signing surface. **Residuals:** the Voting signing path is still ungated and is now the only one (§4.1); the deferred `markSwapTransaction` re-derives its address differently from its sibling, and no test asserts the address (§6.2).

**Phase 2 — the SDK bump** — ✅ **DONE**
6. ✅ Bumped the pin to `2.8.0-rc.1`; changed `prepareWith` to return `Initializer.InitializationResult` across Interface/Live/Test and completed the compile sweep.
7. ✅ Completed MOB-1512 with the `.seedNotRelevant` arm and `998ca6e8`'s `initializerSeedMismatch` remap; focused tests prove the heal remains reachable (§4.1.1 standing rule).

**Phase 3 — correctness** — ✅ **DONE**
8. ✅ Keystone account-switch history landed as one final-state unit with fork teardown preserved.
9. ✅ `MOB-1581` send-completion refresh landed after the provenance guard; PR #35 added event-filtering, foreground resubscription and pending-transaction reconciliation hardening.
10. ✅ `#1920` Keystone import failure handling landed.
11. ✅ All of `#1948`, including `isDifferentError` and the live `ZappSyncErrorSheet` rewrite, landed.

**Phase 4 — Ironwood** — ✅ **DONE**
12. ✅ Pool accounting, `AccountBalanceExtensions.swift`, fork `OfframpNearBridge`, and focused assertions landed.
13. ✅ `MOB-1593` exact-empty memo filter landed.
14. ✅ `MOB-1535` store and live Zapp UI landed.
15. ✅ Ironwood announcement, persistence, gate, debug reset, and Zapp rebrand landed.

**Phase 5 — housekeeping** — ✅ **CORE DONE; RELEASE FOLLOW-UP REMAINS**
16. ✅ MOB-1475, LICENSE, `CLAUDE.md`, the `TransactionStateTests.swift` landmine guard, and §7 conventions landed. `d7121bec`, Zapp What's New, and the release-doc/tooling items moved to the current sequence above. *(MOB-140 remains a deliberate skip.)*
17. ✅ Voting was compiled out behind undefined `VOTING_ENABLED`, with all fork clears audited.

---

## 9. Cross-platform signal — what ZODL *Android* is shipping ahead of iOS

*(New section, 2026-08-10. This document had no cross-platform content at all; `grep -ci android` returned 2 incidental hits.)*

**Scope note first, because the repo names are confusable.** Four sibling checkouts matter and only one is this document's parity target:

| Checkout | Remote | Role |
|---|---|---|
| `~/dev/zapp/zodl-ios` | `zodl-inc/zodl-ios` | **The upstream this document audits.** Byte-parity target. |
| `~/dev/zapp/zodl-android-real` | `zodl-inc/zodl-android` | ZODL **Android** upstream. Different codebase — byte-parity is not meaningful. |
| `~/dev/zapp/zapp-android` | `JustZappIt/zapp-android` | *Our* Android fork. Target of `docs/ANDROID_PARITY_*.md` (UX parity, a separate track). |
| `~/dev/zapp/ios-zapp` | `JustZappIt/ios-zapp` | This repo. |

**Why Android is worth watching.** ZODL Android has shipped **3.9.0 and 3.9.1** and merged `maint/v3.9.x` into `main` (`66e6bc87a`, 2026-08-10) — 342 files, +29,984/−1,877 — while iOS upstream `main` is still on **3.8.1**. Android is running roughly a release ahead, so its merged work is a preview of what iOS upstream will land next. Nothing here is an iOS *parity gap* (upstream iOS doesn't have it either), so none of it changes §1's "parity through 3.8.1 complete" verdict. Treat this as a roadmap input.

**The one item worth acting on independently:**

- **1Click echoes rewritten swap asset IDs; iOS matches them with `==`.** Android established (PR #2352) that the NEAR 1Click API rewrites asset IDs for routing — `nep141:btc.omft.near` → `1cs_v1:btc:native:coin` — and echoes the **rewritten** value back in `quoteRequest`, so any lookup keyed on the raw `assetId` misses. They fixed it twice: `594789e2d` dropped the strict `destinationAsset` equality check that failed every ZEC→BTC quote, and `930776db4` added `findAssetByEchoedId` (exact match, then a ticker fallback parsing `1cs_v1:<ticker>:…`). iOS's `Near1Click.swift` passes the echoed strings through verbatim and five consumers then match with `==`: `RootSwaps.swift:112/119`, `TransactionDetailsStore.swift:492/499`, and the computed `swapFromAsset`/`swapToAsset` (`:669/:685`) and `totalSwapToZecFeeAssetName` (`:715`). The iOS symptom is **silent** rather than an exception — the `if let … .first` / `guard let` sites simply no-op — so for a rewritten asset, Transaction Details shows no token symbol, no chain and no fee asset name.
  **Caveat, stated plainly:** the mapper is upstream iOS's, so this half is *shared with upstream*, not fork drift. The fork-specific half is `OfframpNearBridge`'s two strict `destinationAssetId` guards, which fail closed and which upstream cannot fix for us (cross-reference §6.1). Confirm the rewrite actually occurs for our curated asset set before spending effort.

**Checked and deliberately *not* carried over** (each verified as *not* an iOS fork gap — upstream iOS is byte-identical to us on all three):

- **ZIP-318 Orchard→Ironwood migration** — Android shipped it in production 3.9.0/3.9.1 (170 migration files). iOS upstream has **zero** migration implementation on `main`; it lives only on the unmerged `migration/*` stack (§8 step 8). Our tree is at exact iOS parity.
- **Orchard-spend privacy warning** — Android decoupled it from migration in 3.9.0. `git grep -i 'orchardWarning|spendsLegacyOrchardFunds' upstream/main` → zero hits, same as ours. The migration tag ships a more precise proposal-driven version, which is why §8's branch table says to ignore `michal/orchard-spend-warning-sheet`.
- **`.onion` / `grpc://` custom-server endpoints** (`secure: true` hardcoded, Android fix `8f64f3757`) — `upstream/main:UserPreferencesStorage.swift` has the *identical* two `secure: true,` lines we do, and neither repo has any `onion` handling. Shared upstream behaviour, not drift; and the Android fix is not even on Android `main` yet.
- **MOB-1664 balance retention across synchronizer swaps** — the claimed SDK mechanism does not reproduce on iOS: `switchTo()` never enters `.unprepared`, so `SynchronizerState.zero` is never emitted on a server switch, and iOS `accountsBalances` is a persisted-DB read rather than per-instance in-memory state. The Android bug shape does not translate.

---

## Appendix A — the 26 formerly missing string keys — resolved

**Post-merge status: 26/26 landed in PR #34.** The catalogue now contains 1,673 keys, the app-name copy is adapted to Zapp, the two fragment-boundary spaces are preserved, Spanish coverage is present as designed, and the file ends at `}` with no newline. The table below is the historical transplant checklist, not missing work.

Pre-port key-set diff: upstream 1,138 keys · ours 1,647 · missing from us 26 · new-key intersection 5. Post-merge: ours **1,673**, and the missing set is empty.

| Group | Keys |
|---|---|
| Ironwood announcement (10) | `ironwoodAnnouncement.{title, body1, body2, body3, guidePrefix, guideLink, guideSuffix, learnMore, continue, debugReset}` |
| Pool balances (8) | `poolBalances.{title, desc, totalBalance, ironwood, orchard, sapling, transparent, gotIt}` |
| Keystone connection failure (3) | `keystone.addHWWallet.{failureTitle, failureDesc, contactSupport}` |
| Sync diagnostics (5) | `sync.message.error.{incompatibleServer, server, branchId, code}`, `smartBanner.help.syncError.incompatibleServer.title` |

*Landed and removed from this list: `keystone.firmwareUpdate.{title, body, legacyBody}` (`4a773dfc`, byte-identical to upstream incl. the Spanish `needs_review` state) and `root.initialization.alert.staleWalletDatabaseHealed.{title, message}` (`9556aa6b`). The rebrand pass was applied correctly: `…staleWalletDatabaseHealed.message` is the only one of the five that differs from upstream, and only by saying "Zapp" where upstream says "ZODL", in both languages.*

All 26 have Spanish except `ironwoodAnnouncement.debugReset` (English only, debug builds only).

**The two app-naming keys received the required rebrand pass** — `ironwoodAnnouncement.continue` and `sync.message.error.incompatibleServer` use Zapp copy, and the adapted copy test pins Zapp rather than Zodl.

`CLAUDE.md` was corrected in the same PR, so future string work no longer receives the stale "always ZODL" instruction.

**Two carry load-bearing whitespace:** `ironwoodAnnouncement.guidePrefix` ends with a space, `guideSuffix` begins with one. The three guide fragments are split deliberately so the link range is known by construction rather than found by searching rendered text — keep them split.

Reproduce with:
```sh
git show upstream/main:secant/Resources/Localizable.xcstrings > /tmp/up.xcstrings
git show origin/main:secant/Resources/Localizable.xcstrings   > /tmp/ours.xcstrings   # NOT the working tree
python3 -c "
import json
up=json.load(open('/tmp/up.xcstrings'))['strings']
ours=json.load(open('/tmp/ours.xcstrings'))['strings']
for k in sorted(set(up)-set(ours)): print(k)
"
```

---

## Appendix B — upstream's 19 new test files — all ported/adapted

**Post-merge status: complete, with PR #35 adjunct coverage.** The original five port suites plus all fourteen later new files are present, along with the relevant modified-test coverage. Root suites retain their plain `Store` + `LockIsolated` shape where upstream intentionally avoided exhaustive `TestStore`, and shared-state suites pin fresh in-memory storage. PR #35 added `RootPendingTransactionRefreshTests.swift` (310 lines, 5 tests) for event filtering, polling and lifecycle behavior, and expanded `SmartBannerIncompatibleServerTests.swift` to 164 lines / 9 tests with the recurring-error re-arm case. The historical inventory below explains what each upstream file protects.

**Historical first tranche:** five files initially landed with the early ports and collided by filename with upstream's (§5.4). PR #34 reconciled and extended that coverage, including both SDK mismatch signals and the unified-send address assertions. The old pre-merge line/hunk counts are intentionally omitted because they are no longer useful navigation data.

`project.pbxproj` wiring: confirmed unnecessary — the five landed with a zero-line pbxproj diff.

**Ported in PR #34: 14 new files, plus one modified file called out separately:**

> ⚠️ **The `LOC` column below is `upstream/main`'s line count, not ours.** Every number in it equals upstream's file size exactly, so the column cannot be used to check what actually landed here. All 19 upstream-added test files *are* present in our tree, but sizes differ substantially in both directions — ours vs the table: `RootIronwoodAnnouncementGateTests` **228**/456, `IronwoodAnnouncementCopyTests` **53**/109, `IronwoodAnnouncementTests` **42**/96, `AdvancedSettingsDebugResetTests` **19**/39, `ZcashSDKEnvironmentActivationHeightTests` **19**/28, `IncompatibleServerDiagnosticsTests` **156**/186, `RestoreWalletAnnouncementFlagTests` **58**/72, `SecItemClientTests` **+48**/+84; and going the other way `RootTransactionsAccountSwitchTests` **696**/657, `RootSendCompletionRefreshTests` **492**/440, `SmartBannerIncompatibleServerTests` **164**/132, `TransactionDetailsMemosTests` **48**/38. Most of the shortfall is comment-header stripping and test consolidation, not lost behaviour — `RootIronwoodAnnouncementGateTests` folds upstream's 16 cases into 11 by looping the six safety-gate terms. **One assertion is genuinely dropped:** upstream's `activation + 1` tip-boundary case (`#expect(presented(forTip: activation + 1))`). Prefer `@Test`-count parity over LOC when checking this table.

| File | LOC *(upstream's)* | Locks in |
|---|---:|---|
| `RootTransactionsTests/RootTransactionsAccountSwitchTests.swift` | 657 | Account-switch provenance, cancellation, starvation |
| `UtilTests/RootIronwoodAnnouncementGateTests.swift` | 456 | The four ordered gate guards + debug reset |
| `RootTransactionsTests/RootSendCompletionRefreshTests.swift` | 440 | MOB-1581 across all four send flows |
| `AddKeystoneHWWalletTests/AddKeystoneHWWalletCoordFlowTests.swift` | 197 | #1920 failure sheet / support routing |
| `ModelsTests/TransactionStateTests.swift` | 191 | Self-transfer `netValue` — explicitly guards *against* reintroducing `4d7fdeee` |
| `UtilTests/IncompatibleServerDiagnosticsTests.swift` | 186 | `isIncompatibleServer`, `hexDescription`, message assembly |
| `SmartBannerTests/SmartBannerIncompatibleServerTests.swift` | 132 | #1948 sheet + Switch-server gating |
| `IronwoodAnnouncementTests/IronwoodAnnouncementCopyTests.swift` | 109 | The user-facing keys; **pins `"Go to Zapp"` exactly** |
| `IronwoodAnnouncementTests/IronwoodAnnouncementTests.swift` | 96 | Learn-more ≠ acknowledgement; Continue persists once |
| `UtilTests/SecItemClientTests.swift` | +84 | Keychain duplicate-add → update |
| `RestoreWalletTests/RestoreWalletAnnouncementFlagTests.swift` | 72 | Neither create nor restore may touch the flag; both sends still need `.finish()` containment |
| `SettingsTests/AdvancedSettingsDebugResetTests.swift` | 39 | Debug reset bypasses `operationAccessCheck` |
| `TransactionDetailsTests/TransactionDetailsMemosTests.swift` | 38 | MOB-1593 empty-memo filter |
| `UtilTests/ZcashSDKEnvironmentActivationHeightTests.swift` | 28 | Activation heights per network |
| `AddKeystoneHWWalletTests/ZcashAccountsTestFixture.swift` | 24 | **Reusable fixture** — worth taking on its own |

Plus 14 modified test files (~570 lines) — the `SecItemClientTests.swift` row above is one of them, listed separately because it is worth taking on its own. Another, `SwapTests/Near1ClickTests.swift`, both sides have now edited (we added +35 lines of PRO-325 status-mapping cases), so it needs reconciling against upstream's `92320ace` rather than dropping in.

> **`extension Root.State: @retroactive Equatable` lives in `RootInitializeSDKSingleFlightTests.swift:18`** — *not* in the heal file, where upstream puts it. It is target-wide and compares 7 fields (upstream's 6 plus our `isInitializingSDK`), because `Root.State` embeds non-Equatable CoordFlow states yet `TestStore` requires a conformance. It is deliberately confined to the test target so no `@ObservableState`/SwiftUI diffing path in the shipping app picks up a conformance that treats most fields as equal. **Consequence for the merge:** anyone taking upstream's heal suite on top of ours gets a *duplicate*-conformance build error, not a missing one — and any future Root `TestStore` suite must reuse this one and widen its `==` rather than declare its own.

> **Dependency-stub conclusion:** the fan-out cost was over-estimated. `\.zappMessaging`, `\.chatContacts` and `\.chatPushNotifications` have inert test defaults; only `\.offramp` needs explicit stubbing when a path reaches the heal. File-local helpers remain intentional and no longer represent outstanding port work.
>
> **Root suite shape retained:** `RootTransactionsAccountSwitchTests` and `RootSendCompletionRefreshTests` are not `TestStore` suites: upstream drives both with a plain `Store` plus `LockIsolated` spies and deterministic signaling, deliberately ("Root's init effects are too heavy for exhaustive `TestStore` assertion"), each with its own file-local no-op dependencies. Do not convert them or widen the shared `Root.State` equality for them.
>
> **Probe-only status after PR #34.** Both mismatch scenarios and the voting-override assertion landed. Flexa/preferences/offramp calls are still recorded without ordering assertions, and delete-path plus deferred-alert presentation coverage remain hardening work in §8. The voting override reset remains unconditional in the fork while Voting-specific storage sweeps are guarded.

---

## Appendix C — verified non-gaps

Things that look like gaps and are not. Recorded so nobody chases them twice.

- **MOB-1472 curated swap assets** — already ours, 7 byte-identical cherry-picks (`git patch-id --stable` confirms every pair). 29 curated NEAR asset IDs, 13 chains, `zec` excluded from the address-book picker.
- **`d3eff5b1`** (curated-assets test fixup) — we hit and fixed the same staleness independently in `6d39e324`. Do **not** cherry-pick; it will conflict. One comment-string differs (`// USDC@pol` vs `// pol.usdc`) — optional to align.
- **MOB-1580 / `8a822be7`** — the net delta on `TransactionState.swift` across the whole range is a cosmetic ternary→`if/return` refactor of `netValue`. Our version is already semantically identical to upstream's end state.
- **`7ae2d93a` / `2acef3c0`** (`.regtest`) — `URIParserInterface.swift` is net-unchanged and already byte-identical to `upstream/main`. It is the only net-zero file in the range.
- **`4d7fdeee`** note-count fallback — reverted. Do not port. The 191-line `zodlTests/ModelsTests/TransactionStateTests.swift` is now landed and exists specifically to fail if anyone reintroduces the fallback.
- **MOB-140** — see §4.4. Our Receive rewrite deleted the code both hunks patch.
- **Upstream deletions** — none. `git diff --diff-filter=D` and `--diff-filter=R` come back empty, and `--summary` shows only `create mode` lines — no deletes, renames or mode changes.
- **`fastlane/`, `.github/`, `Scripts/`, `xctemplates/`, entitlements, Info.plists, `.swiftlint*.yml`, and every root doc except `CLAUDE.md`, `LICENSE` and `CHANGELOG.md`** — upstream changed none of them since the fork point, so there is nothing to port and nothing can conflict. ⚠️ **`CHANGELOG.md` is a third exception the original wording omitted:** upstream added 31 lines to it, we added 130/−1, and a dry-run merge already produces one conflict hunk there — guaranteed to grow, since both sides append under `## [Unreleased]`. The directory half of this claim (0 upstream changes under those paths) does reproduce exactly. *(Correction to the first draft: our copies are **not** all byte-identical — we have diverged on the CI workflows and bootstrap action, four `Scripts/`, six `fastlane/` files, every `Info.plist` and every `.entitlements`, for the rebrand and the ZappMessaging bootstrap. `xctemplates/`, `Rakefile`, `.swiftlint*.yml` and the remaining root docs are byte-identical.)*
- **`Near1Click.swift` status mapping** — after `e2dab641`, a full-file diff against `upstream/main` is exactly three hunks, all inside the `quote:` closure (the offramp's `quoteRequest` / address / echoed-asset binds). The `status:` closure and the `swapStatus(from:isSwapToZec:)` helper are character-for-character upstream's, so that area will not conflict on a future sync.
- **`upstream/agent/fix-main-e2e` SDK/CI experiment** — no gap. Its earlier remote-pin commit confirmed Zapp's PR #33 package choice, but the branch now uses an exact Slipstream checkout, locally built matching FFI and package-resolution retries. Do not replay that moving CI shape over Zapp's clean-clone-safe remote package setup.
- **`upstream/chp-re-enable`** — not a parity gap yet. Its sole CHP-specific commit adds a planning document and deliberately changes no code; the inherited 44k-line delta is the unmerged migration program. Treat it as an upstream direction signal, not a port source.
- **Inherited `docs/` files** — every shared file is identical between the two repos except `release-automation.md`, which we forked deliberately. This parity audit is Zapp-owned and has no upstream counterpart.
- **The TransactionGuard / AutoServerSelection architecture** documented in our `CLAUDE.md` is **upstream's**, present at the merge base and still on `upstream/main`. We inherited it; it is not a fork invention, and nothing in this port fights it.

---

## Appendix D — reproducing this audit

```sh
cd ~/dev/zapp/ios-zapp
git fetch upstream --prune && git fetch origin --prune
BASE=$(git merge-base origin/main upstream/main)

git log  --no-merges --format='%h %ad %s' --date=short $BASE..upstream/main
git diff --name-only $BASE upstream/main
comm -12 <(git diff --name-only $BASE upstream/main | sort) \
         <(git diff --name-only $BASE origin/main   | sort)   # the both-sides files — 147 today, not 63

git show upstream/main:<path>                         # upstream's version of a file
git show origin/main:<path>                           # OURS — not the working tree
git grep -n '<pattern>' origin/main -- secant zodlTests
git diff $BASE..origin/main -- <path>                 # what WE changed there
git merge-tree --write-tree origin/main upstream/main # dry-run the whole merge

# conflict hunks in one file, without touching the working tree.
# NOTE: brace the variable. Unbraced, zsh parses ":s..." as a history substitute
# modifier, hands git a mangled argument, and this silently prints 0.
TREE=$(git merge-tree --write-tree origin/main upstream/main | head -1)
git show "${TREE}:secant/Sources/Features/Root/RootStore.swift" | grep -c '^<<<<<<<'   # 17

# every conflicted path (stop at the blank line — informational messages follow it):
git merge-tree --write-tree --name-only origin/main upstream/main \
  | awk 'NR==1{next} /^$/{exit} {print}' | sort -u | wc -l                             # 57
```

**Use `origin/main`, never the checked-out branch.** Every claim in this document was re-verified that way; a stale local `main` is what made the first draft report five completed items as missing.

Upstream checkout for full-file reading: `~/dev/zapp/zodl-ios` (kept at `upstream/main`).
