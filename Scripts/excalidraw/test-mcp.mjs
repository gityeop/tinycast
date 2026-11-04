import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { createInterface } from "node:readline";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const [helper, hostExecutable, directory] = process.argv.slice(2);
const socket = resolve(directory, "socket");
await mkdir(directory, { recursive: true, mode: 0o700 });
const host = spawn(hostExecutable, [], {
  env: { ...process.env, ONCAST_TEST_CANVAS_SOCKET: socket }, stdio: ["ignore", "pipe", "pipe"],
});
let diagnostics = "";
host.stdout.on("data", (data) => { diagnostics += data.toString(); });
host.stderr.on("data", (data) => { diagnostics += data.toString(); });
const hostExit = new Promise((resolve) => host.once("exit", resolve));
const clients = [];
const check = (message) => console.log(`PASS: ${message}`);

async function connect() {
  const client = new Client({ name: "oncast-canvas-verification", version: "1.0.0" });
  clients.push(client);
  await client.connect(new StdioClientTransport({ command: helper, args: ["--socket", socket], stderr: "pipe" }));
  return client;
}

async function call(client, name, args = {}) {
  const result = await client.callTool({ name, arguments: args });
  assert.notEqual(result.isError, true, JSON.stringify(result.content));
  return result;
}

async function read(client) { return (await call(client, "read_canvas")).structuredContent; }

async function verifyModernProtocol() {
  const process = spawn(helper, ["--socket", socket], { stdio: ["pipe", "pipe", "pipe"] });
  const lines = createInterface({ input: process.stdout });
  const iterator = lines[Symbol.asyncIterator]();
  const metadata = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientInfo": { name: "oncast-protocol-test", version: "1.0.0" },
    "io.modelcontextprotocol/clientCapabilities": {},
  };
  async function request(id, method, params) {
    process.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    const line = await iterator.next();
    return JSON.parse(line.value);
  }
  try {
    const discovered = await request(1, "server/discover", { _meta: metadata });
    assert.equal(discovered.result.resultType, "complete");
    assert.ok(discovered.result.supportedVersions.includes("2026-07-28"));
    const listed = await request(2, "tools/list", { _meta: metadata });
    assert.equal(listed.result.tools.length, 4);
    const unsupported = await request(3, "tools/list", { _meta: {
      ...metadata, "io.modelcontextprotocol/protocolVersion": "unsupported-version",
    } });
    assert.equal(unsupported.error.code, -32022);
    const malformed = await request(4, "tools/list", "invalid params");
    assert.equal(malformed.error.code, -32602);
    check("current MCP discovery works and unsupported versions return an explicit error");
  } finally {
    process.stdin.end();
    lines.close();
  }
}

