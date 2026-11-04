# Embedded Excalidraw

Build the official Excalidraw component into the app's local WebKit editor:

```sh
cd Scripts/excalidraw
npm ci --ignore-scripts
npm run build
```

The generated `Tinycast/Resources/Excalidraw/` folder is committed and copied into the app as a folder
resource. Xcode builds do not require Node.js or network access. Do not edit the generated bundle.
The lockfile pins the editor, React and the asset build toolchain.

The wrapper uses Excalidraw's supported component, menu, theme and change APIs. It supplies no welcome
screen, promotional content or collaboration service. IndexedDB retains drawings, attached files and
library items in the app's WebKit data store. Appearance follows the containing native window.
The native bridge accepts readiness/error messages and copies MCP connection settings. Its fixed
canvas command entry point invokes the editor API through validated requests, with canvas/revision
checks and undoable batches. It exposes no filesystem or credential APIs.

The bundled Swift MCP helper uses stdio and a private per-user Unix-domain socket to reach the open
editor. The official MCP SDK is a development dependency used only by `test-mcp.mjs`, not part of the
shipped server. Run `./Scripts/test-canvas-mcp.sh` from the repository root for an end-to-end check.

`EXCALIDRAW-LICENSE.txt` is the upstream v0.18.1 MIT license. `licenses/Fonts.txt` preserves the font
files' copyright and license name records. The build collects the bundled dependencies' license files
and includes these notices in `THIRD-PARTY-LICENSES.txt` beside the generated assets.
