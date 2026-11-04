# Excalidraw

Search for **Excalidraw** in the launcher, or use `oncast://command/excalidraw`.
The command opens the bundled official editor in an Oncast-owned, resizable WebKit window.
Running the command again raises the existing window without reloading the drawing.
A shortcut can be assigned under Settings → Commands.

## Invariants

- `AppCore` owns `ExcalidrawCoordinator`. WebKit is created on first use, never at launch.
- HTML, JavaScript, styles and fonts ship with the app. The editor opens without loading the public
  website, welcome branding, signup offers or promotional buttons.
- WebKit's local asset scheme serves bundled font bytes for text rendering and export. It exposes
  only `.woff2` files inside the resource directory, with cancellable reads off the main actor.
- A compact native titlebar shares the editor's light/dark canvas surface. The editor follows the
  containing window's effective appearance. Reload is in the editor's menu.
- The default persistent `WKWebsiteDataStore` retains the embedded editor's IndexedDB. The wrapper
  saves the scene, attached files and library items through Excalidraw's change callbacks.
- Closing the window releases the web view. Opening it again restores the local drawing.
- Data stored by the earlier public-website view remains untouched. It belongs to a different web
  origin; export/import an `.excalidraw` file to transfer a drawing into the embedded editor.
- Drawing never drags the native window. The titlebar and canvas occupy separate layout areas.
- File inputs use an open sheet. Downloads use a save sheet and a temporary destination, then move
  or replace the chosen file after downloading. Cancelling a sheet cancels that operation.
- Links requesting a new browser window open through the user's default browser.
- Loading errors offer Reload inside the window. Save errors use a friendly status and Oncast's HUD.
  Technical errors are recorded with `Logger`; no alternate site, browser or editor is substituted.

The first opening size is 1200 × 800, with an 800 × 600 minimum. AppKit saves the user's frame.
The window participates in Oncast's existing Dock and close-window lifecycle. ⌘Q closes it when key.
The bundled component has no cloud account or real-time collaboration backend.

## Local AI agent access

Open the editor's menu and choose **AI 에이전트 연결 설정 복사**. Register the copied server entry in a
local MCP client's settings. It launches the bundled native `Contents/Helpers/OncastCanvasMCP`
executable over stdio; Node.js and an API key are not needed to run the server. Use the path copied
by the running app so a development build and an installed build are not confused.

Open Excalidraw in Oncast before calling its tools. The helper connects to the current canvas through
`~/Library/Caches/com.gityeop.tinycast/CanvasMCP/socket`, a Unix-domain socket in a private directory
with mode `0700`; the socket itself has mode `0600`. No TCP port is opened. The listener starts on
first use and stops when Oncast exits. A closed canvas produces an explicit tool error, and no
canvas is opened or activated by an agent request.

| Tool | Behavior |
| --- | --- |
| `read_canvas` | Returns the canvas ID, revision, elements, selected IDs, viewport and file metadata |
| `apply_canvas_changes` | Atomically creates skeletons, updates elements by ID, or deletes IDs |
| `snapshot_canvas` | Returns a PNG and the revision it depicts |
| `export_canvas_scene` | Returns portable Excalidraw JSON including attached files |

Mutations require `canvasId` and `expectedRevision` from `read_canvas`. Content changes advance the
revision; reopening or reloading produces a new canvas ID. A stale version, unknown element, invalid
field, or a second edit already in progress returns an error. The whole batch is validated before
the scene changes. A held pointer or active text edit also prevents agent mutations. A successful
edit is captured in Excalidraw's undo history, committed to local storage before the tool replies,
and announced with an in-editor toast.

Creation accepts `rectangle`, `ellipse`, `diamond`, `text`, `arrow` and `line` skeletons with `x` and
`y`, optional dimensions and styles, `label: {text}`, and arrow `start`/`end` element IDs in the same
creation batch. Updates accept geometry, text and style fields, not internal IDs or versions.
An agent moving connected shapes should include corresponding arrow geometry updates in the batch.

The server implements MCP `2025-11-25` initialization and `2026-07-28` per-request discovery/metadata.
Unknown per-request versions receive an explicit unsupported-version error. The tools expose only this editor;
they do not provide filesystem, shell, credential, or other Oncast-feature access.

## Build and verification

The generated resource folder and license notices are rebuilt with `Scripts/excalidraw/build.mjs`.
See [the asset build instructions](../../Scripts/excalidraw/README.md).

`command-dispatch-test` checks the launch route, and `command-deeplink-test` covers the copied native
address. `excalidraw-test` runs the actual bundled editor, verifies the compact chrome and absence of
promotions, switches between light/dark appearances, and restores a saved drawing after both Reload
and controller recreation. It uses an isolated data store and keeps its test window hidden.

```sh
./Scripts/run-tests.sh excalidraw-test
./Scripts/test-canvas-mcp.sh
```

Manual inspection can show the test window with `ONCAST_TEST_EXCALIDRAW_HOLD_SECONDS=30`. That is an
automated test which later replaces its fixture and closes the window; do not use it for real work.

The MCP check compiles the actual helper and a hidden, isolated editor host, then uses the official
MCP client SDK to discover and call the tools. It checks drawing creation, updates, deletion, PNG and
JSON export, two concurrent agents, revision conflicts, atomic batch rejection, socket permissions,
and current protocol discovery. Install the asset toolchain's dev dependencies before running it.
