# Zapp iOS — Phase 1: Rebrand Skeleton + Zapp Swiss Design System

Fork baseline: `zodl-ios` @ `0d3b93ad` (main). Branch: `feature/zapp-phase1-rebrand`.
Mirrors the Android fork policy in `android-zapp/CLAUDE.md` and the design spec in
`android-zapp/.claude/skills/zapp-style/design-system.md`.

Scope was brand identity + visuals only. No reducer, dependency-client, SDK, or
navigation code was touched. All deep technical identifiers are retained by design:
the `secant` project/folder name, `SECANT_MAINNET` / `SECANT_TESTNET` / `SECANT_DISTRIB`
compile flags, the `zodl-internal` / `zodl-testnet` / `zodl-AppStore` scheme and target
names, `Zashi*` / `Design.*` component and token symbol names, SwiftGen `L10n` keys
(e.g. `accounts.zashi`, `keepZodlOpen*`), keychain constants, and the
`co.electriccoin.power_wifi_sync` / `co.electriccoin.scheduler` BG task identifiers.

## A. Rebrand surface

### Bundle identifiers (per target, all three build configurations each)

| Target | Old | New |
|---|---|---|
| `zodl-production` | `co.electriccoin.secant-mainnet` | `xyz.justzappit.zapp` |
| `zodl-testnet` | `co.ecc.zashi-testnet` | `xyz.justzappit.zapp.testnet` |
| `zodl-internal` | `co.electriccoin.secant-testnet` | `xyz.justzappit.zapp.internal` |
| `zodlTests` | `co.electriccoin.zodlTests` | `xyz.justzappit.zapp.tests` |

This mirrors Android's side-by-side namespace (`xyz.justzappit.zapp` mainnet /
`xyz.justzappit.zapp.testnet`) and no longer collides with any ZODL install.

### Display names (CFBundleDisplayName, per flavor Info.plist)

| Info.plist | Old | New |
|---|---|---|
| `secant-distrib-Info.plist` (production) | Zodl | Zapp |
| `zashi-internal-Info.plist` (internal) | Zodl Internal | Zapp [INT] |
| `secant/zashi-testnet-Info.plist` (testnet) | Zodl Testnet | Zapp [TN] |
| `secant/secant-mainnet-Info.plist` (legacy, not wired to any target) | Zodl | Zapp |
| `secant/secant-testnet-Info.plist` (legacy, not wired to any target) | Zodl Testnet | Zapp [TN] |

The bracket labels mirror Android's launcher labels ("Zapp [DFT]" / "Zapp [DFM]").

### Other plist/entitlement identity

- iCloud container `iCloud.com.electriccoinco.zashi` → `iCloud.xyz.justzappit.zapp` in all
  three entitlements files (`zashi-internal`, `secant-distrib`, `secant-mainnet`) and the
  `NSUbiquitousContainers` plist keys. **The container must be registered in the Zapp
  App Store Connect account before device/distribution signing will pass.**
- `CFBundleURLName` `co-electriccoin.secant-mainnet` → `xyz.justzappit.zapp` (the `zcash`
  URL scheme itself is a payment-protocol identifier and stays).
- `NSUbiquitousContainerName` "Zashi Internal" / "Zashi Address Book" → "Zapp Internal" /
  "Zapp Address Book".
- Kept: BG task ids and `applinks:secant.flexa.link` associated domain (Flexa feature,
  out of scope). Signing now uses Zapp Apple Developer team `63UVRFCV97`.

### App name in strings

