---
name: zapp-ui-standards
description: The Zapp Swiss visual design system as it applies to SwiftUI on iOS — the ZappColors/ZappTextStyle/ZappMotion token layer, the Zapp-vs-Zashi component split, sharp corners, bottom-left back, token-only styling, localized strings, and the iOS-specific rules (44pt targets, Dynamic Type, safe areas, colorScheme, sheet detents, VoiceOver) that have no Android equivalent. MUST BE USED PROACTIVELY before creating any SwiftUI view, adding a UIComponent, or making non-trivial UI edits in ios-zapp. Skip for pure logic/reducer edits with no view changes.
---

Android's `zapp-style` skill is the sibling of this one and the two describe the SAME visual system. When a rule here is silent, `../android-zapp/.claude/skills/zapp-style/design-system.md` is the fuller reference — but translate, don't transliterate: several Android rules have different iOS spellings, and the "iOS divergences" section below lists the ones that are deliberate.

## The two-layer component split

This repo carries two generations of UI, and the distinction drives nearly every review comment:

| Layer | Location | Tokens it reads | Status |
|---|---|---|---|
| **Zapp** (fork) | `UIComponents/Zapp/` (29 files) | `ZappColors`, `ZappTextStyle`, `ZappMotion` | The visual source of truth. New work goes here. |
| **Zashi** (upstream) | the other ~64 files in `UIComponents/` | `Design.*`, `Asset.Colors.*` | Kept for upgradability. Don't restyle wholesale. |

- **New Zapp components go in `UIComponents/Zapp/`, one component per file**, named for the component (`ZappFab.swift`, `ZappRow.swift`). This mirrors Android's `component/zapp/` rule.
- Structural upstream wrappers (`ZashiButton`, `ZashiTextField`, `ZashiSheet`, `ZashiToggle`) stay. Replacing them is an upgrade-cost decision, not a styling one.
- A screen that is fork-authored should read `ZappColors`/`ZappTextStyle` throughout. A screen inherited from upstream may legitimately still read `Design.*` — flag it as **migration debt**, not as a bug.

## Tokens only — the most-violated rule

```swift
// ✓
Text(String(localizable: .chatRoomSend))
    .zappFont(.rowTitle, style: ZappColors.text)
    .background(ZappColors.surfaceAlt.color(colorScheme))

// ✗ every one of these
Text("Send")                                   // hardcoded display string
    .font(.system(size: 15, weight: .semibold)) // raw font
    .foregroundColor(.orange)                   // raw colour
    .background(Color(red: 1, green: 0.58, blue: 0.09))
```

Every visual value comes from a token. `ZappColors` is an enum resolved per `colorScheme`, so colour always reads `ZappColors.<case>.color(colorScheme)` inside a view holding `@Environment(\.colorScheme) private var colorScheme`, or is passed as a `Colorable` to `.zappFont(_:style:)` / `.zImage(width:height:style:)`.

### `ZappColors` cases (21)

`bg` · `surface` · `surfaceAlt` · `surfaceInput` · `border` · `borderStrong` · `text` · `textMuted` · `textSubtle` · `accent` · `accentSoft` · `accentText` · `success` · `successSoft` · `danger` · `dangerSoft` · `chipBg` · `overlay` · `navPill` · `onAccent` · `shadow`

Two pairing rules carried over from Android:
- `onAccent` on a full `accent` background. **Never** `accentText` there — `accentText` is for `accentSoft` backgrounds only.
- `accent` is the single call-to-action colour: CTA fills, progress fills, eyebrow labels, highlight icon boxes. Spending it on decoration devalues it.

