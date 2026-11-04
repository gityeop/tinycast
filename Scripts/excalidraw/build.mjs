import { build } from "esbuild";
import { cp, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
const output = resolve(root, "../../Tinycast/Resources/Excalidraw");
await mkdir(output, { recursive: true });
const result = await build({
  absWorkingDir: root,
  entryPoints: ["src/editor.jsx"],
  outdir: output,
  entryNames: "editor.generated",
  bundle: true,
  format: "iife",
  platform: "browser",
  conditions: ["production"],
  external: ["*.woff2"],
  target: "safari26",
  minify: true,
  sourcemap: false,
  legalComments: "linked",
  metafile: true,
  define: { "process.env.NODE_ENV": '"production"' },
});
await cp(resolve(root, "node_modules/@excalidraw/excalidraw/dist/prod/fonts"), resolve(output, "fonts"), {
  recursive: true,
});
await writeFile(resolve(output, "index.html"), await readFile(resolve(root, "src/index.html")));
const packages = new Set();
for (const input of Object.keys(result.metafile.inputs)) {
  if (!input.startsWith("node_modules/")) continue;
  let directory = dirname(resolve(root, input));
  while (!existsSync(resolve(directory, "package.json"))) directory = dirname(directory);
  packages.add(directory);
}
const notices = [await readFile(resolve(root, "EXCALIDRAW-LICENSE.txt"), "utf8")];
for (const directory of [...packages].sort()) {
  const manifest = JSON.parse(await readFile(resolve(directory, "package.json"), "utf8"));
  const licenses = (await readdir(directory)).filter((name) => /^(licen[cs]e|copying)(\.|$)/i.test(name));
  notices.push(`${manifest.name} ${manifest.version} (${manifest.license})`);
  for (const license of licenses) notices.push(await readFile(resolve(directory, license), "utf8"));
}
notices.push(await readFile(resolve(root, "licenses/Fonts.txt"), "utf8"));
await writeFile(resolve(output, "THIRD-PARTY-LICENSES.txt"), notices.join("\n\n"));
console.log(`Built embedded Excalidraw in ${output}`);
