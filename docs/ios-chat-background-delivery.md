# iOS chat background-delivery design

## Status and parity target

Foreground/cold-open delivery and sender durability can be implemented entirely
in the app and `zappMessaging`. True background delivery cannot: APNs has no
client-side equivalent of Firebase topic subscription, so an authenticated
provider must map device tokens to opaque Hypercore topics and send the APNs
doorbell. No production provider URL, authentication scheme, APNs key, bundle
environment, retention policy, or user opt-in decision exists in this checkout.

Until those choices are supplied, iOS parity is:

- the same authoritative encrypted Hypercore data as Android;
- local Hypercore append before a send reports success;
- deterministic resume and pull when the app becomes active;
- no claim of background notification parity.

This deliberately stops short of registering for remote notifications: doing so
without a working reconciliation backend creates a misleading permission prompt
and a token that cannot receive a chat doorbell.

## Proposed routing model

The SDK remains the only component that derives inbound topics. After identity
and conversations hydrate, the app reads the complete `getPushTopicSnapshot()`
and reconciles it with a Zapp-operated registration service:

```text
iOS app -- device token + opaque topic set --> registration service
blind peer -- proof-backed topic doorbell --> registration service --> APNs
iOS app <-- contentless, signed/versioned topic hint -------------------
```

The provider stores an installation-scoped token and opaque topic membership,
not identity keys, contact names, conversation IDs, message content, or media.
Registration requests must be authenticated with a per-install key and protected
against replay. The blind peer/provider boundary must accept a doorbell only
after verifying the proof for the appended block, matching the current SDK
`sendNotification(core,index)` boundary.

APNs payloads contain only a schema version, an opaque topic digest, a random
doorbell ID, and `content-available: 1`. They never contain message text,
participant identity, conversation ID, or a block. A topic is an untrusted hint;
the app ignores topics absent from its latest local snapshot and never constructs
a chat message from notification data.

## Device behavior

For an allowed silent wake, the app starts or resumes messaging, waits within a
strict background budget for authoritative encrypted replication, persists new
rows, and posts one generic local notification such as “New chat activity.” It
then suspends only if the application is still backgrounded. If the pull cannot
finish before expiration, it records a retryable diagnostic and may post the
same generic notification so opening the app completes the pull. Foreground
doorbells trigger reconciliation but no duplicate local notification.

Doorbell IDs and the newest observed per-topic cursor are retained in a bounded,
expiring store to suppress duplicate notifications. APNs collapse IDs may reduce
wakes but are not correctness state. All execution is bounded; no keepalive,
background socket, or iOS analogue of Android FOSS `ChatWakeService` is proposed.

## Reconciliation and privacy rules

- Reconcile only a complete snapshot with `hydrated == true`. An incomplete
  snapshot may add nothing and must never remove server subscriptions.
- Atomically publish the new local routing set before remote additions, and
  remove local routing before remote unsubscribe. A delayed stale hint is then
  ignored.
- Reconcile on token rotation, identity restore, reinstall, conversation add or
  removal, explicit leave/block, push-topic change, and notification opt-in
  change. Deleting a wallet removes the installation and every topic.
- Blocked-sender filtering occurs against authoritative local conversation data
  after pull. Payloads and logs never expose full topics, tokens, keys, content,
  or identities; diagnostics use short non-reversible hashes.
- User notification authorization and background delivery are explicit product
  choices. Disabling either removes provider subscriptions and the local routing
  map.

## Platform limits

- A user force-quit prevents silent-push launch until they manually reopen the
  app. Delivery then occurs through the normal persisted-cursor catch-up path.
- `AfterFirstUnlockThisDeviceOnly` data is available while locked after the first
  unlock. Before the first unlock following reboot, the wake records no secret,
  performs no pull, and falls back to delivery after unlock/open. Key protection
  must not be weakened to avoid this limit.
- APNs background execution is opportunistic and can be throttled. A doorbell is
  neither message transport nor proof of delivery.

## Required tests

Provider contract tests cover token rotation, complete-set reconciliation,
removal, replay, forged topics, and retention. iOS tests cover disabled
notifications, blocked sender, duplicate doorbell, foreground suppression,
expiration, pre-first-unlock, force-quit documentation, and wallet deletion.
Device verification must include a backgrounded receiver, an offline sender,
authoritative pull, a generic notification, and opening directly to the already
persisted message.

## External decisions required to implement

1. Production/staging registration-service URLs and ownership.
2. Installation authentication and abuse/rate-limit policy.
3. APNs team/key IDs, signing-key custody, bundle/environment mapping, and CI
   secret provisioning.
4. Topic/token retention and deletion SLA.
5. Whether notification permission and background delivery are opt-in, plus the
   exact generic fallback copy.
6. Whether the existing blind-push gateway will route both FCM topics and APNs
   installations, or a separate provider will consume proof-backed doorbells.

Implementation of APNs registration and wake handling is blocked until these are
resolved; inventing defaults would not create a deployable or testable parity
path.
