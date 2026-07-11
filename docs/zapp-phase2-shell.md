# Zapp iOS — Phase 2: Tabs shell + wallet UX rewire

Branch: `feature/zapp-phase2-shell` (on top of Phase 1 `feature/zapp-phase1-rebrand`).
Spec: the Zapp Android fork (`android-zapp`), primarily
`ui-lib/.../screen/tabs/` and `ui-design-lib/.../component/zapp/`. This phase
replicates the navigation shell and non-chat wallet UX; messaging/chat,
chat-contacts, offramp, and notifications are deferred (Phase 3+).

## Tab set and mapping to Android

| Android (`ZappTab`) | iOS (`ZappTab`) | Content |
|---|---|---|
| `PAY` ("Pay") | `.pay` ("Pay") | `WalletTabView` over the upstream `Home` feature |
| `CHATS` ("Chats") | — deferred | Seam below |
| `YOU` ("You") | `.you` ("You") | `YouTabView` over the upstream `Settings` feature |

Notes:
- Android's tab title string is literally "Pay" (`home_pay_title`); iOS matches.
  (The task brief mentions a "Pay" → "Wallet" rename; the current Android fork
  renders "Pay", and Android is the literal spec, so iOS says "Pay".)
- Android boots into CHATS by default; without a Chats tab, iOS defaults to `.pay`.
- Tab selection is view-local state on both platforms (Android `rememberSaveable`,
  iOS `@State`); no reducer owns it.

### Chats/Contacts seam

- `ZappTab` (in `ZappTabsView.swift`) is a `CaseIterable` enum: adding `.chats`
  inserts the tab into the pill automatically. The pill's unread-badge slot
  (Android `chatUnreadCount`) was intentionally not stubbed; it arrives with
  the messaging bootstrap.
- Android's `ZappTabsScaffold` also owns the welcome-gate / onboarding / restore
  state machine (`WelcomeGateVM`); on iOS those remain Root destinations
  (`.welcome` / `.onboarding`), which is the TCA-idiomatic equivalent. When
  messaging onboarding lands, that state machine extends `RestoreWalletCoordFlow`
  and the Root destination switch, not the tabs scaffold.

## New fork files

| File | Android source |
|---|---|
| `UIComponents/Zapp/ZappDesign.swift` | `ZappTheme.colors` token table, `ZappNavBar`, `ZappMotion` |
| `UIComponents/Zapp/ZappComponents.swift` | `ZappScreenHeader`, `ZappSectionLabel`, `ZappStatusChip`, `ZappRow(+Divider)`, `ZappSegmentedSelector`, `ZappFab` |
| `UIComponents/Zapp/ZappSpeedDialFab.swift` | `ZappSpeedDialFab` |
| `UIComponents/Zapp/ZappSparkChart.swift` | `SparkChart` |
| `Features/Tabs/ZappTabsView.swift` | `ZappTabsScaffold`, `FloatingPillNavBar`, `ZappTab` |
| `Features/Tabs/WalletTabView.swift` | `WalletTabContent`, `WalletHomeView`, `WalletBalanceCard`, `WalletSyncStatusViews`, `PayActionSpeedDial` |
| `Features/Tabs/YouTabView.swift` | `SettingsTabContent` |
| `Features/Tabs/BalanceHistory.swift` | `GetBalanceHistoryUseCase`, `BalanceChartVM` windowing, `BalanceChartPeriod` |

Token notes: `c.navPill`/`c.chipBg`/`c.surface` have no exact Phase 1 colorset;
they resolve to the documented nearest ramp steps (Gray100/Shark900,
Gray100/SharkShades06dp, Bone/SharkShades01dp) in `ZappDesign.swift`.

## Upstream files touched (sync-review list)

| File | Change |
|---|---|
| `Features/Root/RootView.swift` | `.home` renders `ZappTabsView` instead of `NavigationStack{HomeView}`; `.onboarding` gains the create-path seed reveal branch. Everything else (path overlays, popovers, splash, alerts) untouched. |
| `Features/Root/RootStore.swift` | Added `isOnboardingSeedRevealShown` state; `isSensitiveFlowActive` additionally gates on `settingsState.votingCoordFlow != nil` (see below). |
| `Features/Root/RootInitialization.swift` | `.onboarding(.newWalletSuccessfulyCreated)` now routes to the seed reveal instead of straight to `.home`; `.phraseDisplay(.finishedTapped/.seedSavedTapped/.remindMeLaterTapped)` land at `.home`. |
| `Resources/Localizable.xcstrings` | 24 new `zapp.*` keys (en + es). No existing keys changed. |
| `Features/SmartBanner/SmartBannerView.swift` | Chrome only: purple gradient panel -> flat obsidian (`ZDesign.Base.obsidian`). |
| `Features/SmartBanner/SmartBannerContent.swift` | Chrome only: banner text colors -> bone / shark400 (dark-mode text ramp). |
| `CHANGELOG.md` | Entry under Unreleased. |

