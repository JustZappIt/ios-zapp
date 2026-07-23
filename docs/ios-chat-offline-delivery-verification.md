# iOS chat offline-delivery verification

Verification date: 2026-07-22

## Artifact freshness

Before the fix, the app pinned SDK source commit
`e909fc363b9194b2d3e62ac43e4870c03700851e`, while both the local generated
iOS resource and the latest `Debug-iphoneos` app resource had SHA-256
`065af305362352794b67bb5618c7a0aa6fd8f36db2772c777df36cfeac1cbe09`.
That bundle was 2,266,612 bytes and did not contain the current persisted
`processed cursor` implementation.

The corrected build pins SDK commit
`c8a2e228d602def5b437f3d9857d4ba6728873c5`. Its generated manifest records:

- source tree: `5b7c6f671b84cdb7fccf8e91bc16bcad231f1ef4`
- source dirty: `false`
- package-lock SHA-256: `0f7c174e52042b93ee1f78b1005a8df7f808cbdbc5a085b35d1f9566b3f34ed4`
- bundle SHA-256: `ebd0e597899fb9f2f7d851e476b7bb560cdab3e5b0157f2dce98bb3b6b271d95`
- bundle size: 2,326,374 bytes
- exact addon set: 15 XCFrameworks

The final `Debug-iphonesimulator/zodl-internal.app` resource has the same
`ebd0e597...` SHA-256 and contains `processed cursor`. The marker is only a
diagnostic; the Xcode guard validates the commit, Git tree, clean-source flag,
package lock, bundle hash, and complete addon set.

Removing the manifest was also exercised as a negative check. The guard failed
with:

```text
error: zappMessaging iOS artifacts are stale or missing: worklet-manifest.json is missing
error: Repair with: cd <sibling checkout>/zappMessaging && npm run setup
```

After `npm run setup`, the bootstrap guard and clean app build both passed.

## Automated verification

- `zappMessaging`: `npm test` — 256/256 passing.
- `zappMessaging`: standalone iOS SDK Xcode tests — passing.
- `ios-zapp`: `zodl-internal` simulator build with package-plugin and macro
  validation skipped — passing.
- `ios-zapp`: targeted `MessagingLifecycleOwnerTests` and
  `ChatMessagingParityTests` — passing.

The lifecycle suite covers startup-time state, rapid and deliberately reordered
requests, pending-send flush, expiration, and idempotence. Foreground resume is
issued before the wallet keychain/preparation and low-disk branches, so those
branches cannot suppress chat resume.

## Scope still requiring device and service validation

The code now guarantees local Hypercore append before send success and preserves
a bounded iOS background flush opportunity. A physical two-device offline matrix
was not available in this development environment and must be run before
release.

True background doorbells also require the provider and product decisions listed
in `ios-chat-background-delivery.md`. Until that service exists, iOS reaches
Android's foreground/cold-open authoritative-pull behavior, but it does not claim
background notification parity.
