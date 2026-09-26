# iOS reputation identity checks

Behavioral reference: Android `feature/reputation-identity-checks`, `abac2b0900c1fd3620295946a88489c0660482e9`.

The old iOS framework (`f0cadaa526`) exposed an integrator-only selfie flow and no passport flow. The replacement uses the shared `IdentityVerificationDriver` and `IdentityAttestationSubmitter` for both checks on the ReputationManager. It also adopts the reference's direct buy route and chain-reported reputation limits; the retired integrator selfie tier is no longer offered.

## Dependency

`Vendor/ZappOfframp.provenance.txt` records the exact source commit and hashes for both framework slices. The Apple bridge lives on Android branch `feature/ios-identity-bridge`, based on the reference commit. No unrelated iOS package or sibling dependency pins change. Rebuild using `ZAPP_ANDROID_DIR=<clean checkout> Scripts/vendor-zapp-offramp.sh`.

The Apple bridge and consumed-callback guard are published at `9a5c4e47a` on that branch. Consumed callback URLs are rejected even after sponsorship failure or cancellation; recovery retains the saved attestation and uses the separate verification/retry path.

The Apple bridge adds synchronous, throwing, per-key storage callbacks. Swift stores their opaque records in the existing wallet-scoped ChaChaPoly envelope, with atomic writes and complete file protection. Wallet reset joins native writes before removing these envelopes. Pending sessions, accepted codes, attestations, transaction hashes/nonces, and receipt blocks share this recovery authority.

## Invariants

- Both return paths use the same persisted authorization: nonce/state, check, corridor, expiry, and a key scoped to wallet, chain and ReputationManager contract. Callback query parameters alone never authorize redemption.
- Strict iOS URL parsing rejects wrong schemes/hosts, paths, user information, ports, fragments, missing state, duplicate parameters, and ambiguous code/error results.
- The Apple facade rejects concurrent runs and ignores mismatched live returns without consuming the legitimate return signal. The iOS actor caches one facade for each wallet lifetime.
- Retry invokes the shared recovery path. Unexpired attestations are reused; saved transaction hashes are reconciled; saved receipts retry only their confirmation read.
- The transaction hash and nonce must be durably written before broadcast. Storage failure aborts that broadcast. Lost responses and receipt timeouts retain the existing operation identity.
- Explicit cancellation invalidates an unredeemed browser session. Cancellation after redemption retains recovery data. Kotlin protects the redemption-to-storage handoff from cancellation; Swift explicitly waits for native completion before wallet teardown.

## Validation boundaries

Shared tests use mocked widget HTTP, RPC and submitters. They cover successful completion, wallet/network/contract/check/corridor/state/expiry validation, replay, cold recovery, cancellation, sponsorship failure, lost send responses, receipt timeouts, failed storage writes and failed confirmation reads. Apple bridge tests additionally cover concurrent callbacks/runs and cancellation during redemption with an explicit completion barrier.

Swift Testing exercises callback parsing, encrypted disk persistence/recreation, write failure, reset clearing, reducer completion/retry/dismissal and existing Root routing. These tests do **not** constitute a real browser round trip or a live sponsored transaction.

Final validation on 2026-09-26:

- `zodl-internal` simulator build and 80 tests across six relevant Swift Testing suites passed against the final vendored framework (Xcode 26.6, iOS 26.5).
- Shared Kotlin JVM suite: 591 tests passed. Kotlin lint and device/simulator XCFramework builds passed.
- SwiftLint 0.50.3 ran with both repository configurations. Full lint remains blocked by existing violations (269 app errors and six test errors). Changed app files have the same three errors as their baseline; changed test files have none.
- Validation used an isolated checkout with the repository's existing messaging dependency pin because the original sibling checkout was at a different revision. No sibling checkout or unrelated dependency pin was changed. Simulator validation disabled signing and debug information to fit available disk space.

## Release integration

The callback URLs are `zcash://liveness-return` and `zcash://passport-return`. Both must be allowlisted by p2p.me for the mainnet tenants configured by `IdentityServices.MAINNET`. A live public-session API probe on 2026-09-26, using a dummy wallet address, returned HTTP 400 with `redirect_uri_not_allowlisted` for **both** URLs. They are **not currently allowlisted** for these tenants. No browser verification or transaction was performed. A real iPhone/browser session for each offered check remains a release integration requirement. Liveness is not offered for INR; passport country selection follows the shared corridor table. The shared configuration does not offer these checks on testnet.
