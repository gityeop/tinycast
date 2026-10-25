# Oncast

Oncast is a personal fork of `abue-ammar/tinycast` for invoking native commands from Leader Key.
It uses a graphite app icon with a white glitch O and cyan/magenta edges.
See [the branding reference](docs/oncast-branding.md) for the icon source and preserved app identity.

Maintainer: Sang Yeop Lim · [Website](https://byyeop.com) ·
[Feedback](https://github.com/gityeop/tinycast/issues) · [Ko-fi](https://ko-fi.com/yeopmac).
App UI uses these destinations; original copyright stays in LICENSE and bundled NOTICE.

- Native `oncast://command/<slug>` links for fixed built-in commands.
- Launcher **⌘K → Copy Deeplink** and **⇧⌘C** for native and installed extension commands.
- Native Confetti with the existing Raycast address retained as an alias.
- Clickable shortcut keys with modifier-side and physical-key / key-equivalent settings.
- External links reveal their destination; ordinary launcher actions and hotkeys keep their behavior.

See [the deeplink reference](docs/features/deeplinks.md) for supported links and their limits.

## Upstream updates — October 8, 2026

Selected changes through upstream `71279c8d` are integrated:

- IME Backspace handling and preferred-language emoji keywords, including Korean.
- Camera preview focus, external Notes edits, microphone mute and chained calculations.
- Launcher shortcuts, aliases and visibility in `settings.json`, including Oncast's side and
  character options.
- Codex web research continuity and AI Chat shortcut toggling. Deeplinks continue to reveal
  the chat window rather than toggle it.
- GitHub extension installation, Store updates, delayed menu-bar null renders, Browser Bookmarks,
  action-panel shortcuts and X.com OAuth lock recovery.

The existing menu-bar activation guard stays in place. Oncast keeps its app identity, signing,
settings paths, native deeplinks and shortcut recorder. Experimental Dictation is not included.

## Upstream updates — October 26, 2026

Selected bug fixes and features through upstream `21f4b901` are integrated:

- Clipboard trimming, stale file previews, and smaller image thumbnails.
- Extension screen cleanup, paste targeting, navigation search state, bundled modules, Docker sockets,
  `createRequire`, SDK 2.8.2 and OAuth redirect handling. OAuth tokens stay in Oncast's Keychain store.
- Notes focus, action-menu focus/click handling, quicklink argument focus, duplicate app installations,
  running-app indicators, AI provider errors, longer Quick Action output, and volume steps.
- File Search uses an out-of-process filename index and FSEvents instead of Spotlight. It requires
  Full Disk Access, searches the home folder by default, and offers editable default ignore patterns.
  File Search remains opt-in and opens its dedicated pane; root-search file rows are not enabled.
- Snippets, Quicklinks, Custom Commands and Calendar events have editors inside the launcher.
  Existing libraries and settings are retained. Use the creation commands or a row's Edit action.

Oncast's native/legacy deeplinks and Any/Left/Right, Pos/Char shortcuts are retained. Hyper Key
expansion, UI localization, experimental Dictation and MCP permission-policy changes are not included.

## Build and run

Requires macOS 26+, full Xcode, and XcodeGen. Select Xcode with `xcode-select` or set
`DEVELOPER_DIR` to its `Contents/Developer` directory, then run:

```sh
./script/build_and_run.sh
```

The script regenerates the project, builds Debug, and launches `build/Build/Products/Debug/Oncast.app`.
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

The result is `build/release/Build/Products/Release/Oncast.app`. The script verifies its
signature, Hardened Runtime and permission entitlements. App Sandbox remains disabled because
Oncast controls other apps through Accessibility and runs extension shell commands.

To notarize with an existing Keychain profile, submit the signed Release app, then staple and verify
the accepted ticket. Apple Developer agreements must be current before submission.

```sh
ditto -c -k --keepParent 'build/release/Build/Products/Release/Oncast.app' build/release/Oncast-notarization.zip
xcrun notarytool submit build/release/Oncast-notarization.zip --keychain-profile YOUR_NOTARY_PROFILE --wait
# Continue only after notarytool reports status: Accepted.
xcrun stapler staple 'build/release/Build/Products/Release/Oncast.app'
xcrun stapler validate 'build/release/Build/Products/Release/Oncast.app'
spctl --assess --type execute --verbose=2 'build/release/Build/Products/Release/Oncast.app'
```

## App identity and existing settings

The app is named **Oncast**, bundle identifier `com.gityeop.tinycast`. Renaming the app keeps
that identifier and accepts existing `tinycast://` URLs, so settings and Leader Key
shortcuts continue to work without migration. New copied links use `oncast://`. It keeps its own
preferences and `~/Library/Application Support/com.gityeop.tinycast` data. It uses the stable update
channel and reads releases only from `gityeop/tinycast`. Tags use `oncast-vMAJOR.MINOR.PATCH`;
`AppVersion` normalizes them to the version stored in the app. Updates are checked daily and through
Check for Updates, and installed only after the user chooses Update Now. Downloaded apps must match
Oncast's bundle ID, version and Developer ID team (`79Q5RV23F9`).
Copy existing settings and extensions into those locations once if you want to reuse them.

Launching a test URL explicitly avoids relying on another app's scheme registration:

```sh
open -a '/absolute/path/Oncast.app' 'oncast://command/search-emoji'
```

Set Oncast as the default handler for `oncast://` and the existing `tinycast://` Leader Key URLs. Camera and Accessibility permissions belong to the fork app separately; grant
only the permissions needed for the functions you use.

## Verification

```sh
./Scripts/run-tests.sh
./Scripts/lint.sh
```

The native deeplink harness compiles the shipped parser and checks configured Leader Key links,
all copied fixed-command addresses, invalid inputs, and unchanged extension routing.
