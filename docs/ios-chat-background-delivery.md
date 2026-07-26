# iOS chat notification delivery

## Implemented alert-doorbell path

The existing blind-push gateway already sends one proof-backed Firebase message
to an opaque topic with both Android and APNs alert payloads. Firebase Cloud
Messaging maps each Apple installation to APNs and supports the same client-side
topic subscriptions used by Android. A separate token-registration provider is
therefore not required for the first iOS alert-doorbell release.

```text
zappMessaging derives opaque inbound topics
        |
iOS Firebase installation subscribes to the complete hydrated topic set
        |
blind peer -> blind-push gateway -> FCM -> APNs -> generic visible alert
        |
user opens Zapp -> authoritative encrypted Hypercore replication
```

The app:

- configures Firebase only when a matching `GoogleService-Info.plist` is embedded;
- asks for notification permission only after explicit user opt-in;
- passes the APNs device token to Firebase Messaging;
- subscribes only to `ready` conversations from a complete hydrated push-topic
  snapshot;
- reconciles on topic changes and FCM token rotation;
- removes subscriptions when notifications are disabled or wallet data is
  cleared; and
- displays only the gateway's generic alert. Notification data is never treated
  as a chat message.

Full topics, device tokens, identity keys, contact names, conversation IDs, and
message content must not be logged. Local routing is removed before a remote
unsubscribe so a delayed stale doorbell is not considered current.

## What the first release does not claim

The current gateway payload is an APNs `alert`, not a silent
`content-available` wake. It tells the user there may be new private activity;
opening or foregrounding Zapp performs the authoritative pull. It does not
guarantee that encrypted message data is downloaded before the alert appears.

True silent background ingestion remains a separate future feature. It requires
a background payload and bounded iOS wake handler, has opportunistic execution
and throttling limits, and cannot run after a user force-quits the app. A
doorbell is never message transport or proof of message delivery.

## Required external configuration

1. Enable Push Notifications for the Apple App ID matching each bundle.
2. Create an APNs authentication key and keep the downloaded `.p8` outside the
   repository.
3. Upload that key in Firebase Cloud Messaging with its Apple Key ID and Team ID.
4. Use a provisioning profile containing the Push Notifications entitlement.
5. Deploy the blind-push gateway with the same Firebase project and the matching
   production `apnsTopic`.
6. Verify end to end on a physical iPhone; a simulator build is not an APNs
   delivery test.

Production currently uses `xyz.justzappit.zapp`. Internal and testnet require
their own Firebase config files and matching gateway APNs topics before their
notifications are enabled.