`onAccent` (white) on `accent` (#FF9417) is 2.21:1 — below WCAG AA. This is a deliberate brand decision replicated from Android (documented in `ZappColors.swift:90`). Do not "fix" it in a drive-by; it needs a brand decision, not a patch.

### `ZappTextStyle` tokens (16)

`screenTitle` · `sectionTitle` · `display` · `displaySecondary` · `balanceDisplay` · `balanceFraction` · `eyebrow` · `groupLabel` · `rowTitle` · `rowSubtitle` · `body` · `caption` · `chip` · `button` · `buttonSmall` · `mono`

Applied only via `.zappFont(_:style:)` or `.zappFont(_:color:)`. Never `.font(...)` + `.foregroundColor(...)` by hand — the modifier also carries tracking and line height, which a raw `.font` silently drops.

Fonts are **Inter** (all styles) and **RobotoMono** (`mono` only). Android ships system-sans and system-mono; iOS deliberately keeps Inter (decision D4). A one-off style may extend the scale in a `private extension ZappTextStyle` beside its view — `ChatRoomView.swift` does this for its two glyphs — but it must still go through `ZappTextStyle`, never inline `Font`.

### Spacing

`Design.Spacing.*` — `_none` 0, `_xxs` 2, `_xs` 4, `_sm` 6, `_md` 8, `_lg` 12, `_xl` 16, `_2xl` 20, `_3xl` 24, `_4xl` 32, `_5xl` 40, `_6xl` 48, `_7xl` 64, `_8xl` 80, `_9xl` 96, `_10xl` 128, `_11xl` 160.

Off-scale Swiss values (**18pt screen gutter**, 14pt button vertical padding, 10pt header vertical padding) stay as named constants in a `private enum Constants` inside the component — that is the established shape in `ZappButton`, `ZappScreenHeader`, `ZappBottomActionBar`. Don't round them onto the token scale, and don't scatter them as bare literals in the body.

### Motion

`ZappMotion.state` (0.12s) · `.content` (0.20s) · `.reveal` (0.35s) · `.shake` (0.40s) — all `timingCurve(0.4, 0, 0.2, 1)`, Compose's `FastOutSlowInEasing`. Swiss language: short crisp tweens. **No springs, no overshoot** — `.spring()` / `.bouncy` / `.snappy` are violations.

Press feedback is `.buttonStyle(.zappPress)` (0.97 scale). Android layers a ripple under it; iOS has none, so the scale carries the feedback alone. Tappable Zapp controls get it — **unless the Android counterpart sets `indication = null`**, in which case `.buttonStyle(.plain)` is the faithful port, not an oversight. `ZappToggle` is the standing example (`ZappComponents.kt:427-431`); its knob is likewise a deliberate hardcoded `Color.White` in both schemes, not a missing token. Check the Kotlin before "fixing" either.

## Sharp corners — non-negotiable

`Rectangle()` everywhere: borders, backgrounds, surfaces, tiles, chips, FABs, avatars.

```swift
.overlay { Rectangle().strokeBorder(ZappColors.border.color(colorScheme), lineWidth: 1) }  // ✓
.clipShape(RoundedRectangle(cornerRadius: 12))                                             // ✗
.cornerRadius(8) / .clipShape(Circle()) / Capsule()                                        // ✗
```

The only rounded things on screen are ones iOS draws itself (sheet corners, the keyboard, system alerts). `CustomRoundedRectangle` and `Capsule` usages under the upstream Zashi layer are pre-existing; leave them unless the file is being converted to Zapp.

## Layout & navigation

- **Back is bottom-left.** `ZappBottomActionBar(onBack:)` — optionally with a trailing primary action inside the same bordered panel; a lone back button renders chrome-free. Never a top-bar back, never a floating text link.
  - **The one documented exception:** the chat room keeps `ZappBackButton` in its header because the composer owns the bottom edge (`ChatRoomView.swift:13`). Android's `ChatRoomView.kt` does the same. A new screen claiming this exception needs the same justification in a comment.
- **Headers** are `ZappScreenHeader(title:subtitle:onTitleTap:left:right:)` — 18pt horizontal gutter, 10pt vertical. `onTitleTap` makes the title a `.zappPress` button; omit it and the title is inert.
- **18pt is the in-app screen gutter.** Onboarding uses a wider one; match the neighbouring screen rather than inventing a value.
- Tab-level chrome is `ZappPillNavBar` / `ZappNavBar`. FABs are `ZappFab` — square, `Rectangle`, accent background. Never a circular FAB.

## Strings, assets, icons

- **Every user-facing string** lives in `secant/Resources/Localizable.xcstrings` and is read with `String(localizable: .someKey)` (~850 call sites; there are no hardcoded display literals in views). Accessibility labels and clipboard labels count as user-facing.
  - `Text(verbatim:)` is legitimate **only** for non-linguistic glyphs — `ChatRoomView`'s `"+"` is the precedent. A word in `verbatim` is a violation.
- **The app name is always `ZODL`** — all caps, everywhere, including strings, comments, and commit messages. Never `Zodl`/`zodl`. Fixed technical identifiers (`zodl_internal`, `zodl-ios`, scheme names, bundle IDs) are exempt.
- **Icons and images** come from the catalogue via `Asset.Assets.<name>.image` (e.g. `Asset.Assets.Icons.arrowUp.image`), rendered with `.zImage(width:height:style:)`. **Prefer these over SF Symbols** — `Image(systemName:)` in fork code is a violation unless no catalogue equivalent exists.
- `Asset.*` symbols are SwiftGen-generated into `Sources/Generated/`. **Never edit those files** — add the asset to `.xcassets` and let the build regenerate.

## iOS-specific standards (no Android equivalent)

These are the rules the Android skill cannot give you. They are where iOS UI review actually finds bugs.

1. **44×44pt minimum touch target** — Apple HIG. (Android's rule is 48dp; do not copy the number.) `ZappButton` is 52pt; small glyph buttons must be padded up. `ChatAttachGlyph` is 44×44 for exactly this reason.
2. **Dynamic Type** — never a fixed-height container around text that can grow. Prefer `minHeight` over `height`. A sheet detent computed from content (`ChatAttachmentSheet.detentHeight`) must include slack for larger type — that file's `ChatAttachmentSheetChrome.slack` is the pattern.
3. **Both colour schemes** — every component holds `@Environment(\.colorScheme)` and resolves tokens through it. A component that renders correctly in light and illegibly in dark is a bug; check both in the preview.
4. **Safe areas** — content respects them; only a background deliberately bleeds, via `.ignoresSafeArea(.container, edges: .bottom)` scoped to the background layer (`ChatRoomInputRow` is the precedent). Never `.ignoresSafeArea()` on a whole screen containing controls.
5. **One `.sheet` per view** — SwiftUI honours a single `.sheet` modifier per view. Multiple sheets on one screen must be mounted on *different* subviews; the chat room documents this at `ChatRoomView.swift:91` and `:272`. A second `.sheet` on the same view silently never presents.
6. **Sheets declare detents** — `.presentationDetents([...])` and `.presentationDragIndicator(.visible)`. Prefer a content-derived height over an eyeballed constant so the sheet stops at its content.
7. **A picker cannot be presented over a live sheet.** Park the choice in state, dismiss the sheet, and promote the picker in the sheet's `onDismiss` — the `pendingAttachment` pattern in `ChatRoomAttachments.swift:11-15`. Presenting directly gets silently dropped by iOS.
8. **VoiceOver** — every icon-only control needs `.accessibilityLabel(String(localizable:))`. Decorative images pass `nil` content. `ZappButton` labels itself from its title; hand-rolled buttons must do it explicitly.
9. **Haptics** — `ZappHaptics.*` on confirmations (`ZappHaptics.sendConfirm()` on send). Don't call `UIImpactFeedbackGenerator` directly.
10. **Previews** — a file that defines a *view* should end in a `#Preview`, in the existing shape: `.applyScreenBackground()`, and every variant shown for a multi-variant component (see `ZappButton.swift:96`). Token/helper files that define no view (`ZappColors`, `ZappType`, `ZappMotion`, `ZappHaptics`, `ZappStringHelpers`) don't need one. Coverage is currently partial — roughly half the `Zapp/` view files still lack a preview — so treat a missing one as backlog, not as a defect worth a standalone fix.

## TCA view conventions

- Views take `@Perception.Bindable var store: StoreOf<Feature>` and wrap the body in `WithPerceptionTracking { }`. Omitting the wrapper breaks observation silently on iOS 16.
- Bindings are `$store.foo.sending(\.fooChanged)`, or an explicit `Binding(get:set:)` when dismissal must send its own action.
- Views are dumb: they send actions, they don't route. Navigation decisions live in the reducer / `RootCoordinator`.
- Scoped child stores present via `.sheet(item: $store.scope(state:action:))`.

## Verify

SwiftLint runs as a build phase and enforces several of these mechanically — no `print`/`debugPrint`/`NSLog`, no string concatenation (use interpolation), TODOs must carry an issue number, 150-char lines, 600-line files, no force unwrapping or implicitly-unwrapped optionals.

```bash
xcodebuild -project secant.xcodeproj -scheme zodl-internal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Note `xcodebuild`'s exit code is lost if you pipe it (`| tail`) — redirect to a file and check `$?`, or grep the log for `** BUILD SUCCEEDED **`.

The build depends on the sibling `../zappMessaging` checkout matching the SHA in `.zapp-deps`; `Scripts/validate-zappmessaging-artifacts.sh` gates it and `cd ../zappMessaging && npm run setup` is the repair.

## When the design system can't cover it

**Stop and ask.** If no component, colour, or asset fits, do not invent a one-off — extend the design system deliberately, with the user's agreement. A bespoke control that duplicates an existing one is the single most common way this system erodes.
