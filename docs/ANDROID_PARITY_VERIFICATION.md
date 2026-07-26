# Android Parity — Phase 11 Verification Pass

**Companion to:** `docs/ANDROID_PARITY_HANDOVER.md` · `docs/ANDROID_PARITY_DECISIONS.md`
**Branch:** `feature/ZAPP-1-android-parity` · **Baseline:** Phase 10 complete (`9dbfec0a`)

Every Android screen under
`../android-zapp/ui-lib/src/main/java/co/electriccoin/zcash/ui/screen/` (abbreviated `A:`)
walked against iOS `secant/Sources/` (abbreviated `I:`). Legend:

- ✅ at parity (screen exists, same sections/rows/buttons, same empty/loading/error states, reachable, strings from the catalogue)
- ⚠️ parity with a documented divergence or a note worth Renee's eye — not a defect
- ❌ genuine gap

**Effort was weighted** per the phase brief: deep scrutiny on what Phases 1–10 changed most
(Pay tab, chat list/room/bubbles/support/contacts/profile), existence + no-regression + reachability
confirmation on untouched areas (Keystone, Voting, All-settings tree, swap, offramp, transactions,
security settings, server setup).

---

## 0. Headline result

**81 verdict rows: 74 ✅, 7 ⚠️, 0 ❌.** (Rows in §4 condense several closely-related Android screen
dirs each, so the underlying screen count is higher — 46 wallet dirs + 9 chat routes + the shell
surfaces.) **No parity defect was found that needed fixing beyond one piece of dead code.**

The seven ⚠️ rows are, in full: the wallet-less Pay tab (unreachable by construction on iOS), the
Wallet-group gating flags (inapplicable on iOS), the chat-list empty state (iOS *adds* one Android
lacks), the chat-list divider/reorder cosmetics (→ decisions §7), the chat-settings hub (dead route
on Android), the sheets-vs-screens shape difference for balances/accountlist/more/insufficientfunds,
and unified send (→ Phase 12). None is a defect.

The two most load-bearing discoveries of this pass are *negative* results that retire open questions
rather than create work:

1. **Android's `HomeArgs` route is dead code on Android.** `AndroidHome` / `HomeView` /
   `SmartBannerView` is registered as a composable (`WalletNavGraph.kt:244`) but **nothing anywhere
   in the Android codebase navigates to it** (verified: the only `HomeArgs` matches repo-wide are its
   own declaration, its own `composable<>` registration, and the unrelated `ChatHomeArgs`). The iOS
   smart-banner tree being stranded is therefore **not a parity gap** — it is the same dead subtree on
   both platforms. This resolves **decisions §5** (5.1 shield-funds prompt, 5.2 disconnected banner,
   5.3 help sheet). See §4 below for how each of the three is in fact covered in the shipped shell.
2. **Android's `ChatSettingsArgs` route is also dead code on Android** (`ChatNavGraph.kt:51`
   registration + declaration only; no `forward(ChatSettingsArgs)` anywhere). So iOS having no
   dedicated chat-settings hub screen — its contents live distributed across the You tab — is not a
   gap either.

Both were found by treating "is this actually reachable?" as a first-class check on **both** sides,
which is what the brief asked for after the `HomeView` incident.

---

## 1. Zapp shell — tabs, Pay, You (Phases 1, 3, 10 territory)

