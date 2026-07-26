# Android Parity — Decisions Pending (Renee)

**Companion to:** `docs/ANDROID_PARITY_HANDOVER.md` · **Branch:** `feature/ZAPP-1-android-parity` · **As of:** Phase 10 complete (`0fbe976e`)

Every item below was found during Phase 1–10 execution/audit, documented in its phase's commit body, and left unresolved because it's a product/design call rather than a parity bug. Nothing here is blocking — the branch builds, tests, and lints clean at every phase. Work through this at your own pace; nothing needs an answer before Phase 11 runs (Phase 11 is a read-mostly verification pass and will likely add more rows to this list).

---

## 1. Missing design-system assets

Each of these currently has a working fallback (documented in-code), not a broken feature.

| # | Asset needed | Where it's used | Current fallback | Phase |
|---|---|---|---|---|
| 1.1 | Filled `pay`/`messageChat`/`user` tab icons | Selected-tab state in `ZappPillNavBar` | Outlined icon, re-tinted only (no shape swap) | 1 |
| 1.2 | Group-conversation avatar glyph (Android: `Icons.Default.Group`) | Group chat rows with no photo | `person.2.fill` SF Symbol | 4 |
| 1.3 | Camera glyph | Attach-media sheet's Camera tile | `camera.fill` SF Symbol | 5 |
| 1.4 | Zapp Support brandmark (Android: `img_zapp_logo`) | Pinned support row avatar | Accent-square avatar + `Icons.help` | 7 |

**Decision needed:** add these 4 assets to `Assets.xcassets` (I can generate/source and wire them once you approve), or accept the fallbacks as final.

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

## 5. Smart Banner content still unreachable

Phase 10 discovered the entire Android-equivalent error/prompt banner view (`HomeView`, containing `SmartBannerView`) is dead code in the shipped Zapp shell — only reachable from its own SwiftUI `#Preview`, never from `ZappTabsView`. Phase 10 restored **just** the sync-error sheet and the "Contact Support" path (the two most user-facing pieces) onto the Pay tab.

**Still stranded**, same root cause:

| # | Content | Detail |
|---|---|---|
| 5.1 | Shield-funds prompt | Prompts to auto-shield transparent funds — currently has no reachable UI in the shipped app. |
| 5.2 | Disconnected banner | Network-disconnected state banner — same issue. |
| 5.3 | Help sheet | A general help/support sheet distinct from the sync-error sheet's "Contact Support" button. |

**Decision needed:** fold these into Phase 11 (it already walks every screen and would naturally hit this), open as a standalone follow-up phase, or confirm they're intentionally not needed in the Zapp shell (e.g. superseded by `ZappSmartActionStrip`, which is iOS/Zapp-only and already ships — worth checking whether it already covers 5.1 before treating this as a gap).

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

## Suggested next step

Phase 11 (full verification pass) is starting now regardless — it's read-mostly, walks every Android screen side-by-side with iOS, and will fix small drift directly while filing bigger findings back into the handover doc as new phases. It will likely surface a few more rows for this list. Once Phase 11 lands, this document plus its findings should give you one clean pass to work through before deciding what (if anything) becomes a Phase 12.
