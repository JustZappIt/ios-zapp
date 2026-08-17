# Security Policy

Zapp is a cryptocurrency wallet. We take security reports seriously and
appreciate responsible disclosure.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report Zapp-specific security issues privately via GitHub's
["Report a vulnerability"](https://github.com/JustZappIt/ios-zapp/security/advisories/new)
(Security advisories) on this repository.

For vulnerabilities in the upstream Zcash Swift SDK, please follow the upstream
[Responsible Disclosure guidelines](https://github.com/zcash/ZcashLightClientKit/blob/master/responsible_disclosure.md).

## Scope

In scope: the Zapp app code in this repository, including the wallet, P2P
messaging integration, and off-ramp flows.

Out of scope: third-party services (p2p.me, NEAR intents, lightwalletd
operators), the upstream Zcash Swift SDK, and the Bare/Hyperswarm runtime.
Please report those to their respective maintainers.

## Handling of secrets

No API keys, credentials or key material are committed to this repository.
Integration keys live in `secant/Resources/PartnerKeys.plist`, Firebase
configuration in `GoogleService-Info.plist`, and App Store Connect credentials
in `fastlane/.env` and a `.p8` key — all four are gitignored and none has ever
been committed. If you believe you have found committed key material, please
report it through the private advisory link above rather than opening an issue.
