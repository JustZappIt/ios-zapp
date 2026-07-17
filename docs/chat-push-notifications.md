# Chat push notifications

Zapp chat notifications are contentless doorbells. A sender appends the encrypted
message to Hypercore, `blind-peering.sendNotification()` forwards an encrypted
blind-push v3 proof through the blind peer and gateway, and FCM delivers a fixed
generic APNs alert. Firebase and APNs are not message stores or sources of truth.

The notification path must never contain plaintext chat text, contact or
conversation names, identity keys, wallet data, encryption keys, receipts,
history, or delivery state. The only variable application field is the encrypted
blind-push envelope. The title and body are always `Zapp` and `New private
message`.

Receiving a doorbell does not start Bare, Hyperswarm, replication, a processing
task, or any other background chat work. Tapping a validated notification opens
Zapp; the normal foreground worklet resume and Hypercore synchronization fetch
and authenticate the message. A notification-service extension is intentionally
not used.

## Apple and Firebase configuration

Each app has its own Firebase Apple app and untracked configuration:

| Target | Bundle ID | Default local plist |
| --- | --- | --- |
| `zodl-production` (`zodl-AppStore` scheme) | `xyz.justzappit.zapp` | `FirebaseConfig/zodl-production/GoogleService-Info.plist` |
| `zodl-testnet` | `xyz.justzappit.zapp.testnet` | `FirebaseConfig/zodl-testnet/GoogleService-Info.plist` |
| `zodl-internal` | `xyz.justzappit.zapp.internal` | `FirebaseConfig/zodl-internal/GoogleService-Info.plist` |

The build phase accepts either `ZAPP_FIREBASE_CONFIG_PATH` for one explicit file
or `ZAPP_FIREBASE_CONFIG_ROOT`, containing one target-named directory per row
above. The repository-local `FirebaseConfig` directory is the final lookup path.
CI should materialize these files from its secret store immediately before the
build and remove them afterwards. They are ignored by git and must not be
committed.

The copy script verifies that the plist's `BUNDLE_ID` matches the target. At
runtime Zapp also verifies the bundle ID, Firebase project `zapp-b3154`, and FCM
sender ID. A missing or mismatched plist is supported: the app continues running
and only chat push is unavailable.

All three targets use explicit Firebase delegate handling with automatic app
delegate proxying disabled. Push Notifications and the appropriate signed
`aps-environment` entitlement must be provisioned for every Apple app ID. Debug
configurations request the development environment and Release configurations
request production.

## Client behavior

Users opt in from the explicit Chat Notifications setting. Zapp requests
alert/sound/badge authorization, registers with APNs, connects the APNs token to
FCM, and handles FCM token refresh. Tokens are used only by Apple/Firebase client
SDKs and are never uploaded to a Zapp server.

JavaScript's `getPushTopicSnapshot()` is the only topic authority. The Swift
client subscribes only to hydrated, ready direct-conversation bindings, excludes
blocked writers, persists successful bindings/subscriptions, removes stale
topics, and reasserts desired topics after token refresh. It retains persisted
subscriptions while a snapshot is unhydrated. Groups are unsupported. Turning
notifications off removes every subscription.

Incoming notifications are accepted only when the FCM sender, topic form,
blind-push version/structure/size, discovery key, APNs structure, and fixed alert
text all match. Unknown but valid topics route safely to the chats list. Known
taps route to the conversation. A blocked writer or the currently visible
conversation suppresses a foreground alert. Logs contain only static operational
messages, never topics, tokens, payloads, identities, or message content.

## Verification

Prepare the shared messaging SDK first:

```bash
cd /Users/chinmaygopal/dev/zapp/zappMessaging
npm ci
npm run setup
npm test
```

Build and test with an explicit simulator destination appropriate to the host:

```bash
cd /Users/chinmaygopal/dev/zapp/ios-zapp
xcodebuild -project secant.xcodeproj -scheme zodl-AppStore -configuration Debug -destination '<simulator>' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project secant.xcodeproj -scheme zodl-testnet -configuration Debug -destination '<simulator>' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project secant.xcodeproj -scheme zodl-internal -configuration Debug -destination '<simulator>' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project secant.xcodeproj -scheme zodl-internal -configuration Debug -destination '<simulator>' test
```

Repeat signed Release builds for physical devices using the JustZappIt team. For
each archive, verify the application identifier and entitlement:

```bash
codesign -d --entitlements :- '<archive>/Products/Applications/Zapp.app'
```

Confirm that `aps-environment` is present and correct. Inspect each built app to
confirm it contains either no Firebase plist (push-disabled test) or exactly its
matching plist and bundle ID. Decode a captured gateway request in a controlled
test environment and verify that it contains only the fixed alert, encrypted
blind-push payload, and transport metadata—never plaintext chat data.

## Physical-device acceptance

1. Install a compatible Android sender and a physical iPhone receiver.
2. Create or restore a fresh direct conversation and confirm reconciliation
   without logging its topic.
3. Background the iPhone normally, lock it, and send from Android.
4. Confirm sender append, blind-peer forwarding, gateway FCM/APNs send, and one
   generic iOS alert.
5. Tap the alert and confirm normal Zapp resume retrieves the authentic Hypercore
   message with no duplicate message or notification.
6. Repeat for a visible active conversation, blocked sender, notifications off,
   restart, and token refresh or reinstall where practical.
7. Confirm gateway and client logs contain no sensitive values.

Apple documents an important platform limitation: if the user force-quits an app
from the multitasking UI, remote notifications may not be delivered until the app
is launched again. Zapp must not promise delivery after force-quit.
