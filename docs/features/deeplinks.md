# Command deeplinks

This personal fork opens built-in Tinycast commands through `tinycast://command/<slug>` and adds
**Copy Deeplink** to the launcher's **⌘K** actions menu. Select a built-in or installed extension
command, then use that action or **⇧⌘C**. Paste the resulting address into Leader Key's URL action,
Shortcuts, or another launcher.

## Leader Key

| Action | Tinycast address |
| --- | --- |
| Search Emoji & Symbols | `tinycast://command/search-emoji` |
| Open Camera | `tinycast://command/open-camera` |
| Confetti | `tinycast://command/confetti` |
| Color Picker | `tinycast://extensions/thomas/color-picker/pick-color` |

Color Picker uses the installed Raycast extension and requires extensions to be enabled. Confetti
is a native command in this fork. Existing links for Raycast's camera, emoji picker, and confetti
also resolve to these native commands, including the existing `raycast-x://` camera address and
`tinycast://extensions/raycast/raycast/confetti`.

To test a copied address in Terminal:

```sh
open 'tinycast://command/search-emoji'
```

## Scope and behavior

Every fixed built-in command has a copyable address, including clipboard history, notes, calendar,
settings, and the built-in quick AI actions. A command still uses its normal coordinator, feature
settings, permissions, and confirmation dialogs. Opening a palette or notes deeplink again reveals
the feature instead of toggling it closed.

**Open in Browser** and **Run Shell Command** need the launcher's typed query and have no input-free
deeplink. Native links do not accept query parameters or fragments; malformed or unknown native
commands report an error. User-created quicklinks, snippets, custom commands, and other item catalogs
do not receive command deeplinks in this fork.

Installed extension commands keep their existing [extension deeplink format](extensions.md#deeplinks)
and argument support. Copy Deeplink copies a Tinycast address for that installed command; it does
not include values entered in its argument fields.

`CommandDeepLink` owns native parsing and canonical addresses. `AppCore.handleOpenURL` routes native
commands before extension links, and `LauncherCoordinator` uses the same command dispatch as launcher
activation. `Tests/command-deeplink-test.swift` compiles both shipped parsers and guards the configured
Leader Key routes, copied-command round trips, invalid native inputs, and Color Picker routing.