| Screen / surface | ✅ | iOS file | Android file | Note |
|---|---|---|---|---|
| Tab shell / scaffold | ✅ | `I:Features/ZappTabs/ZappTabsView.swift` | `A:tabs/view/ZappTabsScaffold.kt` | Launch tab **Chats** both sides; fade-through (not slide) both sides; `hideNavPill` both sides |
| Floating pill nav bar | ✅ | `I:UIComponents/ZappPillNavBar/ZappPillNavBar.swift` | `A:tabs/view/FloatingPillNavBar.kt` | Count badge + selection haptic shipped Phase 1. Badge *placement* differs from Android's actual pixels — already **decisions §2.1** |
| Pay tab | ✅ | `I:Features/ZappTabs/ZappPayView.swift` | `A:tabs/view/WalletHomeView.kt` | Header+sync chip, sync progress row, balance card, "Recent activity" label, activity list, 4-action speed dial — same order |
| — fiat-first default | ✅ | `ZappPayView.swift:30` | `WalletHomeView.kt` (`showZecAsPrimary = false`) | Matches; toggle shared between balance and activity rows on both |
| — see-all row | ✅ | `ZappPayView.swift:187` | `WalletActivitySection.kt` | Centered accent text, no chevron |
| — sync chip / progress row | ✅ | `I:Features/ZappTabs/ZappSyncStatus.swift` | `A:tabs/view/WalletSyncStatusViews.kt` | Synced/syncing/restoring/offline/error/connecting all present; row hidden when synced |
| — sync error surface | ✅ | `I:Features/ZappTabs/ZappSyncErrorSheet.swift` | `A:home/error/*` via `HomeVM` pipeline | Phase 10 salvage. Android reaches the same remedies through `HomeVM`'s nav pipeline, which the Zapp tab *does* subscribe to (`WalletHomeView.kt`) |
| — balance card + shield | ✅ | `I:Features/ZappTabs/ZappBalanceCard.swift` | `A:tabs/view/WalletBalanceCard.kt` | Hero ticker, autosize, delta row, breakdown, shield action (`isShieldBreakdownEnabled = true` on Android) |
| — balance chart | ✅ | `I:Features/ZappTabs/ZappBalanceChart.swift` | `A:home/balancechart/*` | Spark chart + period selector |
| — activity rows | ✅ | `I:UIComponents/.../ZappTransactionRow` | `A:tabs/view/WalletActivitySection.kt` | Unread, swap, fiat/ZEC follow the shared toggle |
| — empty activity state | ✅ | `ZappPayView.swift:201` | `A:transactionhistory/widget/*` | Accent bar + title + subtitle |
| — wallet-less Pay tab | ⚠️ | n/a | `A:tabs/view/WalletTabContent.kt` (`SecretState.NONE`) | Android has an in-tab create/restore empty state + seed reveal. **iOS cannot reach tabs without a wallet** (Root gates on initialization), so unreachable-by-construction. Documented at Phase 3.6; no action |
| — `ZappSmartActionStrip` | ✅ | `ZappPayView.swift:68` | *(none)* | iOS-only, Appendix B — correctly not a gap |
| You tab | ✅ | `I:Features/ZappTabs/SettingsTabContent.swift` | `A:tabs/view/SettingsTabContent.kt` | Group membership **and order** verified identical: Profile card → People → Security → Privacy → P2P → Wallet |
| — Privacy group | ✅ | same | same | Tor / Read receipts / Online status. Background-delivery row absent per **Decision 1** |
| — Wallet group gating | ⚠️ | same | same | Android gates the group on `hasWallet` and Local currency on `VersionInfo.IS_CMC_AVAILABLE`. iOS has **no CMC equivalent** (it sources rates via the SDK, not CoinMarketCap) and cannot reach tabs wallet-less, so both gates are inapplicable. Phase 1.5 explicitly permitted leaving them ungated |
| — iOS-only rows | ✅ | same | *(none)* | "P2P transactions" + "All settings"/More group — Appendix B |
| Chats tab loading state | ✅ | `I:Features/Chats/ChatIdentitySetupView.swift:39` | `A:tabs/view/ZappTabsScaffold.kt` (`ChatsTabContent`) | Android's 3-state (spinner → setup → list) **is** matched: the iOS setup view itself branches `.idle/.initializing` to the same centered accent spinner |

## 2. Chat (Phases 4–9 territory — deepest scrutiny)

All 9 Android chat routes accounted for. Android's chat tree is 120 Kotlin files; iOS's is 53 Swift
files / ~11.9k lines.

