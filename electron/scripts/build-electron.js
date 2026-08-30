// Bundles the Electron main process + preloads into self-contained CJS
// files with esbuild, so electron-builder never needs to trace/ship the
// project's dev node_modules (~1GB, full of Next/React/etc that the
// Electron shell itself has no use for) — only electron/dist ends up in the
// packaged app, alongside the already-self-contained .next/standalone build
// shipped separately via extraResources (see electron-builder.yml).
//
// `uiohook-napi` is the one dependency left external instead of inlined: it
// ships a compiled .node binary for the global double-tap-Option listener
// (see main.js) that esbuild can't bundle into JS. electron-builder.yml
// ships its actual node_modules folder (plus asarUnpack, since a packed
// .asar archive can't dlopen a native addon from inside it) so main.js's
// `require("uiohook-napi")` still resolves normally at runtime.
const esbuild = require("esbuild");
const fs = require("node:fs");
const path = require("node:path");

const electronDir = path.join(__dirname, "..");
const outDir = path.join(electronDir, "dist");

fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(outDir, { recursive: true });

esbuild.buildSync({
  entryPoints: [
    path.join(electronDir, "main.js"),
    path.join(electronDir, "preload-setup.js"),
    path.join(electronDir, "preload-main.js"),
  ],
  bundle: true,
  platform: "node",
  target: "node18",
  format: "cjs",
  external: ["electron", "uiohook-napi"],
  outdir: outDir,
});

// Plain browser HTML/JS for the setup screen — not bundled, just copied
// alongside so main.js's `loadFile(path.join(__dirname, "setup", ...))`
// resolves correctly relative to the bundled output directory.
fs.cpSync(path.join(electronDir, "setup"), path.join(outDir, "setup"), { recursive: true });

console.log("Bundled Electron main/preload into electron/dist, copied setup/ assets.");
