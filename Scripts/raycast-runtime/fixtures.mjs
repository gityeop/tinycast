// Self-contained checks for the embedded runtime: each fixture is a tiny extension command compiled
// with esbuild exactly the way a real one is (CJS, JSX automatic, @raycast/api + react external).
//
//   node fixtures.mjs

import { createHarness, bootConfig, describeTree } from "./test.mjs";
import { transformSync } from "esbuild";

let passes = 0;
let failures = 0;

function check(label, condition, extra = "") {
  if (condition) {
    passes++;
    console.log(`  ✓ ${label}`);
  } else {
    failures++;
    console.log(`  ✗ ${label}${extra ? ` — ${extra}` : ""}`);
  }
}

function compile(source) {
  const { code } = transformSync(source, {
    loader: "jsx",
    jsx: "automatic",
    jsxImportSource: "react",
    format: "cjs",
    target: "es2022",
  });
  return code;
}

const wait = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));

async function run(name, source, mode, verify, options) {
  console.log(`\n▶ ${name}`);
  const harness = createHarness(options);
  harness.boot(bootConfig());
  const code = compile(source);
  harness.start("s1", code, "/fixtures/cmd.js", "/fixtures", mode, {});
  await wait(options?.settle);
  await verify(harness);
  harness.stop("s1");
}

// ─── Fixtures ────────────────────────────────────────────────────────

const listSource = `
import { List, ActionPanel, Action, Icon } from "@raycast/api";
import { useState } from "react";

export default function Command() {
  const [count, setCount] = useState(0);
  return (
    <List
      searchBarPlaceholder="Search…"
      searchBarAccessory={
        <List.Dropdown tooltip="Filter" onChange={() => {}}>
          <List.Dropdown.Item title="All" value="all" />
          <List.Dropdown.Item title="Active" value="active" />
        </List.Dropdown>
      }
    >
      <List.Section title="Main">
        <List.Item
          id="item-1"
          title={"Count is " + count}
          accessories={[{ text: "Tag" }, { icon: Icon.Star }]}
          actions={
            <ActionPanel>
              <Action title="Bump" onAction={() => setCount((c) => c + 1)} />
            </ActionPanel>
          }
        />
      </List.Section>
    </List>
  );
}
`;

const detailSource = `
import { Detail } from "@raycast/api";

export default function Command() {
  return (
    <Detail
      markdown="# Hello world"
      metadata={
        <Detail.Metadata>
          <Detail.Metadata.Label title="Author" text="Ada" />
          <Detail.Metadata.Separator />
          <Detail.Metadata.TagList title="Tags">
            <Detail.Metadata.TagList.Item text="fast" color="#00ff00" />
          </Detail.Metadata.TagList>
          <Detail.Metadata.Link title="Link" target="https://example.com" text="Home" />
        </Detail.Metadata>
      }
    />
  );
}
`;

const fragmentDetailSource = `
import { List } from "@raycast/api";

export default function Command() {
  return (
    <List>
      <List.Item
        title="TOTP"
        detail={
          <>
            <List.Item.Detail markdown="30s remaining" />
            <List.Item.Detail metadata={<List.Item.Detail.Metadata><List.Item.Detail.Metadata.Label title="Code" text="123456" /></List.Item.Detail.Metadata>} />
          </>
        }
      />
    </List>
  );
}
`;

const formSource = `
import { Form, ActionPanel, Action } from "@raycast/api";

export default function Command() {
  return (
    <Form actions={<ActionPanel><Action.SubmitForm title="Save" onSubmit={(values) => { globalThis.__submitted = values; }} /></ActionPanel>}>
      <Form.TextField id="name" title="Name" defaultValue="Ada" />
      <Form.TextArea id="bio" title="Bio" defaultValue="" />
      <Form.Checkbox id="agree" label="I agree" defaultValue={true} />
      <Form.Dropdown id="role" title="Role" defaultValue="dev">
        <Form.Dropdown.Item value="dev" title="Developer" />
      </Form.Dropdown>
      <Form.TagPicker id="tags" title="Tags" defaultValue={["swift"]}>
        <Form.TagPicker.Item value="swift" title="Swift" />
      </Form.TagPicker>
      <Form.DatePicker id="when" title="When" defaultValue={new Date("2026-04-18T10:00:00Z")} />
      <Form.Separator />
      <Form.Description title="Info" text="All fields are saved locally." />
    </Form>
  );
}
`;

const navigationSource = `
import { List, ActionPanel, Action, useNavigation, Detail } from "@raycast/api";

function Subscreen() {
  return <Detail markdown="# Subscreen" />;
}

export default function Command() {
  const { push } = useNavigation();
  return (
    <List>
      <List.Item
        title="Push"
        actions={
          <ActionPanel>
            <Action title="Open subscreen" onAction={() => push(<Subscreen />)} />
          </ActionPanel>
        }
      />
    </List>
  );
}
`;

