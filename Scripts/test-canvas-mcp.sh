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
swiftc -swift-version 6 \
    Tinycast/Platform/ExecutableLocator.swift Tinycast/Platform/ProcessExit.swift \
    Tinycast/Platform/KeychainSecretStore.swift Tinycast/Features/Settings/AppSettingsKey.swift \
    Tinycast/Features/AI/Model/AIConnection.swift Tinycast/Features/AI/Model/AppleIntelligence.swift \
    Tinycast/Features/AI/Model/AITool.swift Tinycast/Features/AI/Model/AIToolServer.swift \
    Tinycast/Features/AI/Model/AIStreamDecoder.swift Tinycast/Features/AI/Model/AIProviderFailure.swift \
    Tinycast/Features/AI/Model/AIThinkTagDecoder.swift Tinycast/Features/AI/Model/AIRequest.swift \
    Tinycast/Features/AI/Model/JSONValue.swift Tinycast/Features/AI/Service/AIProvider.swift \
    Tinycast/Features/AI/Service/AIToolLoopProvider.swift \
    Tinycast/Features/MCP/Model/*.swift Tinycast/Features/MCP/Service/*.swift \
    Tinycast/Features/MCP/Settings/MCPSettingsStore.swift Tinycast/Features/MCP/UI/MCPCoordinator.swift \
    Tinycast/Features/Excalidraw/CanvasMCPServer.swift Tests/canvas-mcp-client-test.swift \
    -o "$CANVAS_TEST_DIRECTORY/CanvasClientTest"
node Scripts/excalidraw/test-mcp.mjs \
    "$CANVAS_TEST_DIRECTORY/OncastCanvasMCP" "$CANVAS_TEST_DIRECTORY/CanvasTestHost" \
    "$CANVAS_TEST_DIRECTORY/run" "$CANVAS_TEST_DIRECTORY/CanvasClientTest"
