# Oncast

A native macOS launcher maintained by **Sang Yeop Lim**. Oncast adds native command deeplinks,
**⌘K → Copy Deeplink**, Confetti, and a graphite icon with a white glitch O.

SwiftUI + AppKit, macOS 26+, Swift 6. It runs as a menu-bar accessory and executes Raycast
extensions natively in JavaScriptCore.

- **Website:** [byyeop.com](https://byyeop.com)
- **Source code:** [Oncast](https://github.com/gityeop/tinycast/tree/native-deeplinks)
- **Feedback:** [GitHub Issues](https://github.com/gityeop/tinycast/issues)
- **Support development:** [Ko-fi](https://ko-fi.com/yeopmac)

## Features

App launching, global and per-app hotkeys, clipboard history, calculator, notes, snippets,
quicklinks, window management, file search, calendar, emoji and symbols, camera preview,
AI chat, quick actions, and Raycast extensions.

## Deeplinks

```text
oncast://command/search-emoji
oncast://command/open-camera
oncast://command/confetti
```

Native and installed extension commands expose **Copy Deeplink** in the launcher action menu.
Existing `tinycast://` and Raycast addresses remain accepted, so existing Leader Key shortcuts
continue to work. See [supported deeplinks](docs/features/deeplinks.md).

## Build and run

Install full Xcode and XcodeGen, then select Xcode with `xcode-select` or `DEVELOPER_DIR`:

```sh
./script/build_and_run.sh
```

The app builds as `Oncast.app`. See [FORK.md](FORK.md) for signing, notarization, verification,
and existing settings. The bundle identifier remains `com.gityeop.tinycast` to reuse the fork's
preferences and permission grants. Upstream automatic updates are disabled.

## License and attribution

Oncast is based on [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar and remains
licensed under [AGPL-3.0](LICENSE). Original copyright and third-party notices are retained in
[NOTICE.md](NOTICE.md), which is included in the app bundle.
