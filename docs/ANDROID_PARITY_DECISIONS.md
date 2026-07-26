# Android Parity — Decisions Pending (Renee)

**Companion to:** `docs/ANDROID_PARITY_HANDOVER.md` · `docs/ANDROID_PARITY_VERIFICATION.md` · **Branch:** `feature/ZAPP-1-android-parity` · **As of:** Phase 11 complete

Every item below was found during Phase 1–11 execution/audit, documented in its phase's commit body, and left unresolved because it's a product/design call rather than a parity bug. Nothing here is blocking — the branch builds, tests, and lints clean at every phase. Work through this at your own pace.

**Phase 11 changed this list as follows:** §5 (stranded Smart Banner content) is **resolved as not a gap** — the equivalent Android route is equally dead code. §1 gained three rows (1.5–1.7, more missing assets behind SF-Symbol fallbacks). A new §7 records two cosmetic chat-list drifts. Phase 11 also filed one new **Phase 12** (unified send form) in the handover doc, which needs a go/no-go from you before any work starts.

---

## 1. Missing design-system assets

Each of these currently has a working fallback (documented in-code), not a broken feature.

| # | Asset needed | Where it's used | Current fallback | Phase |
|---|---|---|---|---|
| 1.1 | Filled `pay`/`messageChat`/`user` tab icons | Selected-tab state in `ZappPillNavBar` | Outlined icon, re-tinted only (no shape swap) | 1 |
| 1.2 | Group-conversation avatar glyph (Android: `Icons.Default.Group`) | Group chat rows with no photo | `person.2.fill` SF Symbol | 4 |
| 1.3 | Camera glyph | Attach-media sheet's Camera tile | `camera.fill` SF Symbol | 5 |
| 1.4 | Zapp Support brandmark (Android: `img_zapp_logo`) | Pinned support row avatar | Accent-square avatar + `Icons.help` | 7 |
| 1.5 | Add / arrow-right / close / check / person glyphs | `NewChatView` — group-mode FAB (`plus`/`arrow.right`), participant chip remove (`xmark`), selected-contact tick (`checkmark`), contact placeholder avatar (`person.fill`) | SF Symbols | 11 |
| 1.6 | Add glyph | `ZappSpeedDialFab` collapsed state (`plus`) | SF Symbol | 11 |
| 1.7 | Check glyph | `ZappOfframpComponents` (`checkmark`) | SF Symbol | 11 |

Rows 1.5–1.7 were found by Phase 11's design-system sweep. They are the same class as 1.2/1.3: the
design system bans SF Symbols, but closing them means adding assets to the catalogue, which
`CLAUDE.md` says must be a deliberate extension rather than a silent one-off — so they are listed
here instead of being fixed unilaterally. Phase 11 also confirmed the **good** news: zero hardcoded
colors in any `Zapp*`/`Chat*` file, and the five fixed `Color.white`/`Color.black` uses (QR plates,
image-viewer backdrop, toggle knob) are all verified-intentional matches to Android's own
hardcoded values, so dark/light is correct.

**Decision needed:** add these 7 assets to `Assets.xcassets` (I can generate/source and wire them once you approve), or accept the fallbacks as final.

---

## 2. Doc-vs-Android wording conflict

| # | Item | Detail |
|---|---|---|
| 2.1 | Chats-tab badge placement | The handover doc's own wording says "onto the icon's top-trailing corner" (which iOS follows); Android's actual layout anchors the badge to the *tab cell's* corner instead, landing it further from the glyph. iOS currently matches the **doc**, not **Android's actual pixels**. |

**Decision needed:** keep iOS as-is (matches doc), or move the badge to match Android's actual on-screen position (doc would need a one-line correction too).

---

## 3. Small UX inconsistencies