const nodeSource = `
import path from "node:path";
import os from "node:os";
import fs from "node:fs";
import crypto from "node:crypto";
import { Buffer } from "node:buffer";
import { fileURLToPath, pathToFileURL } from "node:url";
import { Detail } from "@raycast/api";

export default function Command() {
  const errorCode = (fn) => {
    try {
      fn();
      return "none";
    } catch (error) {
      return error.code ?? error.name;
    }
  };
  const cpu = os.cpus()[0];
  const parts = [
    path.join("/a/b", "../c", "d.txt"),
    path.extname("x/y/file.tar.gz"),
    path.basename("/a/b/c.md", ".md"),
    os.platform(),
    Object.keys(cpu.times).sort().join(","),
    String(Object.values(cpu.times).every(Number.isFinite)),
    String(os.freemem() > 0),
    String(os.uptime() > 0),
    String(os.loadavg().length === 3 && os.loadavg().every(Number.isFinite)),
    new URL("/next?q=1", "https://example.com/base/page").href,
    new URLSearchParams({ a: "1", b: "two words" }).toString(),
    crypto.createHash("sha256").update("abc").digest("hex").slice(0, 8),
    Buffer.from("hello").toString("base64"),
    Buffer.from("aGVsbG8=", "base64").toString("utf8"),
    new TextDecoder().decode(new TextEncoder().encode("héllo")),
    fileURLToPath("file:///Applications/Tinycast%20Beta.app"),
    fileURLToPath(new URL("file:///tmp/%ED%95%9C%EA%B8%80.txt")),
    fileURLToPath("file://localhost/tmp/a?query=ignored#fragment"),
    fileURLToPath("file:///tmp/a%5Cb"),
    fileURLToPath("file:tmp/a"),
    fileURLToPath("file:///tmp/%2e%2e/a"),
    fileURLToPath("file://%6cocalhost/tmp/a"),
    fileURLToPath("file:///tmp//a"),
    fileURLToPath(new URL("file:///tmp/a///b")),
    fileURLToPath("file:///tmp/a//../b"),
    fileURLToPath("file:///C:/.."),
    new URL(
      "file:///tmp/a?query=" +
        String.fromCharCode(92) +
        "keep#fragment=" +
        String.fromCharCode(92) +
        "keep",
    ).href,
    new URL("https://example.com/C:/..").href,
    fileURLToPath("file:///a:folder/.."),
    new URL("..", "file:///a:folder/child").href,
    new URL("..", "https://example.com/C:/child").href,
    pathToFileURL("/tmp/My Image.png").href,
    pathToFileURL("/tmp/a#b.png").href,
    fileURLToPath(pathToFileURL("/tmp/a#b.png")),
    fileURLToPath(pathToFileURL("/tmp/a?b.png")),
    fileURLToPath(pathToFileURL("/Applications/Tinycast Beta.app")),
    errorCode(() => fileURLToPath("file:///tmp/a%2Fb")),
    errorCode(() => fileURLToPath("file://a%2Fb/tmp/a")),
    errorCode(() => fileURLToPath("file://example.com/tmp/a")),
    errorCode(() => fileURLToPath("https://example.com/a")),
    errorCode(() => fileURLToPath({})),
    errorCode(() => fileURLToPath("file://user@localhost/tmp/a")),
    errorCode(() => fileURLToPath("file://localhost:/tmp/a")),
    errorCode(() => fileURLToPath("file:///C:/a", { windows: true })),
    // fs validates URL schemes the way Node does: a vscode-remote:// workspace URI whose stripped
    // pathname exists locally ("/" always does) must not pass existsSync — Raycast's Search Recent
    // Projects relies on that guard before handing the URI to fileURLToPath.
    String(fs.existsSync(new URL("vscode-remote://ssh-remote%2Bucg/"))),
    String(fs.existsSync(new URL("vscode-remote://ssh-remote%2Bserver/etc/docker/daemon.json"))),
    String(fs.existsSync(new URL("file:///etc/hosts"))),
    String(fs.existsSync("/etc/hosts")),
    errorCode(() => fs.statSync(new URL("https://example.com/a"))),
    errorCode(() => fs.readFileSync(new URL("https://example.com/a"))),
  ];
  return <Detail markdown={parts.join("\\n")} />;
}
`;

const slowBufferSource = `
const { Buffer } = require("buffer");

module.exports.default = () => {
  const SafeBuffer = Buffer.from && Buffer.alloc && Buffer.allocUnsafe && Buffer.allocUnsafeSlow
    ? Buffer : function (size) { return Buffer(size); };
  const selected = new SafeBuffer(4);
  const first = SafeBuffer.allocUnsafeSlow(4);
  const second = SafeBuffer.allocUnsafeSlow(4);
  first[0] = 91;
  globalThis.__slowBuffer = {
    selected: Buffer.isBuffer(selected) && selected.length === 4,
    enumerable: Object.keys(Buffer).includes("allocUnsafeSlow"),
    bytes: Array.from(second),
    independent: first.buffer !== second.buffer,
    empty: Buffer.isBuffer(Buffer.allocUnsafeSlow(0)) && Buffer.allocUnsafeSlow(0).length === 0,
  };
};
`;

const onceSource = `
const { EventEmitter } = require("events");

module.exports.default = () => {
  const emitter = new EventEmitter();
  const calls = [];
  const chained = emitter.once("ready", function (...args) {
    calls.push([this === emitter, ...args, emitter.listenerCount("ready")]);
    emitter.emit("ready", "recursive");
  }) === emitter;
  const emitted = emitter.emit("ready", "value", 7);
  const repeated = emitter.emit("ready", "again");
  let removedCalls = 0;
  function removed() { removedCalls++; }
  emitter.once("removed", removed).removeListener("removed", removed);
  emitter.emit("removed");
  const ordinary = [];
  emitter.on("ordinary", function (value) { ordinary.push([this === emitter, value]); });
  emitter.emit("ordinary", 1);
  emitter.emit("ordinary", 2);
  globalThis.__once = { calls, chained, emitted, repeated, removedCalls, ordinary };
};
`;

// apple-passwords lazily requires `@raycast/api` through `createRequire`, so it must resolve
// through the same registry as a top-level require.
const createRequireSource = `
import { createRequire } from "module";
import { Detail } from "@raycast/api";

const requireFromHere = createRequire("/fixtures/package.json");

export default function Command() {
  const api = requireFromHere("@raycast/api");
  const path = requireFromHere("node:path");
  const parts = [String(api.List !== undefined), String(api.ActionPanel !== undefined), path.join("a", "b")];
  return <Detail markdown={parts.join("\\n")} />;
}
`;