try {
  let ready = false;
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (host.exitCode !== null) throw new Error(`Canvas host exited: ${diagnostics}`);
    try { ready = (await readFile(`${socket}.ready`, "utf8")) === "ready"; } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    if (ready) break;
    await delay(50);
  }
  assert.equal(ready, true, diagnostics);
  await verifyModernProtocol();
  const first = await connect();
  const second = await connect();
  const listed = await first.listTools();
  assert.deepEqual(listed.tools.map((tool) => tool.name).sort(), [
    "apply_canvas_changes", "export_canvas_scene", "read_canvas", "snapshot_canvas",
  ]);
  check("the official MCP client discovers the four canvas tools");
  const initial = await read(first);
  assert.equal(initial.elements.length, 0);
  const created = (await call(first, "apply_canvas_changes", {
    canvasId: initial.canvasId, expectedRevision: initial.revision,
    create: [
      { id: "client", type: "rectangle", x: 100, y: 100, width: 180, height: 90, label: { text: "Client" } },
      { id: "server", type: "rectangle", x: 420, y: 100, width: 180, height: 90, label: { text: "Oncast" } },
      { id: "request", type: "arrow", x: 280, y: 145, width: 140, height: 0, start: { id: "client" }, end: { id: "server" } },
    ],
  })).structuredContent;
  assert.ok(created.revision > initial.revision);
  assert.ok(created.elements.some((element) => element.id === "request"));
  assert.ok(created.elements.some((element) => element.text === "Client"));
  check("MCP creates labeled shapes and an arrow in the live editor");
  const snapshot = await call(first, "snapshot_canvas", { canvasId: created.canvasId });
  const image = snapshot.content.find((content) => content.type === "image");
  assert.ok(image);
  const png = Buffer.from(image.data, "base64");
  assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  await mkdir(resolve("build/verification"), { recursive: true });
  await writeFile(resolve("build/verification/Canvas-MCP.png"), png);
  check("MCP returns a rendered PNG of the actual drawing");
  const current = await read(first);
  const clientLabel = current.elements.find((element) => element.type === "text" && element.text === "Client");
  assert.ok(clientLabel);
  const changed = (await call(first, "apply_canvas_changes", {
    canvasId: current.canvasId, expectedRevision: current.revision,
    update: [
      { id: "client", changes: { backgroundColor: "#a5d8ff" } },
      { id: clientLabel.id, changes: { text: "Agent" } },
    ],
  })).structuredContent;
  assert.equal(changed.elements.find((element) => element.id === "client").backgroundColor, "#a5d8ff");
  assert.equal(changed.elements.find((element) => element.id === clientLabel.id).text, "Agent");
  check("MCP updates existing shape styles and text by ID");
  const conflict = await second.callTool({ name: "apply_canvas_changes", arguments: {
    canvasId: current.canvasId, expectedRevision: current.revision, delete: ["server"],
  } });
  assert.equal(conflict.isError, true);
  assert.match(conflict.content[0].text, /Revision conflict/);
  assert.ok((await read(first)).elements.some((element) => element.id === "server"));
  check("a second agent's stale revision cannot overwrite the drawing");
  const beforeParallel = await read(first);
  const concurrent = await Promise.all([first, second].map((client, index) => client.callTool({
    name: "apply_canvas_changes", arguments: {
      canvasId: beforeParallel.canvasId, expectedRevision: beforeParallel.revision,
      create: [{ id: `parallel-${index}`, type: "ellipse", x: 100 + index * 100, y: 300, width: 60, height: 60 }],
    },
  })));
  assert.equal(concurrent.filter((result) => result.isError !== true).length, 1);
  assert.equal((await read(first)).elements.filter((element) => element.id.startsWith("parallel-")).length, 1);
  check("two simultaneous agents cannot both apply the same revision");
  const beforeInvalid = await read(first);
  const invalid = await first.callTool({ name: "apply_canvas_changes", arguments: {
    canvasId: beforeInvalid.canvasId, expectedRevision: beforeInvalid.revision,
    create: [{ id: "must-not-exist", type: "ellipse", x: 100, y: 300 }], delete: ["missing-element"],
  } });
  assert.equal(invalid.isError, true);
  const afterInvalid = await read(first);
  assert.equal(afterInvalid.revision, beforeInvalid.revision);
  assert.ok(!afterInvalid.elements.some((element) => element.id === "must-not-exist"));
  check("a failed batch makes no partial edits");
  const exported = (await call(first, "export_canvas_scene", { canvasId: current.canvasId })).structuredContent;
  assert.equal(exported.scene.type, "excalidraw");
  assert.ok(exported.scene.elements.some((element) => element.id === "server"));
  await writeFile(resolve("build/verification/Canvas-MCP.excalidraw"), JSON.stringify(exported.scene, null, 2));
  check("MCP exports portable Excalidraw JSON");
  const beforeDelete = await read(first);
  await call(first, "apply_canvas_changes", {
    canvasId: beforeDelete.canvasId, expectedRevision: beforeDelete.revision, delete: ["request"],
  });
  assert.ok(!(await read(first)).elements.some((element) => element.id === "request"));
  check("MCP deletes only the requested element");
  const beforeTemporary = await read(first);
  const beforeBounds = await call(first, "snapshot_canvas", { canvasId: beforeTemporary.canvasId });
  const beforePNG = Buffer.from(beforeBounds.content.find((content) => content.type === "image").data, "base64");
  const temporary = (await call(first, "apply_canvas_changes", {
    canvasId: beforeTemporary.canvasId, expectedRevision: beforeTemporary.revision,
    create: [{ id: "temporary-outside-scene", type: "rectangle", x: -2000, y: -2000, width: 100, height: 100 }],
  })).structuredContent;
  await call(first, "apply_canvas_changes", {
    canvasId: temporary.canvasId, expectedRevision: temporary.revision, delete: ["temporary-outside-scene"],
  });
  const afterBounds = await call(first, "snapshot_canvas", { canvasId: temporary.canvasId });
  const afterPNG = Buffer.from(afterBounds.content.find((content) => content.type === "image").data, "base64");
  assert.deepEqual(afterPNG.subarray(16, 24), beforePNG.subarray(16, 24));
  check("deleted shapes do not leave empty margins in MCP snapshots");
  const permissions = (await import("node:fs/promises")).stat;
  assert.equal((await permissions(socket)).mode & 0o777, 0o600);
  check("the socket is accessible only to its owning user");
} catch (error) {
  console.error(diagnostics);
  throw error;
} finally {
  await Promise.allSettled(clients.map((client) => client.close()));
  await writeFile(`${socket}.done`, "done");
  await Promise.race([hostExit, delay(5000)]);
  if (host.exitCode === null) host.kill("SIGTERM");
}