| Screen / surface | ✅ | iOS file | Android file | Note |
|---|---|---|---|---|
| Chat list (`ChatHomeArgs`) | ✅ | `I:Features/Chats/ChatsListView.swift` | `A:chat/view/ChatListView.kt` | Support row pinned above timestamp-sorted list; loading state; network chip + details sheet |
| — empty state | ⚠️ | `ChatsListView.swift:128` | *(none)* | **iOS adds** a title/subtitle empty state Android does not have; support row stays reachable above it. Deliberate iOS improvement, documented in-file |
| — row contents | ✅ | `I:Features/Chats/ChatConversationRow.swift` | `A:chat/view/ChatListConversationItem.kt` | Avatar/initials, name, preview, relative time, unread chip, online dot, blocked handling |
| — swipe-to-leave | ✅ | `I:Features/Chats/ChatSwipeToLeaveRow.swift` | `A:chat/view/ChatListSwipeToLeave.kt` | Direct **and** group, destructive confirm, context menu retained |
| — leave confirm | ✅ | `ChatsListStore.swift` → `.alert` | `A:chat/view/ChatListLeaveDialog.kt` | iOS-native alert (correct platform substitution) |
| — ToS gate | ✅ | `I:Features/Chats/ChatTermsView.swift` | `A:chat/view/ChatTermsDialog.kt` | Accept/decline; swipe-away = decline; decline returns to previous tab |
| — row divider / reorder | ⚠️ | `ChatsListView.swift:118` | `ChatListView.kt` | Two cosmetic drifts, deliberately **not** changed: iOS omits the divider after the *last* row (Android emits one), and iOS has no reorder animation (Android `animateItem()`). Both are sub-pixel/motion nits I could not visually verify; flagged rather than churned. See §5 |
| Chat room (`ChatRoomArgs`) | ✅ | `I:Features/Chats/ChatRoomView.swift` | `A:chat/view/ChatRoomView.kt` | Header + back + network chip, messages, reply bar, composer, date separators |
| — bubble dispatch | ✅ | `I:Features/Chats/ChatRoomBubbleRow.swift` | `A:chat/view/ChatMessageBubble.kt` | **All 6 Android bubble types + text present**: payment request, wallet address, transaction, media (image+video), file, text |
| — payment request bubble | ✅ | `ChatPaymentRequestBubble.swift` | `A:chat/view/bubbles/PaymentRequestBubble.kt` | Pay action, paid/settled states |
| — transaction bubble | ✅ | `ChatTransactionBubble.swift` | `.../TransactionBubble.kt` | View-transaction → detail |
| — wallet-address bubble | ✅ | `ChatWalletAddressBubble.swift` | `.../WalletAddressBubble.kt` | Send-to-address; QR plate fixed-white **matching Android** (see §3) |
| — file bubble | ✅ | `ChatFileBubble.swift` | `.../FileBubble.kt` | Name/size/type, open |
| — media bubble | ✅ | `ChatMediaBubble.swift` | `.../MediaBubble.kt` | Progress, tap → viewer |
| — location bubble | ✅ | *(fallback)* | `.../LocationBubble.kt` | Out of scope per **Decision 3**; incoming keeps the plain-text fallback, wire type named in `ChatContentType.swift` |
| — wire content types | ✅ | `I:Features/Chats/ChatContentType.swift` | `A:chat/model/MimeTypes.kt` | Literals mirrored exactly; no invented IPC types |
| — image viewer | ✅ | `I:Features/Chats/ChatImageViewer.swift` | `A:chat/view/ImageViewerOverlay.kt` | Fullscreen + pinch-zoom + drag-dismiss. "Save to gallery" absent — already **decisions §3.2** |
| — attachment sheet | ✅ | `I:Features/Chats/ChatAttachmentSheet.swift` | `A:chat/view/AttachmentSheet.kt` | Share address / Send ZEC / **conditional** Split-bill-vs-Request-payment label / Attach media — conditional matches Android exactly |
| — media sheet | ✅ | same + `ChatRoomAttachments.swift` | `A:chat/view/MediaAttachmentSheet.kt` | Media / File / Camera. Location option omitted per **Decision 3** |
| — camera picker | ✅ | `I:Features/Chats/ChatCameraPicker.swift` | `A:chat/media/CameraCaptureState.kt` | Permission-denied copy inconsistency already **decisions §3.1** |
| — split bill | ✅ | `I:Features/Chats/ChatSplitBillSheet.swift` | `A:chat/view/SplitBillSheet.kt` | Memo + per-participant shares, equal-split helper |
| — in-room contact mgmt | ✅ | `ChatRoomView.swift:26` → `.titleTapped` | `A:chat/view/ChatRoomView.kt:200` + `BlockUserDialog.kt` | DM title opens add/edit/block; group title opens group info. Blocked senders filtered at **both** ingest and cold read |
| — send-failure banner | ✅ | `ChatRoomView.swift:46` | `A:chat/room/ChatRoomState.kt` | Inline danger text |
| — group info | ✅ | `I:Features/Chats/GroupInfoView.swift` | `A:chat/view/ChatRoomGroupInfoSheet.kt` | Rename / add / leave |
| — message status | ✅ | `I:Features/Chats/ChatMessageStatusIndicator.swift` | `A:chat/view/MessageStatusIndicator.kt` | |
| — date separators | ✅ | `I:Features/Chats/ChatDateSeparator.swift` | `A:chat/view/ChatDateSeparator.kt` | |
| — relative time | ✅ | `I:Features/Chats/ChatRelativeTime.swift` | `A:chat/common/RelativeTime.kt` | |
| New conversation (`NewConversationArgs`) | ✅ | `I:Features/Chats/NewChatView.swift` | `A:chat/view/NewConversationView.kt` (+6 sub-views) | DM + group, search, participant chips, contact rows, empty state, public-key banner |
| — scan public key (`ChatScanPublicKeyArgs`) | ✅ | via `ScanCoordFlow` + `PublicKeyRules` | `A:chat/scan/ChatScanPublicKeyScreen.kt` | Phase 8.2; iOS reuses the shared scan flow rather than a dedicated screen — capability parity |
| Contacts (`ChatContactsArgs`) | ✅ | `I:Features/Chats/ChatContactsListView.swift` | `A:chat/view/ChatContactsView.kt` | List + blocked chip |
| — contact form | ✅ | `I:Features/Chats/ChatContactFormView.swift` | `A:chat/view/{Add,Edit}ChatContactSheet.kt` | Name, public key, primary address **+ transparent/EVM/Solana** with per-field scan |
| — address wire keys | ✅ | `I:Models/ChatContact.swift:43-45` | `A:common/model/AddressBookContact.kt:17-20` | `zcash_transparent` / `evm` / `solana` — byte-identical, so contacts round-trip |
| Profile (`ChatProfileArgs`) | ✅ | `I:Features/Chats/ChatProfileView.swift` | `A:chat/view/ChatProfileTabsView.kt` | Segmented Messaging-ID / Wallet-address, with Shielded/Transparent sub-tabs + QR + caption |
| — secret reveals | ✅ | `I:Features/Chats/ChatProfileSecret{s,Views}.swift` | `A:chat/view/ChatProfile{SeedPhrase,P2pKey}Dialog.kt` | Phase 8.6, app-lock gated, hide-on-background. Pre-existing screen-recording limitation already **decisions §3.4** |
| — delete identity | ✅ | `ChatProfileStore.swift` | `A:chat/view/ChatProfileDeleteDialog.kt` | Destructive confirm. Copy concern already **decisions §3.3** |
| — edit name | ✅ | `ChatProfileView.swift` | `A:chat/view/ChatProfileEditNameDialog.kt` | |
| Chat settings (`ChatSettingsArgs`) | ⚠️ | *(distributed across You tab)* | `A:chat/settings/ChatSettingsScreen.kt` | **Dead route on Android** — registered, never navigated to. Its five sections map onto iOS's You tab + network details sheet + profile. Not a gap; see §0 |
| Read receipts (`ReadReceiptsSettingsArgs`) | ✅ | `I:Features/Chats/ChatPrivacySettingView.swift` | `A:chat/readreceipts/ReadReceiptsSettingsView.kt` | Exact structural parity: hero icon, intro, on/off/both-sides blocks, control group header, bottom bar Back + **staged Save** enabled only when changed |
| Online status (`OnlineStatusSettingsArgs`) | ✅ | same | `A:chat/onlinestatus/OnlineStatusSettingsView.kt` | Same, with on/off/**reciprocal** blocks |
| Background delivery | ✅ | *(absent)* | `A:chat/backgrounddelivery/*` | Deliberately absent per **Decision 1** (deferred to its own ticket) |
| Identity setup | ✅ | `I:Features/Chats/ChatIdentitySetupView.swift` | `A:chat/identity/ChatIdentitySetupScreen.kt` | Form + deriving + failed + retry, and the initializing spinner |
| Username rules | ✅ | `I:Features/Chats/UsernameRules.swift` | `A:chat/common/UsernameRules.kt` | Must agree across create/restore on both platforms |
| Network status | ✅ | `I:Features/Chats/ChatNetworkStatusView.swift` | `A:chat/view/{NetworkStatus,ChatListNetworkChip,ChatRoomNetworkChip}.kt` | Chip + details sheet (connection / DHT / peers / protocol / encryption) |
| Support ticket list (`SupportTicketListArgs`) | ✅ | `I:Features/Chats/SupportTicketListView.swift` | `A:chat/support/SupportTicketListScreen.kt` | Reached from the pinned support row (`ChatListVM.onSupportClick` ↔ `.supportRowTapped`) |
| Support chat (`SupportChatArgs`) | ✅ | `I:Features/Chats/SupportChatView.swift` | `A:chat/support/SupportChatScreen.kt` | Bot-prefix handling, composer restrictions |
| — support constants | ✅ | `I:Features/Chats/SupportChatConstants.swift` | `A:chat/support/SupportChatConstants.kt` | Side-asymmetric `isSupportConversation`; support convos excluded from the ordinary list |
| — pinned support row | ✅ | `I:Features/Chats/SupportContactRow.swift` | `ChatListView.kt` (`item(key="support_row")`) | Brandmark asset missing — already **decisions §1.4** |

## 3. Dark / light mode

Correctness proxy per the brief: no fixed colors where an adaptive token belongs.

| Check | Result |
|---|---|
| `Color(red:)` / `Color(hex` / `#colorLiteral` / `UIColor(red:` / hex string literals | **Zero** in `Features/ZappTabs/`, `Features/Chats/`, `Features/SmartBanner/`, `UIComponents/Zapp*`. The only 4 repo-wide hits are pre-existing upstream ZODL files (`PollsListView`, `TorSetupView`, `Tooltip` ×2) — untouched by this branch |
| `ZappColors` hex confinement | `UIComponents/Zapp/ZappColors.swift` uses `Color(zappHex:)` 47× but defines **both** a `light` and a `dark` palette resolved through `color(_ colorScheme:)`; `zappHex` appears in no other file. Correctly confined to the token layer |
| Fixed `Color.white` / `Color.black` | 5 shipping uses, **all verified as intentional Android parity, not bugs**: QR plates in `ChatProfileView` + `ChatWalletAddressBubble` (Android `WalletAddressBubble.kt:79-80,121` hardcodes `Color.White`/`Color.Black` — a QR must keep a light plate to stay scannable in dark mode), the `ChatImageViewer` black backdrop (Android `ImageViewerOverlay.kt:87`), the secret-reveal scrim, and the `ZappToggle` knob (Android `ZappComponents.kt:439` is also `Color.White`) |
| Verdict | ✅ Dark/light correct by this proxy |

**SF Symbols** (banned by the design system) — 8 uses in Zapp/Chat-owned files. Two are already
tracked (decisions §1.2 `person.2.fill`, §1.3 `camera.fill`); the other **six are newly found and
have been added to decisions §1** as rows 1.5–1.7, because closing them means adding assets to the
catalogue, which per `CLAUDE.md` is a deliberate design-system extension needing sign-off — not a
unilateral fix.

## 4. Untouched wallet surfaces — existence + reachability

46 Android wallet screen dirs mapped; **every** iOS counterpart has a real construction site
(parent view, CoordFlow destination, `RootView`/`SettingsView` destination, or `zashiSheet`). No
regression from Phases 1–10 in any of them. Condensed — full mapping was verified row by row:

| Android | iOS | ✅ | Note |
|---|---|---|---|
| about, advancedsettings, addressbook, deletewallet, disconnect, exportdata, feedback, resync, securitysettings, taxexport, tor, whatsnew, chooseserver, exchangerate, heightinfo | `I:Features/{About,Settings,AddressBook,DeleteWallet,DisconnectHWWallet,PrivateDataConsent,SendFeedback,ResyncWallet,SecuritySettings,ExportTransactionHistory,TorSetup,WhatsNew,ServerSetup,CurrencyConversionSetup,WalletBirthday}` | ✅ | All mounted via `SettingsView`/`RootView` |
| welcome, splash, warning | `I:Features/Welcome`, `I:UIComponents/Overlays/SplashView.swift`, `I:Features/NotEnoughFreeSpace` | ✅ | |
| receive, qrcode, request | `I:Features/Receive`, `I:Features/AddressDetails`, `I:Features/RequestZec` | ✅ | Receive is a push on **both** (decisions §4). Request presentation still open as **decisions §4.1** |
| scan, send, reviewtransaction, transactionprogress | `I:Features/Scan`, `I:Features/SendForm`, `I:Features/SendConfirmation` (+ Sending/Pending/Success/Failed) | ✅ | |
| transactiondetail, transactionhistory, transactionfilters, transactionnote | `I:Features/TransactionDetails`, `I:Features/{TransactionList,TransactionsManager}`, `FiltersSheet`, `AnnotationSheet` | ✅ | Filters/note are sheets on iOS vs screens on Android — shape differs, capability matches |
| swap, topup | `I:Features/SwapAndPayForm`, `I:Features/Offramp` | ✅ | iOS folds top-up into Offramp |
| walletbackup, restore, onboarding, authentication, keepopen | `I:Features/CoordFlows/{WalletBackup,RestoreWallet}CoordFlow*`, `I:Features/{RecoveryPhraseDisplay,AppLockSetup,RestoreInfo}` | ✅ | `keepopen` == iOS `RestoreInfoView` (`.keepScreenOn*` strings) — Phase 2.3 confirmed |
| balances, accountlist, more, insufficientfunds | `I:Features/BalanceBreakdown`, `WalletAccountsSheet`, `MoreSheet`, `InsufficientFundsSheet` | ⚠️ | Sheets on iOS vs screens on Android. `BalancesView` has no Settings/Home entry on iOS (only from send/cross-pay) — noted, matches how the Zapp shell surfaces balance via the Pay card instead |
| texunsupported | `I:Features/SendForm/SendFormView.swift:123` (`isSheetTexAddressVisible`) | ✅ | **Not missing** — iOS handles TEX via a sheet (`isValidTexAddress` / `isTexSendSupported`) where Android uses a full screen |
| unifiedsend | *(split: `SendFormView` + `SwapAndPayForm`)* | ⚠️ | Android merges ZEC-send and swap into one asset-selector form; iOS keeps two screens. Filed as **Phase 12** — see §5 |
| crashreporting, hotfix, integrations, flexa | *(n/a)* | ✅ | Android ops tooling / imperatively-invoked SDK; deliberately not ported (Appendix A/B) |
| connectkeystone, scankeystone, selectkeystoneaccount, signkeystonetransaction | `I:Features/{AddKeystoneHWWallet,CoordFlows/SignWithKeystone*}` | ✅ | iOS-only per Appendix B — present and mounted, not re-audited |
| home | *(dead on both)* | ✅ | See §0.1 |

**Pre-existing dead view, no action:** `I:Features/SwapAndPayForm/SwapAndPayOptInView.swift` has zero
construction sites (its sibling `SwapAndPayOptInForcedView` is mounted at
`SwapAndPayCoordFlowView.swift:76`). Verified **pre-existing on `main`** (introduced by `226a1a02`,
an ancestor of `main`) and untouched by any commit on this branch. Left pristine per the fork
discipline that keeps upstream files merge-clean — the same treatment `HomeView` gets.

### Decisions §5 resolved

| Item | Finding |
|---|---|
| 5.1 Shield-funds prompt | Covered in the shipped shell on **both** platforms by the balance card's shield affordance — Android `WalletHomeView.kt` passes `isShieldBreakdownEnabled = true`; iOS `ZappPayView.swift:146` wires `onShieldTapped → .smartBanner(.shieldFundsTapped)`. Not stranded |
| 5.2 Disconnected banner | Covered by the sync chip + progress row, which both platforms render for `DISCONNECTED`/`ERROR` (`WalletSyncStatusViews.kt` ↔ `ZappSyncStatus.swift`). Not stranded |
| 5.3 Help sheet | Not reachable from Android's Zapp shell either (lives only in the dead `HomeArgs` tree). iOS's Contact-Support path from the sync-error sheet is the shipped equivalent |

**→ Recommend closing decisions §5 as "not a gap".** No Phase needed.

## 5. Strings

All 453 `String(localizable:)` accessors used across `Features/Chats/`, `Features/ZappTabs/`,
`Features/CoordFlows/` and `UIComponents/Zapp*` resolve to keys defined in
`secant/Resources/Localizable.xcstrings` (1,596 entries) — **zero missing, zero stale**. No
hardcoded display literals in the audited views; the two `String(localized:defaultValue:)` rows
Phase 1 was asked to migrate are gone.

---

## 6. Outcome of this pass

**Fixed directly (1):** removed dead `placeholder(_:)` from `ZappTabsView.swift` — a leftover
scaffold from early tab work with no call site.

**Filed as a new phase (1):** **Phase 12 — Unified send form** (appended to the handover doc).
Android's Send entry (`HomeVM.onSendButtonClick` → `UnifiedSendArgs`, and the chat room's Send-ZEC /
send-to-address paths) lands on one `UnifiedSendScreen` whose asset selector switches between
ZEC-send and swap (`UnifiedSendVM.kt:390` `isSwap = selectedAsset !is ZecSwapAsset`). iOS keeps
`SendFormView` and `SwapAndPayForm` as two screens. **Capability parity already exists** — both
platforms' Pay speed dials expose Send and Swap separately — so this is a form-shape difference in a
money-moving flow, filed so Renee can decline it cheaply rather than left undocumented.

**Added to the decisions doc (2 items):** six newly-found SF-Symbol/missing-asset rows (§1.5–1.7),
and the two cosmetic chat-list drifts (new §7) — trailing row divider and list reorder animation.

**Deliberately not changed:** the two cosmetic chat-list nits above, the QR/backdrop/toggle fixed
colors (verified intentional Android parity), and the pre-existing upstream dead swap opt-in view.

**Verification:** `xcodebuild … -scheme zodl-internal … build` clean; `zodlTests` green apart from
the three known pre-existing failures (`OfframpTests.topUpRequiresPreviewBeforeStartingBridge`,
`Near1ClickTests.curatedKeepsSupportedAndDropsRest`,
`FlexaSecurityTests.switchingWalletAccountCancelsOpenFlexaSession`); SwiftLint at the 1,089 baseline
with zero new violations in touched files.
