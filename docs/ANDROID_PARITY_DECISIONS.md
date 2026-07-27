# Android Parity — Decisions Pending (Renee)

**Companion to:** `docs/ANDROID_PARITY_HANDOVER.md` · `docs/ANDROID_PARITY_VERIFICATION.md` · **Branch:** `feature/ZAPP-1-android-parity` · **As of:** Phase 14 complete

Every item below was found during Phase 1–14 execution/audit, documented in its phase's commit body, and left unresolved because it's a product/design call rather than a parity bug. Nothing here is blocking — the branch builds, tests, and lints clean at every phase. Work through this at your own pace.

**Phase 11 changed this list as follows:** §5 (stranded Smart Banner content) is **resolved as not a gap** — the equivalent Android route is equally dead code. §1 gained three rows (1.5–1.7, more missing assets behind SF-Symbol fallbacks). A new §7 records two cosmetic chat-list drifts. Phase 11 also filed one new **Phase 12** (unified send form) in the handover doc, which needs a go/no-go from you before any work starts.

**Phase 14 changed this list as follows:** seven items you approved — §3.1, §3.2, §3.4, §4.1, §6.1, §6.5, and §7.1 — are now built and resolved (see each row for what shipped).

---

## 1. Missing design-system assets — **RESOLVED by Phase 13**

Renee approved commissioning all seven. Phase 13 closed every row below; no SF-Symbol fallback
remains at any of these call sites. Two findings worth recording:

- **Only five new assets were actually needed, not seven.** Rows 1.5–1.7 asked for add / arrow-right
  / close / check / person glyphs, and the catalogue already shipped all five of them
  (`Icons.plus`, `Icons.arrowRight`, `Icons.xClose`, top-level `check`, `Icons.user`). Those rows
  were pure wiring — no new art. The genuinely missing glyphs were the three filled tab icons plus
  a group glyph, a camera glyph and the Zapp brandmark.
- The catalogue's icon family was reverse-engineered before anything was drawn: a 24×24 grid,
  stroke-width 2, round caps and joins, ink `#282622`, exported as a 512×512 RGBA8 PNG whose
  `Contents.json` carries no template-rendering key (tint comes from `.renderingMode(.template)`
  inside `zImage`). Every new asset matches that convention exactly.

Each of these previously had a working fallback (documented in-code), not a broken feature.

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

**How each new asset was produced** (Phase 13):

| Asset | Source |
|---|---|
| `Icons.payFilled` | Solid disc at the outlined `pay`'s own outer radius with its arrow knocked out — the treatment the catalogue's existing `checkSolid` already uses. Same centre and footprint as the outline, so the tab doesn't shift on selection. |
| `Icons.userFilled` | The outlined `user`'s measured geometry filled rather than stroked: head disc at its outer radius, shoulder arc closed into a solid body. Identical footprint to the outline. |
| `Icons.messageChatFilled` | Derived from the outlined `messageChat` PNG itself — interiors flood-filled, then a separation band carved along the small bubble's real edge via a Euclidean distance transform. No geometry invented; both bubble tails and the exact silhouette are preserved. |
| `Icons.users` | Drawn as a sibling of the outlined `user` (same circle-head + wide-arc-shoulder vocabulary, stroke weight, caps and footprint), with the back person smaller, raised, and separated from the foreground person by a clearance band so it reads as occluded. Android's `Icons.Default.Group` is a filled Material glyph and would have clashed with the outlined `user` shown directly beside it in the same avatar slot. **Redrawn during the Phase 13 audit**: the first cut placed both heads at the same size and height with crossing shoulder arcs, which read as a face rather than two people at the real 20pt call size. |
| `Icons.camera` | Constructed on the family's 24×24 / stroke-2 grid. Android uses Compose's `Icons.Default.CameraAlt`, which ships no vector drawable in the repo to extract. |
| `zappLogo` | Rendered from Android's own design source, `design/Zapp-designs/assets/zapp_logo.svg` — the same mark as its `img_zapp_logo` raster, but vector-sourced so it stays crisp. Full-colour, so it is drawn untinted (its `#FF9417` field is exactly the app's `accent`). |

