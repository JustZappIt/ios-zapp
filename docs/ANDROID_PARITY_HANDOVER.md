# Android Parity Handover — iOS Zapp

**Author:** Fable 5 (audit) · **Executor:** Opus · **Branch:** `feature/ZAPP-1-android-parity` · **Ticket:** ZAPP-1

This document is the authoritative, phase-by-phase plan to close every identified UX gap between
`ios-zapp` and `android-zapp`. **Android (`../android-zapp`) is the spec.** iOS must match Android's
features, screens, flows, buttons, and visual layout. Where iOS platform conventions differ
(back-swipe, alerts, haptic vocabulary), keep the iOS-native feel — do not transplant Material
ripples or Android dialog styles. iOS-only features (Keystone, Voting, "All settings"/ZODL
surfaces, ZappSmartActionStrip) stay untouched; they are listed in Appendix B.

---

## 1. Execution model (read first)

- **Two agents per phase.**
  1. **Executor** implements the phase exactly as written here.
  2. **Auditor** independently re-reads this document's phase spec, diffs the executor's work
     against it AND against the Android reference files, and fixes/closes any gaps it finds.
- **One commit per phase**, on `feature/ZAPP-1-android-parity`, only after the auditor signs off.
  Commit message format: `[ZAPP-1] Phase N: <title>` (e.g. `[ZAPP-1] Phase 1: Tab shell parity polish`).
  Push after each phase commit.
- **Verify before commit:** the project must build
  (`xcodebuild -project secant.xcodeproj -scheme zodl-internal -destination 'generic/platform=iOS Simulator' build`)
  and, when a phase touches logic with existing tests, `zodlTests` must pass. SwiftLint runs as a
  build phase — zero new violations.
- **Changelog:** every phase adds its user-facing entries to `CHANGELOG.md` under `## [Unreleased]`
  with the `[ZAPP-1]` prefix, in the same commit.
- **Do not** start a later phase before the earlier one is committed, and do not batch phases into
  one commit.

### Repo conventions that bind every phase

- TCA throughout: `@Reducer`, `@ObservableState`, `@Dependency`; feature = `<Name>Store.swift` +
  `<Name>View.swift` (see `secant/Sources/Features/Chats/` for the established Zapp style).
- **Fork discipline:** never edit upstream ZODL views to add Zapp UI — add `Zapp*`/`Chat*` files
  beside them (see the header comment in `Features/ZappTabs/ZappPayView.swift`). Upstream reducers
  may gain actions only when unavoidable.
- All user-facing strings go in `secant/Resources/Localizable.xcstrings` via
  `String(localizable: .someKey)`. Two existing rows in `SettingsTabContent.swift` use
  `String(localized:defaultValue:)` — Phase 1 migrates them.
- Design system only: `ZappColors`/`Design.*` tokens, `Zapp*` UI components
  (`ZappRow`, `ZappButton`, `ZappFab`, `ZappScreenHeader`, `ZappSectionLabel`,
  `ZappSegmentedSelector`, `ZappToggle`-equivalents, `ZappRowDivider`, `ZappStatusChip`), assets via
  `Asset.Assets.*` / colors via asset catalogue. **No SF Symbols, no hex literals.** If a needed
  component/asset does not exist, extend the design system deliberately (new asset in `.xcassets`,
  regenerate via build) — mirror the Android Swiss design: sharp rectangles, no rounded corners.
- New tests use **Swift Testing** (`@Suite`/`@Test`/`#expect`), TCA `TestStore`. Suites touching
  process-global state get `@Suite(.serialized)`.
- Android reference roots (abbreviate below as `A:`):
  `../android-zapp/ui-lib/src/main/java/co/electriccoin/zcash/ui/`
  iOS roots (abbreviate `I:`): `secant/Sources/`.

### Decisions already made by Renee (sign-off scope)

| Topic | Decision |
|---|---|
| Scope | Full app; Android is spec |
| iOS-only features | Leave untouched, listed in Appendix B |
| Platform feel | Match features/layout; keep iOS-native gestures/dialogs; add premium-iOS touches (Appendix C) |
| Doc / branch | This file; `feature/ZAPP-1-android-parity`; one commit per phase |