| # | Item | Detail | Phase |
|---|---|---|---|
| 3.1 | Camera-permission-denied messaging | Chat's camera tile now shows "enable it in Settings" as text; `ScanView` already has a real **Open Settings button** for the identical situation. Worth making the two consistent. | 5/10 |
| 3.2 | Image viewer has no "Save to gallery" | Android's fullscreen image viewer offers it; iOS's doesn't. Needs a new `NSPhotoLibraryAddUsageDescription` permission string — a privacy-prompt addition, your call before it's added. | 6 |
| 3.3 | Delete-identity confirmation copy | Ported verbatim from Android: "Your funds are unaffected and can be recovered at any time with your seed phrase." True, but both platforms *also* wipe local wallet data and all preferences — the copy may understate what's actually happening. Same wording issue exists on Android today; could raise it upstream rather than diverge here. | 8 |
| 3.4 | Screen-recording-already-in-progress isn't caught | The secret-reveal screen (and the pre-existing onboarding seed-backup screen it mirrors) only detects a recording that *starts* while the screen is open (`UIScreen.capturedDidChange`). If a recording is already running before the user taps Reveal, nothing blocks it. Inherited limitation from existing code, not introduced by this branch — but a real gap. A cheap hardening (refuse reveal when `UIScreen.main.isCaptured`) would need a new dependency and affects the onboarding screen too. | 8 |

---

## 4. Receive / Request presentation