**Auto-server-switch gate fix (behavioral, not cosmetic):** upstream classified
`path == .settings` as sensitive because the voting flow presents from inside
Settings. With Settings mounted as the You tab, voting can run while
`path == nil`, so `isSensitiveFlowActive` now also checks
`settingsState.votingCoordFlow != nil`. Without this, an automatic server
switch could interrupt a voting broadcast.

**No-longer-mounted upstream views** (kept in-tree, byte-identical, for merge
friendliness): `HomeView.swift` (+ `GlobalNavBar`, `MoreSheet`,
`SendSelectSheet`, `WalletAccountsSheet`), `SettingsView.swift`,
`WelcomeView` is still mounted (boot splash). `YouTabView` mirrors
`SettingsView`'s destination switch and sheets - when upstream adds a
`Settings.Path` case, mirror it in `YouTabView` (conflict hotspot).

## Behavior decisions where Android has no clean iOS/TCA analog

1. **SmartBanner kept on the Wallet tab (deviation from Android).** Android has
   no banner; its fork moved those concerns elsewhere. On iOS the smart banner
   is the only entry point for wallet-backup reminders, shielding, sync-error
   reporting, and currency/Tor setup, and its reducer drives the priority
   pipeline. Removing it would orphan those flows. It renders between the
   balance card and the activity list. Revisit when Phase 3 relocates those
   flows.
2. **Wallet-state gating.** Android gates the Pay tab on
   `SecretState` (LOADING spinner / NONE empty-state / READY home) because its
   shell can boot without a wallet. On iOS a wallet always exists before the
   `.home` destination shows (onboarding completes first), so the gating maps
   to: `migratingDatabase` -> centered accent spinner, else home. The Android
   in-tab create/restore empty state arrives with the messaging-first
   onboarding (Phase 3), where the tabs shell becomes reachable pre-wallet.
3. **Speed dial action set.** Android currently ships Pay Merchant / Send /
   Swap / Receive. Per the phase brief, iOS ships Send / Receive / Scan / Swap
   and leaves the offramp (Pay Merchant) slot for Phase 3 - the action array in
   `WalletTabView` takes one more entry, no restructuring.
4. **Balance breakdown / shield button.** Android renders shielded/transparent
   breakdown + Shield inside the balance card. On iOS shielding is owned by the
   SmartBanner/shieldingProcessor pipeline (kept, see 1); duplicating the
   button risks double-broadcast paths. Deferred with the banner relocation.
5. **Account switcher / Keystone.** The upstream Home nav-bar account switcher
   is not part of the Android shell and is not mounted. Keystone flows remain
   reachable (add/select via Settings paths); switching the *active* account
   has no Zapp-shell surface yet - flagged for Phase 3.
6. **Onboarding seed reveal (create path).** Android reveals the seed during
   onboarding (WALLET_SEED). Upstream iOS went straight to home. Now
   `.onboarding(.newWalletSuccessfulyCreated)` presents
   `RecoveryPhraseDisplay` (wallet-backup button set: "I wrote it down" /
   "Remind me later"; reveal is auth-gated) and both buttons land at home. The
   backup-reminder banner stays active until the real backup flow completes,
   matching upstream semantics.
7. **Restore -> home.** Android hit a "restore doesn't mark onboarding
   complete" bug. iOS is structurally immune: there is no onboarding-complete
   flag - destination routing derives from keychain/db state each boot
   (`walletInitializationState`), and the restore path
   (`restoreInfo(.gotItTapped)` -> `initializeSDK(.restoreWallet)` ->
   `checkBackupPhraseValidation` -> `.home`) lands at home in-session.
   Verified in code; smoke-test item below.
8. **System back.** iOS equivalents are native: swipe-back inside the
   You tab's NavigationStack and the coord flows' StackState; the tabs shell
   itself has no back (matches Android where tabs are lateral).
9. **Bottom-bar idioms.** Back-bottom-left and the chrome-free lone-back dock
   apply to flow screens (send/receive/scan), which keep their upstream chrome
   this phase - restyling every flow's dock is Phase 3 scope with offramp. The
   floating pill respects the safe-area inset and floats 12pt above it
   (Android: insets + 12dp margin before background/border).