**Decision — resolved:** all seven rows are closed; the five pre-existing glyphs were reused and five new assets were added to `Assets.xcassets`.

**One new row found by the Phase 13 audit, deliberately left open:**

| # | Asset needed | Where it's used | Current fallback | Phase |
|---|---|---|---|---|
| 1.8 | History / clock glyph | `OfframpView`'s "Recent transactions" button | `clock.arrow.circlepath` SF Symbol | 13 |

This is the last SF Symbol left in any `Zapp*`/`Chat*`/offramp shell file — the fifteen that remain
project-wide are all in upstream Zashi screens (Voting, Splash), which this branch does not touch.
Unlike rows 1.5–1.7 it cannot be closed by rewiring: the catalogue ships no clock or history glyph,
so closing it means commissioning an eighth asset. Same call as before — flagged rather than
improvised.

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
| 3.1 | Camera-permission-denied messaging — **RESOLVED by Phase 14** | Chat's send-failure strip now offers the same `ZappButton` → Settings deep link `ScanView` already used, replacing the "enable it in Settings" sentence. Shared via `ChatSendFailureBanner`, used by both the room and Support chat. | 5/10/14 |
| 3.2 | Image viewer has no "Save to gallery" — **RESOLVED by Phase 14** | A save button next to the close button saves the original file (not a re-compressed copy) via a new `PhotoLibraryClient` dependency (add-only access), confirming with "Image saved" or a failure toast. A refusal is handled apart from a failed write — it is permanent, since iOS never re-prompts — so it shows a notice that does not time out, carrying the same Settings deep link §3.1 gives a denied camera. Adds `NSPhotoLibraryAddUsageDescription`; button only appears once the photo has finished downloading. | 6/14 |
| 3.3 | Delete-identity confirmation copy | Ported verbatim from Android: "Your funds are unaffected and can be recovered at any time with your seed phrase." True, but both platforms *also* wipe local wallet data and all preferences — the copy may understate what's actually happening. Same wording issue exists on Android today; could raise it upstream rather than diverge here. | 8 |
| 3.4 | Screen-recording-already-in-progress isn't caught — **RESOLVED by Phase 14** | A new `ScreenCaptureClient` dependency (`UIScreen.main.isCaptured`) is checked up front by both the chat profile's secret reveal and the onboarding seed-backup screen; a recording already running refuses the reveal outright, before authentication, with an explicit message — instead of only reacting to a recording that starts later. | 8/14 |

---

## 4. Receive / Request presentation