### Decisions resolved at sign-off (2026-07-25, Renee) — see §3

1. **Push notifications / background delivery: DEFERRED.** No notifications/background-push UI on
   iOS in this branch; the rows stay absent (current deliberate omission stands). The push
   subsystem is a separate ticket. Phase 9 shrinks to a copy/layout check of the read-receipts and
   online-status screens.
2. **Secret-reveal surfaces in chat profile: PORT.** Phase 8 adds Android's seed-phrase and P2P
   private-key reveal dialogs to the iOS profile, **gated behind app-lock authentication**
   (biometric/PIN verify immediately before reveal) and using the existing redaction/hide-on-background
   patterns from `OnboardingSeedBackup` (`hideSensitiveContent`).
3. **Location sharing: OUT OF SCOPE.** No share-location option (Phase 5) and no `LocationBubble`
   (Phase 6); incoming location messages keep the generic fallback rendering.

---

## 2. Phase plan

Phases are ordered so that shared plumbing lands before the features that need it. Small, safe
polish first; big feature builds after.

---

### Phase 1 — Tab shell & You tab parity polish  *(small)*

**Android refs:** `A:screen/tabs/view/FloatingPillNavBar.kt`, `A:screen/tabs/view/SettingsTabContent.kt`
**iOS files:** `I:UIComponents/ZappPillNavBar/ZappPillNavBar.swift`, `I:Features/ZappTabs/ZappTabsStore.swift`,
`I:Features/ZappTabs/SettingsTabContent.swift`, `I:Features/ZappTabs/ZappTabsView.swift`

1. **Unread badge = count, not dot.** Android renders the Chats badge as a count chip: text
   `min(count,99)` with `"99+"` cap, danger background, bold ~10pt, min size 16pt, sharp rectangle,
   offset onto the icon's top-trailing corner; it scales+fades in/out on visibility change.
   Replace the iOS 8pt `Circle()` with a matching rectangle count chip (keep `ZappColors` danger),
   animate appearance with `.transition(.scale.combined(with: .opacity))`.
2. **Tab-switch haptic.** Android fires `SegmentTick` on every tab change. iOS: fire
   `UISelectionFeedbackGenerator().selectionChanged()` in `ZappPillNavBar` when a different tab is
   tapped (or `.sensoryFeedback(.selection, trigger:)` if minimum deployment target allows).
3. **Selected-state icons.** Android swaps outlined→filled per tab on selection. If filled variants
   of `pay` / `messageChat` / `user` exist in `Assets.xcassets`, use them when selected; if not,
   add filled variants to the catalogue (extend design system; do not use SF Symbols).
4. **You tab — App lock row.** Android's Security group has Profile & identity + **App lock**
   (routes to `SecuritySettingsScreen`: verify current PIN/bio → change PIN / re-enroll bio). iOS
   already has the full `Features/SecuritySettings/` feature (menu → verify → change / switch
   method, lockout timer) reachable only via All settings → Settings. Add the App lock `ZappRow`
   to the Security group routing to `SecuritySettings` (new `ZappTabs.Action.appLockTapped`,
   routed in `RootCoordinator` like the other You-tab rows). Update the stale header comment in
   `SettingsTabContent.swift` ("App lock … not available on iOS yet" — it is now).
5. **You tab — grouping parity.** Android order: People / Security (Profile, App lock) / Privacy
   (Tor, Background delivery*, Read receipts, Online status) / P2P (payment method) / Wallet
   (Local currency†, Choose server). Align iOS group membership and order: move the two P2P rows
   out of Privacy into their own `P2P` group (keep the iOS-only "P2P transactions" row there).
   *Background delivery stays absent pending Decision 1. †Android gates Local currency on
   CMC availability and the whole Wallet group on wallet existence — mirror with the iOS
   equivalent flags if present, else leave ungated and note in the phase-commit body.
6. **Strings hygiene.** Migrate the two `String(localized:defaultValue:)` rows to
   `Localizable.xcstrings` keys.