The handover doc said to convert Receive and Request to sheets. On investigation, **Android's Receive screen is a plain horizontal push, not a sheet** — converting iOS's Receive to `.sheet` would have been a regression (and would break the existing edge-swipe/parallax back system, which depends on preferences that don't cross a sheet boundary). This was **not done**, correctly, per Phase 10's audit.

The one real gap that *is* still open:

| # | Item | Detail |
|---|---|---|
| 4.1 | Request ZEC flow presentation | Android rises its Request flow as a slide-up transition; iOS pushes it horizontally through a 3-screen chain (`zecKeyboard → requestZec → requestZecSummary`) inside the Receive `NavigationStack`. |

**Decision needed:** worth restyling Request's presentation to match Android's slide-up, or leave as an iOS-idiomatic push? (Small, self-contained change if you want it.)

---

## 5. Smart Banner content still unreachable — **RESOLVED by Phase 11: not a gap**

Phase 10 discovered the entire Android-equivalent error/prompt banner view (`HomeView`, containing `SmartBannerView`) is dead code in the shipped Zapp shell — only reachable from its own SwiftUI `#Preview`, never from `ZappTabsView`. Phase 10 restored **just** the sync-error sheet and the "Contact Support" path (the two most user-facing pieces) onto the Pay tab.

**Still stranded**, same root cause:

| # | Content | Detail |
|---|---|---|
| 5.1 | Shield-funds prompt | Prompts to auto-shield transparent funds — currently has no reachable UI in the shipped app. |
| 5.2 | Disconnected banner | Network-disconnected state banner — same issue. |
| 5.3 | Help sheet | A general help/support sheet distinct from the sync-error sheet's "Contact Support" button. |

**Phase 11 answered this — no action needed.** The root cause is not an iOS oversight: Android's
`HomeArgs` route (`AndroidHome` → `HomeView` → the banner tree) is registered in `WalletNavGraph.kt:244`
but **nothing in the entire Android codebase navigates to it**. It is the same dead subtree on both
platforms, so its contents are not an iOS parity gap. Each of the three is in fact covered in the
shipped shell:

- **5.1 Shield-funds prompt** — covered by the balance card's shield affordance on both sides
  (Android passes `isShieldBreakdownEnabled = true` in `WalletHomeView.kt`; iOS wires
  `onShieldTapped → .smartBanner(.shieldFundsTapped)` at `ZappPayView.swift:146`).
- **5.2 Disconnected banner** — covered by the sync chip + sync progress row, which both platforms
  render for `DISCONNECTED`/`ERROR`.
- **5.3 Help sheet** — not reachable from Android's Zapp shell either; iOS's Contact-Support path
  from the Phase 10 sync-error sheet is the shipped equivalent.

**Recommend closing §5.** The dead `HomeView`/`SmartBannerView` files stay pristine on purpose, so
the monthly upstream merge keeps applying cleanly.

---

## 6. Appendix C — Premium iOS touches (need your individual approval)

Per the handover doc, none of these ship without an explicit yes. Status of each:

| # | Touch | Status |
|---|---|---|
| 6.1 | Context-menu **previews** on chat rows (peek the conversation) | Not built — needs approval |
| 6.2 | `.contentTransition(.numericText())` hero balance ticker | **Already shipped** (Phase 3) |
| 6.3 | Drag-down-to-dismiss + pinch-zoom in the image viewer | **Already shipped** (Phase 6, doc explicitly welcomed it there) |
| 6.4 | Detented sheets (`.presentationDetents`) for attachment/media sheets and Receive QR | Attachment/media sheets: partially — Phase 5 used a two-page single sheet, not confirmed to use detents specifically. Receive QR: **not applicable** — Receive isn't a sheet at all (see §4). Needs a decision on whether the attachment sheet specifically should get detents. |
| 6.5 | `ScrollView` edge effects + subtle nav-pill shadow on scroll | Not built — needs approval |
| 6.6 | Haptic on send success | **Already shipped** (Phase 10, as part of the required haptic vocabulary, not gated on this list) |
| 6.7 | Home-screen quick actions (long-press app icon → New chat / Scan / Receive) | Not built — needs approval |
| 6.8 | Edge-back swipe with parallax | **Already shipped and kept** (predates this branch, per the doc) |

**Decision needed:** approve/reject 6.1, 6.4 (attachment sheet detents specifically), 6.5, 6.7 individually — the rest are already resolved one way or another.

---

## 7. Chat-list cosmetic drift (found in Phase 11)

Both are one-line changes I deliberately did **not** make, because they are motion/sub-pixel details
I had no way to visually verify, and in each case iOS's current behaviour looks like a considered
choice rather than an oversight.

| # | Item | Detail |
|---|---|---|
| 7.1 | Trailing row divider | Android emits `ZappRowDivider(inset = true)` after **every** conversation row, including the last, leaving a hairline above the bottom clearance. iOS suppresses it on the last row (`ChatsListView.swift:118`). "Android is the spec" argues for matching; visual taste argues for iOS's version. |
| 7.2 | List reorder animation | Android animates rows moving as conversations re-sort by timestamp (`animateItem()`). iOS's `LazyVStack`/`ForEach` re-sorts without animation. SwiftUI's equivalent is fiddlier than Compose's and can read as jank if applied carelessly. |

**Decision needed:** match Android on either/both, or accept iOS as-is. Neither affects function.

---

## Suggested next step

Phase 11 has landed, so the audit programme is complete: every Android screen has been walked
side-by-side with iOS and the result is 71 ✅ / 6 ⚠️ / 0 ❌ (see
`docs/ANDROID_PARITY_VERIFICATION.md`). There are no known parity defects left on the branch.

What's actually left for you, in the order it's cheapest to answer:

1. **§1 assets (7 rows)** — one yes/no: commission the assets, or accept the SF-Symbol/text fallbacks as final.
2. **§6 premium-iOS touches (6.1, 6.4, 6.5, 6.7)** — four independent yes/nos.
3. **§7 chat-list cosmetics + §2.1 badge placement + §4.1 Request presentation** — three small taste calls.
4. **§3 small UX inconsistencies (3.1–3.4)** — 3.2 and 3.4 involve new privacy prompts / a new dependency, so they're the ones worth real thought.
5. **Phase 12 (unified send form)** — the only large item, and a legitimate decline. Capability parity already exists; it's a form-shape question in a money-moving flow.

§5 needs nothing from you — Phase 11 closed it.