## Balance-history chart

iOS analog of `GetBalanceHistoryUseCase`: `BalanceHistory.build` folds the
shared `transactions` state (already maintained by Root's transaction observer)
into a running signed-delta series - settled receives add, settled sends
subtract, pending/failed/shielding contribute zero. `BalanceHistory.window`
mirrors the Android period windowing: baseline carry-in at the cutoff, series
extended to now, minimum 2 points to render. Periods: 24h / 1w / 1m / All
(default 1w). Chart renders via `ZappSparkChart` (Canvas port of Android's
`SparkChart`: auto-scaled line + vertical gradient fill, no axes). The hero
balance is fiat-first with tap-to-toggle to ZEC-first, sensitive-content
hiding preserved via `ZatoshiText`.

## Audit vs Android (full shell UI, 2026-07-11)

Element-by-element pass over every Android shell file after the first
simulator round. Fixed in this pass:

- `ZappSegmentedSelector` was built to the Receive-tab-switcher spec (accent
  selected cell, 34pt); the actual component spec is bg-colored selected cell
  on a bordered surface, 48pt min height, caption weight. Corrected.
- Header + sync progress row now scroll with the content (Android renders
  them as LazyColumn items); previously pinned.
- Balance card insets now match Android's nesting (18 outer + 20/18 inner).
- Fiat hero now splits whole/fraction (52pt Black text / 26pt Bold muted) per
  Android `formatFiat`, and sources its rate like Android's `zecFiatRate`:
  the user's exchange-rate currency when opted in, else the always-on USD
  price from the swap asset catalog. Root gained
  `ensureSwapAssetsLoaded`/`swapAssetsLoaded` (fired from `.home(.onAppear)`,
  fetch-once) as the `EnsureSwapAssetsLoadedUseCase` analog.
- `ZappBottomActionBar` + `ZappBackButton` ported into the component layer
  (back bottom-left, chrome-free lone-back, insets-and-margin before
  background/border so the bar floats above the home indicator).

Known remaining deltas, with the call made:

| Delta | Call |
|---|---|
| Flow screens (Send/Receive/Scan/Swap steps) still use upstream top-back chrome instead of `ZappBottomActionBar` | Each coord-flow screen is an individual chrome restyle over upstream views with their own toolbars; component is ready, per-screen adoption batched with the Phase 3 offramp flow work. |
| Activity rows render via upstream `TransactionListView` rather than a 1:1 `ActivityRow` port (40pt square icon box, fiat/ZEC value swap tied to the hero toggle) | Keeping the upstream reducer-view pair intact was judged safer than re-implementing row content logic (swap statuses, memos, read state). Visual tokens already match via Phase 1. Revisit if row parity matters before Phase 3. |
| Pill icons do not switch filled/outlined with selection | The iOS asset catalog has single-variant icons; selection is conveyed by the accent cell. |
| You tab groups: People (Address Book) / Wallet / Support vs Android's People / Security / Privacy / P2P / Wallet | Android's Security/Privacy/P2P rows are chat- and offramp-owned (profile, app lock, Tor toggles, read receipts, payment method) and arrive with those phases; iOS keeps Tor/server under Advanced Settings until then, since surfacing them top-level needs new Settings actions in upstream code. |
| Swiss onboarding screens (OnbScreen scaffold, ghost numbers, progress bar, eyebrow) | Phase 1 scoped these out as screen-level patterns; Phase 2 matched onboarding *behavior* (create -> seed reveal -> home, restore -> home, native back). Visual port lands with the messaging-first onboarding (Phase 3), which restructures those steps anyway. |
| Balance breakdown + Shield inside the card | Deferred with the SmartBanner relocation (decision 4 above). |
| `ZappStackedActionBar`, `ZappActionTile`, `ZappEyebrowTopAppBar`, `ZappToggle`, `ZappInputField`, sheets/drag handle | Not used by the Phase 2 shell surface on Android (they serve chat, offramp, and modal flows); port on first use. |

## Side-by-side behavior checklist

| Android shell behavior | iOS implementation | Status |
|---|---|---|
| Persistent bottom pill nav, sharp corners, accent selected cell | `FloatingPillNavBar` in `ZappTabsView` | Done |
| Tab switch = fade-through, not slide | `.opacity` transition, 200ms ease | Done |
| Haptic tick on tab switch | `UIImpactFeedbackGenerator(.light)` | Done |
| Tab set Pay / Chats / You | Pay / You (Chats seam documented) | Done (partial by design) |
| Pill hides under fullscreen sub-screens | Hidden while You tab's stack is non-empty; Root path overlays cover it | Done |
| Wallet tab: header + sync chip | `ZappScreenHeader` + `ZappStatusChip` from SmartBanner sync state | Done |
| Sync progress row under header (3pt bar) | `syncProgressRow` | Done |
| Balance hero: Black 52pt, fiat-first, tap toggles ZEC-first | `balanceHero` | Done |
| Balance delta row (▲/▼ + percent + period) | `balanceDelta` | Done |
| SparkChart + 24h/1w/1m/All chips | `ZappSparkChart` + `ZappSegmentedSelector` | Done |
| Balance history from signed tx deltas, no backend | `BalanceHistory` | Done |
| Recent-activity list, Swiss empty state | `TransactionListView` (upstream reducer) + `activityEmpty` | Done |
| See-all row opens full history | `.home(.seeAllTransactionsTapped)` -> transactionsCoordFlow | Done |
| Speed dial: accent FAB, rotate +, scrim, labelled actions | `ZappSpeedDialFab` | Done |
| Speed dial routes: Send / Receive / Scan / Swap | `.home(.sendTapped/.receiveScreenRequested/.scanTapped/.swapWithNearTapped)` | Done |
| Offramp (Pay Merchant) action | Deferred slot (Phase 3) | Deferred |
| You tab: grouped rows, icon boxes, group headers | `YouTabView` | Done |
| You tab: profile card (chat identity) | Deferred (messaging phase) | Deferred |
| Wallet-state gating: spinner / empty / home | Spinner (migratingDatabase) / home; empty state deferred (see decision 2) | Done (partial by design) |
| Create wallet -> seed reveal -> home | `isOnboardingSeedRevealShown` + `RecoveryPhraseDisplay` | Done |
| Restore -> lands at home, onboarding complete | Upstream routing verified (decision 7) | Done |
| System back through onboarding steps | Native stack back in `RestoreWalletCoordFlow` | Done (upstream) |

## Verification

- `xcodebuild -project secant.xcodeproj -scheme zodl-internal build` (iOS Simulator
  destination): **BUILD SUCCEEDED**, zero errors, with SwiftLint 0.50.3 installed and
  detected by the build phase.
- `swiftlint lint --config .swiftlint.yml` over the new `Features/Tabs/` and
  `UIComponents/Zapp/` files: clean except one `redundant_optional_initialization`
  warning on `@Shared(...) var currencyConversion: CurrencyConversion? = nil` -
  kept deliberately, since `@Shared` requires the explicit default and upstream
  carries the identical warning on the same pattern (RootStore, WalletBalances, ...).
- Simulator walkthrough (iPhone 16 Pro, iOS 18.6, driven via idb; screenshots
  verified in light and dark mode): fresh install -> onboarding -> Create ->
  seed reveal (auth-gated, "I've saved it" / "Remind me later") -> Pay tab;
  relaunch -> Pay tab directly (no re-shown onboarding); sync chip + progress
  row live (Syncing n% -> Synced); speed dial expands over scrim and Send
  routes into the send flow and back; You tab groups render, Advanced Settings
  pushes with the nav pill hidden; tab switch fades with haptic.
- Fixes found during the walkthrough: speed-dial FAB was centered instead of
  bottom-trailing (missing expanding frame); the wallet tab no longer blanks
  behind a spinner on `migratingDatabase` (upstream treats it as a transient
  note, and leftover keychain keys from a previous install can hold that state
  for a long restore); `checkBackupPhraseValidation`'s home routing is gated on
  the seed reveal so background init can't skip it; smart banner recolored from
  upstream purple to the Zapp obsidian panel.
- Manual smoke test (run on simulator):
  1. Fresh install -> onboarding shows; "Create new wallet" -> seed reveal
     (reveal requires auth) -> "I wrote it down" -> lands on Pay tab.
  2. Fresh install -> restore with a valid phrase -> restore info -> "Got it"
     -> lands on Pay tab in Restoring state; kill + relaunch -> Pay tab again
     (no re-shown onboarding).
  3. Pay tab: sync chip cycles Connecting -> Syncing n% -> Synced; progress row
     disappears when synced.
  4. Balance hero: tap toggles fiat/ZEC; period chips switch the chart window;
     chart hidden with zero balance or fewer than 2 settled transactions.
  5. Speed dial: expands over scrim; Send / Receive / Scan / Swap each open the
     right flow full-screen and return on close.
  6. You tab: rows push (pill hides), back returns (pill shows); Advanced ->
     recovery phrase reachable; version footer gestures still work.
  7. Tab switch Pay <-> You: fade, haptic, state retained per session.