**Acceptance:** badge shows counts and animates; tab switch clicks haptically; App lock reachable
from You tab; groups match Android order; all strings from the catalogue; build + lint clean.

---

### Phase 2 — Onboarding completeness  *(small/medium)*

**Android refs:** `A:screen/onboarding/ZappOnboardingFlow.kt`, `view/MessagingIdentityView.kt`
(`MessagingPhaseIntro`), `view/OnboardingDoneScreen.kt`, `view/WalletPhaseIntroView.kt`,
`A:screen/onboarding/ZappRestoreFlow.kt` (KEEP_OPEN step), `A:screen/authentication/view/AuthenticationView.kt`
**iOS files:** `I:Features/CoordFlows/RestoreWalletCoordFlow*.swift`, `I:Features/AppLockSetup/*`,
`I:Features/RestoreInfo/*`

1. **Messaging-phase intro screen.** Android inserts `MessagingPhaseIntro` (Part 2 intro: eyebrow,
   hero, sub, Continue; **no back** — wallet already committed) between seed backup and username
   entry. iOS goes straight from `seedBackup` to `chatUsername`. Add a `messagingIntro` step
   (new lightweight reducer or a `LandingStep`-style case) rendered with the same
   eyebrow/hero/sub/CTA layout as the existing iOS wallet-intro landing pages, and route:
   seed backup → messaging intro → username. Content mirrors Android's strings (add xcstrings keys).
2. **Onboarding Done screen.** Android ends with `OnboardingDoneScreen(mode:)`: confirmation copy
   that reflects the chosen 2FA mode (Bio vs PIN), an "Enter Zapp" CTA, and a Confirm haptic pulse
   on appear. iOS currently finishes at `appLockSetup(.setupFinished)` and jumps to tabs. Add a
   `done` path step after app-lock setup with mode-aware copy, CTA → complete, and
   `UINotificationFeedbackGenerator().notificationOccurred(.success)` on appear.
3. **Restore-flow tail parity.** Android's "I already use Zapp" restore ends
   … SECURE_CHOICE → BIO/PIN → **KEEP_OPEN** (keep-the-app-open education). Verify iOS's
   `restoreInfo` step appears at the same point after app-lock in the restore path; if it renders
   before security setup, reorder to match Android (seed → birthday → restoring → seed confirm →
   username → deriving → secure → keep-open).
4. **Step transition + haptics.** Android animates steps with a directional slide (⅕ width) +
   fade, back-navigation sliding the opposite way, and fires Reject haptic on bio-enroll error.
   iOS: ensure landing-step changes (`welcome`/`walletIntro`/`walletChoice`/`creatingWallet`)
   animate with a matching directional slide+fade (`.transition(.asymmetric(...))` keyed on step
   ordinal), and add `.error` notification haptic on biometric enrollment failure in `AppLockSetup`.
5. **Unlock (cold-open) experience.** Android shows a full-screen brand "Z" privacy cover behind
   the system prompt, a retry state (`authentication_failed_welcome_title/subtitle`), and
   Error/Failed dialogs offering **Retry** and **Support**. Compare with the iOS app-lock unlock
   path (`AppPINEntryView` + local-auth flow from recent app-lock commits): iOS must have (a) a
   privacy cover over content while locked, (b) a retry affordance after failure, (c) a support
   escape hatch. Close whichever pieces are missing using existing UIComponents
   (`SplashView`/brand overlay) — iOS-native presentation is fine.

**Acceptance:** create-wallet run shows intro → choice → encrypting → seed → **messaging intro** →
username → deriving → 2FA choice → bio/PIN → **done**; restore run matches Android's order incl.
keep-open; step transitions directional; success/error haptics present; unlock has cover + retry +
support; build + tests + changelog.

---

### Phase 3 — Pay tab detail parity  *(small)*

**Android refs:** `A:screen/tabs/view/WalletBalanceCard.kt`, `WalletHomeView.kt`, `WalletActivitySection.kt`,
`WalletTabContent.kt`
**iOS files:** `I:Features/ZappTabs/ZappPayView.swift`, `ZappBalanceCard.swift`, `ZappBalanceChart.swift`,
`I:UIComponents/…/ZappTransactionRow` (as applicable)

