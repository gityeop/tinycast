# Tinycast Fork

Personal fork of `abue-ammar/tinycast` for invoking native commands from Leader Key.

- Native `tinycast://command/<slug>` links for fixed built-in commands.
- Launcher **⌘K → Copy Deeplink** and **⇧⌘C** for native and installed extension commands.
- Native Confetti with the existing Raycast address retained as an alias.
- External links reveal their destination; ordinary launcher actions and hotkeys keep their behavior.

See [the deeplink reference](docs/features/deeplinks.md) for supported links and their limits.

## Build and run

Requires macOS 26+, full Xcode, and XcodeGen. Select Xcode with `xcode-select` or set
`DEVELOPER_DIR` to its `Contents/Developer` directory, then run:

```sh
./script/build_and_run.sh
```

The script regenerates the project, builds Debug, and launches `build/Build/Products/Debug/Tinycast Fork.app`.
Optional modes are `--verify`, `--debug`, `--logs`, and `--telemetry`.
The default signing identity is ad-hoc. To preserve macOS permission grants across rebuilds,
set `TINYCAST_SIGNING_IDENTITY` and `TINYCAST_DEVELOPMENT_TEAM` to your signing identity and team.
Do not commit your signing credentials.

## Signed Release build

Use Release for the installed app: it enables Hardened Runtime for both the app and its clipboard
helper. The Icon Composer `.icon` bundle is compiled as an app icon rather than copied as loose files.

```sh
./script/build_release.sh 'Developer ID Application: Your Name (TEAM_ID)' TEAM_ID
```

The result is `build/release/Build/Products/Release/Tinycast Fork.app`. The script verifies its
signature, Hardened Runtime and permission entitlements. App Sandbox remains disabled because
Tinycast controls other apps through Accessibility and runs extension shell commands.

To notarize with an existing Keychain profile, submit the signed Release app, then staple and verify
the accepted ticket. Apple Developer agreements must be current before submission.

```sh
ditto -c -k --keepParent 'build/release/Build/Products/Release/Tinycast Fork.app' build/release/Tinycast-Fork-notarization.zip
xcrun notarytool submit build/release/Tinycast-Fork-notarization.zip --keychain-profile YOUR_NOTARY_PROFILE --wait
# Continue only after notarytool reports status: Accepted.
xcrun stapler staple 'build/release/Build/Products/Release/Tinycast Fork.app'
xcrun stapler validate 'build/release/Build/Products/Release/Tinycast Fork.app'
spctl --assess --type execute --verbose=2 'build/release/Build/Products/Release/Tinycast Fork.app'
```

## Separate app and settings

The app is named **Tinycast Fork**, bundle identifier `com.gityeop.tinycast`. It keeps its own
preferences and `~/Library/Application Support/com.gityeop.tinycast` data. It uses the development
update channel, so the upstream updater cannot replace the fork with a release missing these changes.
Copy existing settings and extensions into those locations once if you want to reuse them.

Launching a test URL explicitly avoids relying on another app's scheme registration:

```sh
open -a '/absolute/path/Tinycast Fork.app' 'tinycast://command/search-emoji'
```

Leader Key uses the default handler for `tinycast://`. Set that handler to Tinycast Fork when
switching to it. Camera and Accessibility permissions belong to the fork app separately; grant
only the permissions needed for the functions you use.

## Verification

```sh
./Scripts/run-tests.sh
./Scripts/lint.sh
```

The native deeplink harness compiles the shipped parser and checks configured Leader Key links,
all copied fixed-command addresses, invalid inputs, and unchanged extension routing.
