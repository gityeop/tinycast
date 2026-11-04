#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CANVAS_TEST_DIRECTORY="$(mktemp -d /tmp/oncast-canvas-check.XXXXXX)"
trap 'rm -rf "$CANVAS_TEST_DIRECTORY"' EXIT
swiftc -swift-version 6 \
    Tinycast/Features/Excalidraw/CanvasProtocol.swift \
    Tinycast/Features/Excalidraw/Helper/CanvasSocketClient.swift \
    Tinycast/Features/Excalidraw/Helper/OncastCanvasMCP.swift \
    -o "$CANVAS_TEST_DIRECTORY/OncastCanvasMCP"
swiftc -swift-version 6 \
    Tinycast/Features/Excalidraw/CanvasProtocol.swift \
    Tinycast/Features/Excalidraw/CanvasSocketServer.swift \
    Tinycast/Features/Excalidraw/ExcalidrawViewController.swift \
    Tinycast/Features/Excalidraw/ExcalidrawAssetsHandler.swift \
    Tinycast/Features/Excalidraw/ExcalidrawWindowChrome.swift \
    Tinycast/Windows/WindowChrome.swift Tests/excalidraw-test.swift \
    -o "$CANVAS_TEST_DIRECTORY/CanvasTestHost"
node Scripts/excalidraw/test-mcp.mjs \
    "$CANVAS_TEST_DIRECTORY/OncastCanvasMCP" "$CANVAS_TEST_DIRECTORY/CanvasTestHost" "$CANVAS_TEST_DIRECTORY/run"