1. **Fiat-first by default.** Android defaults `showZecAsPrimary = false` (fiat leads when a rate
   exists; tap toggles, and the activity rows follow). iOS defaults to `true`. Flip the iOS default
   to fiat-first, keep the toggle behavior and the shared toggle across balance + activity rows.
2. **Hero ticker animation.** Android animates balance changes with a slide-up (⅓ height) + fade
   (`heroTickerTransition`). Add the equivalent on iOS
   (`.transition(.move(edge: .bottom).combined(with: .opacity))` keyed by the formatted amount, or
   `.contentTransition(.numericText())` — pick whichever reads closest to Android's effect).
3. **Balance amount autosizing.** Android autosizes the hero (22→52sp) so long balances never wrap,
   ZEC ticker suffix baseline-aligned. Verify iOS `ZappBalanceCard` hero uses `minimumScaleFactor`
   / fixed single line with baseline-aligned ticker; fix if it wraps or truncates.
4. **See-all row.** Android renders a **centered** accent-text row ("See all"); iOS uses
   leading text + chevron. Match Android (centered, accent, no chevron).
5. **Balance-delta row.** Verify iOS delta row matches Android format:
   `▲/▼ <abs ZEC> · <±x.xx%> · <period label>` with success/danger coloring and small square
   separator dots. Close any formatting drift.
6. **Wallet-less Pay tab.** Android's Pay tab handles `SecretState.NONE` with an empty state
   (eyebrow/hero/sub + action list: "Create" highlighted / "Restore") and an in-tab seed reveal that
   hides the nav pill. Determine whether iOS can ever reach tabs without a wallet (Root gates on
   initialization). If unreachable, document that in the commit body and skip; if reachable, port
   the empty state.

**Acceptance:** fresh install shows fiat-first once a rate resolves; balance changes tick; see-all
centered; delta format identical; build + changelog.

---

### Phase 4 — Chat list parity  *(medium)*

**Android refs:** `A:screen/chat/view/ChatListView.kt`, `ChatListSwipeToLeave.kt`, `ChatTermsDialog.kt`,
`A:screen/chat/list/ChatListVM.kt`
**iOS files:** `I:Features/Chats/ChatsListView.swift`, `ChatsListStore.swift`, `ChatConversationRow.swift`

1. **Swipe-to-leave.** Android rows swipe away to leave/remove a conversation (with confirm via
   `onLeaveRequest`). iOS only has a context-menu Delete on direct chats. Add trailing
   swipe-action (iOS-native `.swipeActions` or drag-gesture equivalent matching the current
   `ScrollView`/`LazyVStack` structure) for **both** direct and group rows, driving the existing
   remove/leave actions, with a destructive confirm. Keep the context menu too.
2. **Terms-of-service dialog.** Android gates chat with `ChatTermsDialog` (Accept / Decline) driven
   by `state.tosDialog`. iOS has none. Port: first entry to the Chats tab presents an iOS-native
   confirmation (alert or sheet, Zapp-styled like `ConfirmDialog` usage) persisting acceptance;
   decline returns to the previous tab. Mirror Android's copy via xcstrings.
3. **Support row placeholder.** The pinned "Zapp Support" row ships with Phase 7 (support
   subsystem); this phase only leaves a clearly-marked `// Phase 7` extension point in
   `ChatsListStore` sorting (Android pins the aggregate support row above the timestamp-sorted
   list).
4. **Row parity check.** Verify iOS row contents match Android's
   (`ChatListConversationItem.kt`): avatar/initials, name, last-message preview, relative time,
   unread count chip, online dot placement, blocked handling. Close drift.

**Acceptance:** swipe-to-leave works on direct + group with confirm; ToS dialog gates first use and
persists; rows visually match; build + tests + changelog.

---

### Phase 5 — Composer & attachments  *(large)*

**Android refs:** `A:screen/chat/view/AttachmentSheet.kt`, `MediaAttachmentSheet.kt`,
`A:screen/chat/media/*` (ImageProcessor, MediaPickHandlers, CameraCaptureState),
`A:screen/chat/room/ChatRoomVM.kt` (onAttach*, onTakePhoto, onFilePicked, onShareAddress, onSendZec)
**iOS files:** `I:Features/Chats/ChatRoomView.swift`, `ChatRoomStore.swift` (+ new sheet views)

1. **Attachment sheet.** Android's composer "+" opens a sheet with four actions:
   **Share address** (posts your wallet address into the chat), **Send ZEC** (starts a send to the
   peer), **Split bill** (Phase 6), **Attach media**. iOS composer currently only mounts a
   `PhotosPicker`. Build `ChatAttachmentSheet` (Zapp-styled bottom sheet) with those actions;
   Split bill enters disabled/hidden until Phase 6 lands.
2. **Media sheet.** "Attach media" opens Android's second sheet: **Media** (gallery), **File**,
   **Camera** (Location omitted per Decision 3). iOS: Media → existing `PhotosPicker`
   flow; File → `fileImporter` (mirror Android's mime allow-list in `model/MimeTypes.kt`);
   Camera → `UIImagePickerController`/camera capture wrapped as a dependency client
   (`Dependencies/` pattern), permission handled with the standard iOS flow + `NSCameraUsageDescription`.
3. **Send-ZEC and Share-address wiring.** Route through Root the same way existing chat→wallet
   handoffs work (see `RootCoordinator` chat cases): Send ZEC opens `SendCoordFlow` prefilled with
   the peer's wallet address (from contact record); Share address posts a wallet-address message
   (the message type consumed by Phase 6's `WalletAddressBubble`). Wire formats already exist in
   the SDK — **do not invent new IPC message types**; mirror what Android sends
   (`ChatRoomVM.onShareAddressClick` / `onSendZecClick`).
4. **Scan wallet address from room** (`onScanWalletAddress`): entry from the room (Android exposes
   it in the send-ZEC path) opening the existing `ScanCoordFlow`.

**Acceptance:** composer "+" presents the attachment sheet; camera/file/gallery each produce a
delivered media message visible on an Android peer; Share address produces a message Android
renders as its wallet-address bubble; Send ZEC lands in the send flow prefilled; permissions
declared; build + tests + changelog.

---

### Phase 6 — Rich message bubbles & split bill  *(large)*

**Android refs:** `A:screen/chat/view/bubbles/` (PaymentRequestBubble, TransactionBubble,
WalletAddressBubble, LocationBubble, FileBubble, MediaBubble), `SplitBillSheet.kt`,
`ImageViewerOverlay.kt`, `A:screen/chat/room/ChatRoomVM.kt` (onPayRequest, onViewTransaction,
onSendToAddress, onCreateSplit)
**iOS files:** `I:Features/Chats/ChatMessageBubble.swift`, `ChatMediaBubble.swift`, `ChatRoomStore.swift`
(+ new bubble views)

1. **Message-type rendering.** Android renders dedicated bubbles for: payment request (amount,
   memo, **Pay** button → `onPayRequest` → send flow; paid/settled states), transaction reference
   (**View transaction** → transaction detail), wallet address (**Send to address**), file
   (name/size/type, open) and media. iOS renders only text + media. Add a bubble per type, matching
   Android's message-model discrimination (`A:screen/chat/model/ChatModels.kt`) — the SDK already
   carries these message types; parse the same fields the Android views read. Unknown types —
   including location messages, which are out of scope per Decision 3 — keep the current fallback.
2. **Split bill.** Android's `SplitBillSheet`: memo + per-participant share inputs (equal-split
   helper), creates linked payment-request messages (`onCreateSplit(memo, shares)`). Port as a
   Zapp-styled sheet reachable from Phase 5's attachment sheet; enable that action.
3. **Fullscreen image viewer.** Android taps a media bubble into `ImageViewerOverlay`
   (fullscreen, dismiss, zoom). iOS: present a fullscreen viewer (native
   pinch-zoom/`ScrollView` zoom, drag-down to dismiss — premium-iOS touch welcomed).
4. **Bubble long-press parity.** Android long-press = reply (with LongPress haptic). iOS keeps its
   context menu but must include Reply plus Copy for text bubbles; add a light impact haptic when
   the menu opens if the system doesn't already provide it.

**Acceptance:** each bubble type sent from Android renders correctly on iOS and vice versa
(payment request round-trip: request → Pay on iOS → Android sees settlement); split bill creates
requests for each share; images open fullscreen with zoom; build + tests + changelog.

---

### Phase 7 — Zapp Support subsystem  *(medium)*

**Android refs:** `A:screen/chat/support/` (SupportChatConstants, SupportTicketListScreen/VM,
SupportChatScreen/VM, SupportChatState), `A:screen/chat/list/ChatListVM.kt` (buildSupportRow,
isSupportConversation pinning)
**iOS files:** new `I:Features/Chats/Support*` + `ChatsListStore.swift`

1. Port `SupportChatConstants` (support public key(s), `BOT_PREFIX` stripping, side-asymmetric
   `isSupportConversation` logic) into a Swift equivalent.
2. **Ticket list screen:** lists support conversations as tickets (Android: status, subject/last
   message, new-ticket entry) → opens a support chat.
3. **Support chat screen:** chat-room variant with the bot-prefix handling and any composer
   restrictions Android applies (read `SupportChatVM` carefully).
4. **Pinned row:** aggregate "Zapp Support" row pinned above the sorted conversation list
   (subtitle = latest support message stripped of `BOT_PREFIX`), excluded from the normal list, and
   routed to the ticket list. Fill the Phase 4 extension point.

**Acceptance:** support conversations no longer appear as ordinary chats; pinned row shows latest
support message; ticket list → support chat send/receive works against the same support key
Android uses; build + tests + changelog.

---

### Phase 8 — Contacts & profile parity  *(medium)*

**Android refs:** `A:screen/chat/contacts/` (AddChatContactVM, EditChatContactVM, ChatContactsVM),
`A:screen/chat/view/AddChatContactSheet.kt`, `EditChatContactSheet.kt`, `BlockUserDialog.kt`,
`A:screen/chat/scan/ChatScanPublicKeyScreen.kt`, `A:screen/chat/view/NewConversationPublicKeyBanner.kt`,
`A:screen/chat/view/ChatProfileTabsView.kt`, `ChatProfileP2pKeyDialog.kt`, `ChatProfileSeedPhraseDialog.kt`,
`A:screen/chat/profile/ChatProfileVM.kt`
**iOS files:** `I:Features/Chats/ChatContactForm*`, `ChatContactsList*`, `NewChat*`, `ChatProfile*`,
`ChatRoomStore.swift`

1. **Contact form multi-address fields.** Android's add/edit contact captures name, public key,
   primary wallet address **plus typed addresses: transparent / EVM / Solana**, each with its own
   scan icon (scans route by field). iOS has name/key/single address. Add the typed fields (persist
   via the existing `walletAddresses: [String: String]` map with Android's
   `ADDR_TYPE_TRANSPARENT/EVM/SOLANA` keys) and per-field scan via `ScanCoordFlow`.
2. **Scan public key.** Android: new-conversation shows a scan affordance
   (`ChatScanPublicKeyScreen`) + a banner when a key is scanned. iOS `NewChat` has no scan. Add a
   scan entry (camera icon in the key field / toolbar) reusing the scan flow with a
   public-key validator (`PublicKeyRules`), feeding the detected-key path `NewChatStore` already has.
3. **In-room contact management.** Android's room can add/edit the peer contact (sheet), and
   block/unblock with confirm dialog. iOS: from the chat room's title/menu, offer
   Add-to-contacts (when unknown) / Edit contact / Block with an iOS-native confirm; reuse
   `ChatContactForm` and the existing `setBlocked` plumbing.
4. **Profile wallet-address surface.** Android profile has segmented tabs: Messaging ID (QR, name
   edit, copy) / Wallet address (Shielded / Transparent sub-tabs, each with QR + caption). iOS has
   only the messaging-ID card. Add the segmented wallet-address surface using the existing
   `ZappSegmentedSelector` + `QRCodeGenerator`, sourcing addresses the same way the Receive screen
   does.
5. **Delete identity.** Android profile/chat-settings expose Delete identity with a destructive
   confirm dialog. Mirror on iOS profile (destructive row + confirmation; wire to the SDK's
   identity-reset the same way Android's `onDeleteClick` path does).
6. **Secret reveals (in scope per Decision 2).** Port Android's seed-phrase and P2P private-key
   reveal dialogs (`ChatProfileSeedPhraseDialog.kt`, `ChatProfileP2pKeyDialog.kt`) into the iOS
   profile. Requirements: reveal only after an app-lock authentication check (reuse the
   `SecuritySettings` verify path / local-auth dependency), content hidden on backgrounding
   (mirror `OnboardingSeedBackup.hideSensitiveContent`), words/key rendered with the existing
   redacted-string components, copy-to-pasteboard only where Android offers it. Update the stale
   "minus its secret-reveal surfaces" header comment in `ChatProfileStore.swift`.

**Acceptance:** contact round-trips all four address types with Android; new-chat scan fills the
key; block/edit reachable from the room; profile shows wallet QR tabs; delete identity works with
confirm; build + tests + changelog.

---

### Phase 9 — Chat privacy settings verification  *(small — notifications deferred per Decision 1)*

**Android refs:** `A:screen/chat/readreceipts/ReadReceiptsSettingsView.kt`,
`A:screen/chat/onlinestatus/OnlineStatusSettingsView.kt`
**iOS files:** `I:Features/Chats/ChatPrivacySettingView.swift`

1. **Read receipts / online status detail screens:** verify the iOS staged screens match Android's
   (explanation copy + toggle + subtitle states). Close copy/layout drift.
2. **Notifications/background delivery: no UI change** (Decision 1 defers the subsystem to a
   separate ticket). Record the deferral in the commit body. If nothing needed fixing in step 1,
   this phase may be folded into Phase 10's commit — note that in the commit body instead.

---

### Phase 10 — System feel: haptics, keep-awake, dialogs  *(small/medium)*

**Android refs:** haptic call sites (`FloatingPillNavBar`, `ZappOnboardingFlow`, `ChatMessageBubble`,
swipe rows), `A:screen/ScreenTimeoutVM.kt`, `A:screen/error/*`, keep-open screen
**iOS files:** cross-cutting; `I:UIComponents/`, feature views listed above

1. **Haptic vocabulary.** Introduce a tiny `ZappHaptics` helper (selection / success / error /
   long-press impact) and apply at Android's call sites: tab switch (done Phase 1), onboarding done
   + bio error (done Phase 2), bubble long-press/reply, swipe-to-leave commit, send success in
   composer. Keep it subtle and iOS-idiomatic (UIKit feedback generators).
2. **Keep screen awake.** Android's `ScreenTimeoutVM` holds the screen on during long-running
   states (restore/sync — read its call sites). iOS only does this in Voting. Apply
   `isIdleTimerDisabled` during wallet restore/resync progress screens, cleared on disappear.
3. **Error surface parity.** Android registers `ErrorDialog`, `ErrorBottomSheet`, `SyncError`
   dialogs. Verify each error path a user can hit on Android (sync error from Pay tab, send
   failure, chat failure states) has an iOS surface with equivalent copy and actions (retry /
   support). Close gaps with iOS-native alerts/sheets, Zapp-styled.
4. **Receive/QR sheet feel.** Android gives QR/Request routes a sheet-style transition. iOS should
   present Receive QR / Request as sheets (if not already) — iOS-native `.sheet` with detents is
   the right analogue.
5. **Premium-iOS touches** from Appendix C that Renee approves at sign-off.

---

### Phase 11 — Full verification pass  *(audit-only phase)*

The auditor walks **every** Android screen in `A:screen/` side-by-side with iOS (simulator +
Android build or the Android source), checking: screen exists, same sections/rows/buttons, same
empty/loading/error states, same navigation entries/exits, strings equivalent, dark/light OK.
Produce `docs/ANDROID_PARITY_VERIFICATION.md` — a table of every screen with ✅/❌ and file refs —
fix small residual gaps directly, and file the big ones back into this document as new phases.
Commit: `[ZAPP-1] Phase 11: parity verification pass`.

---

## 3. Decision log

| # | Decision | Answer | Date |
|---|---|---|---|
| 1 | Notifications/background delivery in scope? | **No — deferred to a separate ticket; rows stay absent** | 2026-07-25 |
| 2 | Port secret-reveal dialogs (seed / P2P key)? | **Yes — behind app-lock auth gate (Phase 8.6)** | 2026-07-25 |
| 3 | Location sharing in scope? | **No — send and bubble both out; incoming keeps fallback** | 2026-07-25 |

Overall plan signed off by Renee on 2026-07-25 ("Approved — start as written").

---

## Appendix A — Audit evidence (what was compared)

- Android nav map: `RootNavGraph.kt` → `MainAppGraph` → `walletNavGraph` (start `TabsArgs`) +
  `chatNavGraph` (9 chat routes) + ~80 wallet routes.
- Confirmed already at parity on iOS (no phase needed): onboarding skeleton (landing steps + seed
  backup + username + identity derivation + app-lock setup), restore w/ birthday estimation, tabs
  shell geometry (0.81 width pill, 48pt cells, sharp rects), Pay tab structure (header, sync chip +
  progress row, balance card w/ spark chart + delta + period selector + breakdown + shield,
  activity rows w/ fiat/zec swap, speed-dial FAB pay/send/swap/receive, empty state), chat core
  (list, room text/reply/media-receive, new chat DM+group, group info rename/add/leave, identity
  setup, network status chip + details), contacts list w/ blocked chip, profile QR + name + read
  receipts/presence toggles, You-tab groups (mostly), SecuritySettings feature, Tor, local
  currency picker, choose server, offramp/UPI (incl. pay-merchant → payment corridor), swap
  (`swapWithNearTapped` → SwapAndPay), transactions flows, smart banner.
- Gap sources: iOS code comments self-documenting omissions
  (`ChatsListView.swift:12`, `SettingsTabContent.swift:11`, `ChatProfileStore.swift:8`), missing
  symbols (no iOS match for SupportChat*, AttachmentSheet, SplitBill, PaymentRequest/Transaction/
  WalletAddress/Location/File bubbles, ImageViewerOverlay, ChatScanPublicKey, ChatTermsDialog,
  ChatListSwipeToLeave, BackgroundDelivery*, MessagingPhaseIntro, OnboardingDoneScreen,
  KeepOpen), and behavioral diffs read from source (badge count vs dot, fiat-first default,
  haptics, hero ticker animation, see-all row style, contact address fields).

## Appendix B — iOS-only surfaces (leave untouched)

Keystone HW wallet (AddKeystoneHWWallet, SignWithKeystone, scan-keystone), Voting coord flow,
"All settings" → ZODL Settings tree (About, What's New, Feedback, Advanced settings, Export logs,
Delete wallet, Address book, Integrations/Flexa), ZappSmartActionStrip on Pay,
"P2P transactions" You-tab row, DeeplinkWarning, OSStatusError, background WiFi sync task.
(Android-side extras like Debug screens / hotfix dialogs are ops tools, deliberately not ported.)

## Appendix C — Premium-iOS recommendations (approve individually)

1. Context-menu **previews** on chat rows (peek the conversation) — iOS-only affordance.
2. `.contentTransition(.numericText())` on the hero balance for the ticker effect (Phase 3).
3. Drag-down-to-dismiss + pinch-zoom in the Phase 6 image viewer.
4. Detented sheets (`.presentationDetents`) for attachment/media sheets and Receive QR.
5. `ScrollView` edge effects + subtle nav-pill shadow on scroll (material-free, Swiss-compatible).
6. Haptic on send success (light impact) — matches iMessage muscle memory.
7. Home-screen quick actions (long-press app icon → New chat / Scan / Receive).
8. Already shipped and kept: edge-back swipe with parallax tracking the finger.
