# Local Firebase configuration

Place each untracked Firebase file at exactly one of these paths:

- `FirebaseConfig/zodl-production/GoogleService-Info.plist`
- `FirebaseConfig/zodl-testnet/GoogleService-Info.plist`
- `FirebaseConfig/zodl-internal/GoogleService-Info.plist`

The build validates `BUNDLE_ID`, copies only the selected target's file into the
app, and succeeds without a file. CI can instead set `ZAPP_FIREBASE_CONFIG_ROOT`
to a directory with the same target subdirectories, or
`ZAPP_FIREBASE_CONFIG_PATH` to one exact file. Never commit these plists.
