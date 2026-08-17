# Zapp for iOS

Zapp is a privacy-first Zcash wallet with an end-to-end encrypted peer-to-peer messenger built
into it. Shielded ZEC for the money, Hyperswarm for the messages, and a peer-to-peer offramp for
spending in local currency. No account, no custody, no tracking.

Zapp for iOS is a fork of [Zodl](https://github.com/zodl-inc/zodl-ios), itself a fork of Electric
Coin Company's [Zashi](https://github.com/Electric-Coin-Company/zashi-ios). The fork diverged at
upstream commit [`0d3b93ad`](https://github.com/zodl-inc/zodl-ios/commit/0d3b93ad9ced06e76fa7e65be27437712984296b)
and carries its own line of development on top of it.

The Android counterpart lives at [JustZappIt/zapp-android](https://github.com/JustZappIt/zapp-android).

## What is different from upstream

- **Encrypted P2P chat.** Direct and group messaging over Hyperswarm, with identities derived from
  the wallet seed. No Zapp server can read your messages: a project-run blind peer stores encrypted
  blocks so they reach a recipient who was offline, and it cannot decrypt them.
- **A peer-to-peer offramp.** Pay a merchant in local currency out of shielded ZEC, through the
  p2p.me contracts on Base.
- **A unified send-and-swap screen.** One screen sends ZEC or swaps it for another asset through
  NEAR intents, with the recipient prefilled wherever Zapp already knows it.
- **A different shell and visual system.** Zapp's tabbed shell (`ZappTabsView`, `ZappPayView`) and a
  Swiss-minimalist token set, layered on top of upstream's design system rather than replacing it.

Everything else is deliberately kept in lockstep with upstream: target names, scheme names, the
`secant` / `zodl` file and module naming, and the build-flag prefixes all stay as `zodl-ios` has
them so that future upstream merges stay cheap. That is why the Xcode project is still
`secant.xcodeproj` and the build flags are still `SECANT_MAINNET` / `SECANT_TESTNET`.

## Features

- Shielded-by-default Zcash send and receive, with unified, transparent and shielded addresses
- Ironwood (NU6.3) support, including a guided migration that moves Orchard funds into the new
  shielded pool in standard-sized pieces over time
- Transaction history, filters, notes and tax export
- Address book, with the same records backing chat contacts
- Encrypted chat: DMs, groups, media, read receipts, payment requests
- Keystone hardware-wallet signing over animated QR
- Swaps to and from shielded ZEC through NEAR intents
- Tor routing for exchange-rate lookups, transaction submission and integrations, with a settings
  toggle to turn it off
- English and Spanish

## Building

### Known limitation: this cannot be built outside the org today

`secant.xcodeproj` references `../zappMessaging/ios` as a **local** Swift package
(`XCLocalSwiftPackageReference`), so that sibling checkout is a build prerequisite, not an optional
convenience:

```
<some-dir>/
  ios-zapp/            <-- this repository
  zappMessaging/       <-- required, currently private
  zcash-swift-wallet-sdk/  <-- required, public (zcash/zcash-swift-wallet-sdk)
```

[`JustZappIt/zappMessaging`](https://github.com/JustZappIt/zappMessaging) is **private at the time
of writing**. Xcode fails to resolve packages if it is missing, and there is no flag that stubs the
messaging package out, so people outside the JustZappIt org cannot currently build this project. CI
works only because it checks the repository out with a read token. This is a known limitation,
stated here rather than worked around.

The messaging runtime itself is open source at
[JustZappIt/zappmessaging-sdk](https://github.com/JustZappIt/zappmessaging-sdk).

### Prerequisites

- Xcode matching [`.xcode-version`](.xcode-version)
- [SwiftGen](https://github.com/SwiftGen/SwiftGen) — `brew install swiftgen`
- [SwiftLint](https://github.com/realm/SwiftLint) **0.50.3** specifically — install from the
  [official 0.50.3 package](https://github.com/realm/SwiftLint/releases/download/0.50.3/SwiftLint.pkg)

Both run automatically as Xcode build phases. On Apple Silicon, if you installed either via
Homebrew, symlink it so the build phase can find it:

```
ln -s /opt/homebrew/bin/swiftgen /usr/local/bin
ln -s /opt/homebrew/bin/swiftlint /usr/local/bin
```

### First build

```bash
Scripts/bootstrap-zappmessaging.sh   # clones/pins the sibling and generates its artifacts
open secant.xcodeproj
```

Re-run `bootstrap-zappmessaging.sh` whenever you pull JS changes in `zappMessaging` — the build
otherwise links a stale `worklet.bundle` with no warning at all.

### Schemes

| Scheme | Network | Notes |
|---|---|---|
| `zodl-internal` | mainnet (ZEC) | internal/development build; also runs the `zodlTests` target |
| `zodl-testnet` | testnet (TAZ) | |
| `zodl-AppStore` | mainnet (ZEC) | production / App Store build |

### Partner keys

Integrations read their keys from `secant/Resources/PartnerKeys.plist`, which is **gitignored and
never committed**. Archive builds fail without it — see
[`Scripts/validate-partner-keys.sh`](Scripts/validate-partner-keys.sh) for the required keys.
Normal debug builds run fine without the file; the affected integrations are simply inert.

### Vendored binary

`Vendor/ZappOfframp.xcframework` is a compiled artifact, not third-party closed source. It is the
Kotlin Multiplatform `offramp-lib` module built for the `iosMain` target; its source is public in
[zapp-android](https://github.com/JustZappIt/zapp-android/tree/main/offramp-lib).

## Testing

Run the `zodlTests` target via the `zodl-internal` scheme. All tests use
[Swift Testing](https://developer.apple.com/documentation/testing) with TCA's `TestStore`.

## Contributing

Please read the [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CONDUCT.md).
[AGENTS.md](AGENTS.md) documents the architecture, conventions and invariants that reviews enforce —
read it before your first change. Further documentation is in [docs/](docs/README.md).

## Security

Please do not open a public issue for security vulnerabilities. See [SECURITY.md](SECURITY.md) for
how to report one.

## License

MIT, with Zapp-original contributions additionally available under Apache 2.0. See
[LICENSE](LICENSE) and [NOTICE](NOTICE).