- `secant/Resources/Localizable.xcstrings`: 130 localized string values (en + es)
  renamed Zodl/ZODL → Zapp. Keys unchanged, so the committed SwiftGen `L10n` output
  stays valid. Three values intentionally keep "Zodl":
  - `keystone.drawer.banner.desc` (the Keystone promo code is literally "Zodl")
  - `coinVote.pollsList.approvedByZodl`, `coinVote.results.approvedByZodl`
    ("Approved by Zodl" names the endorsing entity — the endorsement list is fetched
    from Zodl's bundled voting service config, so renaming it would be false)
- `secant/Resources/WhatsNew/whatsNew.json` + `whatsNew_es.json`: 4 occurrences each.
  Note: the historical "Zashi -> Zodl branding update" release note now reads
  "Zashi -> Zapp"; the WhatsNew history likely wants a fresh Zapp entry in a later phase.
- Left pointing at Zodl properties (external resources, need Zapp equivalents before
  release): `support@zodl.com` (`SupportDataGenerator.swift`), `https://zodl.com/...`
  privacy-policy/terms URLs in feature views.

### App icons and brand art

All generated from `zappLogos/zapp-logo-1024.png` (white Z-slash on orange) plus the
bundled Inter-Black for the wordmark. Full-quality final art can be dropped in over the
same filenames; Contents.json files were not touched.

- `AppIcon.appiconset` (production): Zapp mark, white on accent `#FF9417`, 25 sizes, opaque.
- `AppIcon-internal.appiconset`: same mark on charcoal `#15120D` — distinguishable placeholder.
- `AppIcon-testnet.appiconset`: same mark on green `#2F9D6A` — distinguishable placeholder.
- `ZashiLogo.imageset/logoTransLight.png`: Z-mark alpha mask (all call sites tint via
  `.renderingMode(.template)`).
- `zashiTitle.imageset/zodlTitle.png`: "Zapp" wordmark, Inter Black (template-tinted).
- `WelcomeScreenLogo.imageset` (4 files): Z-mark + "Zapp" lockup, black for light, white for dark.
- `icons/zashiLogoSq.imageset`, `icons/zashiLogoSqBold.imageset`: Z-mark masks.
- `ZashiLogoWithBackground.imageset`: full square logo on exact accent.
- **Not touched:** `Brandmarks/*` (these are Zcash/ZEC currency marks, not app brand),
  `brandmarkKeystone`, `prevZashiLogo` (unused legacy), `zcashZecLogo`.

Placeholders to replace with final art later: the internal/testnet icon color variants,
the welcome lockup, and the wordmark (rendered text, not drawn lettering).

## B. Zapp Swiss design port

### Color ramp recolor (`Colors.xcassets/ZDesign`, 72 colorsets + 3 legacy)

Semantic `Design.*` token names and the token API are unchanged; the raw ramp under them
was re-anchored to the Zapp palette. Android token → anchored iOS colorset → value:

| Android token | iOS colorset (ZDesign) | New value | Resolves through |
|---|---|---|---|
| `c.bg` light | `Base/Bone` | `#FFFFFF` (unchanged) | `Design.Surfaces.bgPrimary` light |
| `c.bg` dark | `Base/Midnight` | `#0F0E0C` | `Design.Surfaces.bgPrimary` dark |
| `c.text` light | `Base/Obsidian`, `Gray950` | `#15120D` | `Design.Text.primary` light |
| `c.text` dark | `Shark50` | `#F6F2EA` | `Design.Text.primary` dark |
| `c.surfaceAlt` light | `Base/Concrete` | `#F4F2EE` | `Design.Surfaces.bgAdjust`, `Btns.Secondary.bg` |
| `c.surfaceAlt` dark | `Shark900` | `#1B1916` | `Design.Surfaces.bgSecondary` dark |
| `c.surfaceInput` light | `Gray50` | `#F6F4F0` | `Design.Inputs.Default.bg` light |
| `c.surfaceInput` dark | `SharkShades06dp` | `#201D19` | elevation shades |
| `c.chipBg` light | `Gray100` | `#EFECE5` | `Design.Surfaces.bgTertiary` light |
| `c.border` light | `Gray200` | `#EBE7E0` | `Design.Surfaces.strokePrimary` light |
| `c.border` dark | `Shark800` | `#2A2622` | `Design.Surfaces.strokeSecondary` dark |
| `c.borderStrong` light | `Gray300` | `#D9D4CA` | `Design.Inputs.Filled.stroke` light |
| `c.borderStrong` dark | `Shark700` | `#3A342D` | `Design.Surfaces.strokePrimary` dark |
| `c.textSubtle` light | `Gray400` | `#9A9288` | icon tints |
| `c.textSubtle` dark | `Shark600` | `#726A60` | `Design.Text.disabled` dark |
| `c.textMuted` light | `Gray600` | `#6B645A` | `Design.Text.quaternary` light |
| `c.textMuted` dark | `Shark400` | `#A59C90` | `Design.Text.support` dark |
| `c.accent` | `Base/Brand`, `Brand500` | `#FF9417` | `Design.Surfaces.brandPrimary`, `Btns.Primary.bg`, `Btns.Brand.bg` |
| `c.accentSoft` light | `Brand100` | `#FFE7CC` | `Design.Utility.Brand._100` |
| `c.accentSoft` dark | `Brand950` | `#3A2713` | `Design.Utility.Brand._950` dark side |
| `c.accentText` light | `Brand700` | `#A65500` | `Design.Utility.Brand._700` |
| `c.accentText` dark | `Brand300` | `#FFB26B` | `Design.Utility.Brand._300` |
| `c.onAccent` light | `Base/Bone` | `#FFFFFF` | `Btns.Primary.fg` light |
| `c.onAccent` dark | `Base/Obsidian` | `#15120D` (spec `#1A140B`, nearest token) | `Btns.Primary.fg` dark |
| `c.danger` light | `ErrorRed500` | `#D94545` | `Design.Text.error` light |
| `c.danger` dark | `ErrorRed300` | `#EF6A5F` | `Design.Text.error` dark |
| `c.dangerSoft` light | `ErrorRed100` | `#FDE2E0` | destructive surfaces |
| `c.dangerSoft` dark | `ErrorRed950` | `#2E1A18` | destructive surfaces dark |
| `c.success` light | `SuccessGreen500` | `#2F9D6A` | status indicators |
| `c.success` dark | `SuccessGreen400` | `#5FD49C` | status indicators dark |
| `c.successSoft` light | `SuccessGreen100` | `#D7F0E3` | chips |
| `c.successSoft` dark | `SuccessGreen950` | `#1A2E24` | chips dark |

Intermediate ramp steps (Gray500/700/800/900, Shark100–300/500, Brand200/400/600/800/900,
ErrorRed/SuccessGreen 200–900) were interpolated in the same warm hue family so every
existing semantic pairing keeps a monotonic light/dark relationship. `SharkShades*dp`
elevation shades were re-derived from `#0F0E0C` → `#2A2622`.

Untouched ramps (no Zapp analog in the spec, kept for upstream compatibility):
`Espresso*`, `WarningYellow*`, `HyperBlue*` (links), `Indigo*`, `Purple*`, `Base/Black`,
`Base/Espresso`, and the legacy root palette except `splash`, `launchScreenBcg`, and
`background` (dark), which were re-anchored to `#0F0E0C`.

### Semantic re-maps in `DesignSystem.swift`

Only where the Zapp spec assigns a different role (every changed token supplies both
light and dark via `Design.col`):

- `Btns.Primary`: bg `obsidian/bone` → `brand/brand` (accent CTA), fg → `bone/obsidian`
  (= onAccent), bgHover → `brand600/brand600`. Realizes "accent is the single CTA color".
- `Btns.Brand`: bg `brand400` → `Base.brand`, fg `obsidian/obsidian` → `bone/obsidian`
  (spec: `onAccent` on full accent, not `accentText`).
- `Btns.Secondary`: bg → `concrete/shark900` (surfaceAlt block), border re-mapped to the
  background color so the button renders borderless per the `ZappButton` Secondary spec
  without restructuring `ZashiButton`.
- `Design.Radius`: every token (`_xxs` … `_full`) now resolves to 0 — one overlay edit
  flattens all 207 token call sites (buttons, cards, sheets incl.
  `presentationCornerRadius`, text fields, badges).

### Corner pass (raw literals outside the token system)

40 call sites flattened to 0 / `Rectangle()`:

- UIComponents: `Tooltip`, `MessageEditor`, `NoTransactionPlaceholder`,
  `NoChainPlaceholder`, `FloatingArrow` (was misusing `Spacing._md` as a radius; now
  uses `Radius._md`).
- Features: `SmartBannerView` (top/bottom curved banner shapes → flat),
  `PollsListView`, `ProposalListView`, `DelegationSigningStore`, `ResultsView`,
  `ConfirmSubmissionView`, `NoRoundsView` (Capsules → `Rectangle()`),
  `AnnotationSheet`, `TransactionDetailsView`, `ScanView` (QR frame),
  `WhatsNewView`, `WalletBalancesView`, `ServerSetupView`, `SendFeedbackView`,
  `SwapAndPayForm`, `SwapForm`.

Deliberately kept round (no clean sharp-corner analog on iOS, or non-brand):
`Circle()` shapes (avatars, radio indicators, progress spinners, QR finder dots) and
`CircularProgressIndicator` equivalents — the Android spec itself keeps circular
loading indicators. Revisit avatars in a later phase if Zapp wants square ones.

### Typography

Inter Black was already bundled; no font additions or plist/swiftgen changes needed.

- `ZashiFont.swift` `fontName`: the semantic `.semiBold` weight now resolves to
  Inter-Black (`.semiBoldItalic` → BlackItalic). One overlay edit turns all 186
  heading/title/CTA call sites Black-weight per the spec, without touching call sites.
- `ZashiButton.swift`: hardcoded `Inter.semiBold` label → `Inter.black`
  (spec: `.button` is Black).
- `.medium` (215 sites) and `.regular` intentionally unchanged: they carry body copy
  and row subtitles, which the Zapp scale keeps at Normal weight. The Compose spec's
  10–11sp Black eyebrow/chip micro-styles have no dedicated iOS token; screens adopt
  them ad hoc in later phases.

### Spec items with no iOS analog in Phase 1 (explicitly out)

- `Box + clickable` (Compose) — iOS keeps `Button`-based `ZashiButton`; visual parity
  achieved via tokens, no structural rewrite.
- Bottom-left back dock — navigation-structure change, out of Phase 1 scope.
- `ZappFab`, `OnbScreen`, ghost numbers, eyebrow/progress components — screen-level
  patterns for later feature phases.
- Edge-to-edge inset rules — Android-specific (API 35 mandate).

## C. Upstream files touched beyond the branding/token surface (for sync review)

Feature files touched by the corner pass only (one-line radius/shape literals):
`SmartBannerView`, `PollsListView`, `ProposalListView`, `DelegationSigningStore`,
`ResultsView`, `ConfirmSubmissionView`, `NoRoundsView`, `AnnotationSheet`,
`TransactionDetailsView`, `ScanView`, `WhatsNewView`, `WalletBalancesView`,
`ServerSetupView`, `SendFeedbackView`, `SwapAndPayForm`, `SwapForm`.
Plus `ZashiButton.swift` (font name) and `ZashiFont.swift` (weight resolution) in
UIComponents. Everything else is assets, plists, entitlements, pbxproj bundle ids,
xcstrings values, WhatsNew json, `DesignSystem.swift`, and this note + CHANGELOG.

## D. Verification

- BUILD_RESULT_PLACEHOLDER
- SwiftGen/SwiftLint are not installed on this machine. Both build phases degrade to
  warnings when the binaries are absent, and upstream ships the `swiftlint lint`
  invocations commented out in the build phase, so the phase passes vacuously.
  No asset/color/string **keys** changed, so the committed SwiftGen outputs remain
  correct without regeneration. A human with SwiftLint 0.50.3 installed should run the
  lint config once over the touched Swift files.
- Side-by-side install: bundle ids no longer overlap any ZODL id; simulator
  verification pending.