The handover doc said to convert Receive and Request to sheets. On investigation, **Android's Receive screen is a plain horizontal push, not a sheet** — converting iOS's Receive to `.sheet` would have been a regression (and would break the existing edge-swipe/parallax back system, which depends on preferences that don't cross a sheet boundary). This was **not done**, correctly, per Phase 10's audit.

The one real gap that *was* still open, now closed:

| # | Item | Detail |
|---|---|---|
| 4.1 | Request ZEC flow presentation — **RESOLVED by Phase 14** | The `zecKeyboard → requestZec → requestZecSummary` chain was lifted out of Receive's own `NavigationStack` into a standalone `ReceiveRequestFlow`, presented as a `fullScreenCover` (the iOS equivalent of "a full destination that rises and drops back down") — matching Android's `slideIntoContainer(Up)` for its `REQUEST` route. Receive itself keeps its own `NavigationStack`, so its edge-swipe/parallax back system is unaffected. |

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
| 6.1 | Context-menu **previews** on chat rows (peek the conversation) | **Built by Phase 14** — long-pressing a row shows `ChatConversationPreviewCard` (name, unread count or last-active time, last message), built entirely from list data already held (no room opened, no message stream subscribed), alongside the existing Leave action. |
| 6.2 | `.contentTransition(.numericText())` hero balance ticker | **Already shipped** (Phase 3) |
| 6.3 | Drag-down-to-dismiss + pinch-zoom in the image viewer | **Already shipped** (Phase 6, doc explicitly welcomed it there) |
| 6.4 | Detented sheets (`.presentationDetents`) for attachment/media sheets and Receive QR | Attachment/media sheets: partially — Phase 5 used a two-page single sheet, not confirmed to use detents specifically. Receive QR: **not applicable** — Receive isn't a sheet at all (see §4). Needs a decision on whether the attachment sheet specifically should get detents. |
| 6.5 | `ScrollView` edge effects + subtle nav-pill shadow on scroll | **Built by Phase 14** — `ZappScrollEdge` fades scrollable content out at the top/bottom edges (a ramp of the screen's own background colour, no material/blur, per the Swiss-design brief) and reports scroll travel so `ZappPillNavBar` deepens its shadow once content is passing beneath it. |
| 6.6 | Haptic on send success | **Already shipped** (Phase 10, as part of the required haptic vocabulary, not gated on this list) |
| 6.7 | Home-screen quick actions (long-press app icon → New chat / Scan / Receive) | Not built — needs approval |
| 6.8 | Edge-back swipe with parallax | **Already shipped and kept** (predates this branch, per the doc) |

**Decision needed:** approve/reject 6.4 (attachment sheet detents specifically) and 6.7 — the rest are now resolved one way or another.

---

## 7. Chat-list cosmetic drift (found in Phase 11)

Both are one-line changes I deliberately did **not** make, because they are motion/sub-pixel details
I had no way to visually verify, and in each case iOS's current behaviour looks like a considered
choice rather than an oversight.

| # | Item | Detail |
|---|---|---|
| 7.1 | Trailing row divider — **RESOLVED by Phase 14: matched to Android** | iOS now emits `ZappRowDivider(inset: true)` after every row, including the last, matching Android's `ZappRowDivider(inset = true)` placement exactly. |
| 7.2 | List reorder animation | Android animates rows moving as conversations re-sort by timestamp (`animateItem()`). iOS's `LazyVStack`/`ForEach` re-sorts without animation. SwiftUI's equivalent is fiddlier than Compose's and can read as jank if applied carelessly. |

**Decision needed:** match Android on 7.2, or accept iOS as-is. Doesn't affect function.

---

## Suggested next step

Phase 11 has landed, so the audit programme is complete: every Android screen has been walked
side-by-side with iOS and the result is 71 ✅ / 6 ⚠️ / 0 ❌ (see
`docs/ANDROID_PARITY_VERIFICATION.md`). There are no known parity defects left on the branch.

**Phase 14 closed §3.1, §3.2, §3.4, §4.1, §6.1, §6.5, and §7.1** — all seven were approved and built
in one pass (chat send-failure Settings button, save-photo-to-gallery, screen-recording-already-in-progress
guard, Request ZEC as a rising `fullScreenCover`, chat-row long-press preview, scroll-edge fade +
nav-pill scroll shadow, and the trailing chat-list divider).

What's actually left for you, in the order it's cheapest to answer:

1. **§1 assets** — already resolved (Phase 13), except row 1.8 (history/clock glyph), still an open one-off.
2. **§6.4 / §6.7** — two independent yes/nos (attachment sheet detents specifically; home-screen quick actions).
3. **§7.2 list reorder animation + §2.1 badge placement** — two small taste calls.
4. **§3.3 delete-identity confirmation copy** — the one remaining §3 item, a wording call shared with Android.
5. **Phase 12 (unified send form)** — the only large item, and a legitimate decline. Capability parity already exists; it's a form-shape question in a money-moving flow.

§5 needs nothing from you — Phase 11 closed it.
