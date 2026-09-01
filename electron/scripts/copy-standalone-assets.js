// Next's `output: "standalone"` produces .next/standalone/server.js plus a
// pruned node_modules, but deliberately does NOT copy `public/` or
// `.next/static` — the docs call this out as a required manual step, since
// those are normally meant to be served by a CDN instead.
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..", "..");
const standalone = path.join(root, ".next", "standalone");

if (!fs.existsSync(standalone)) {
  console.error("`.next/standalone` not found — run `bun run build` first.");
  process.exit(1);
}

const publicDir = path.join(root, "public");
if (fs.existsSync(publicDir)) {
  fs.cpSync(publicDir, path.join(standalone, "public"), { recursive: true });
}
fs.cpSync(path.join(root, ".next", "static"), path.join(standalone, ".next", "static"), { recursive: true });

console.log("Copied public/ and .next/static into .next/standalone.");

// electron-builder's file copier hardcodes an unconditional exclusion for
// any directory whose path *relative to the copy source root* is exactly
// "node_modules" (app-builder-lib/out/util/filter.js: "filter the root
// node_modules, but not a sub-node_modules") — with no config to opt out.
// Since `.next/standalone`'s immediate child is literally named
// `node_modules`, pointing extraResources.from directly at it silently
// drops the entire dependency tree, no matter what `files`/`filter`
// patterns are set. Staging the whole standalone build one level deeper
// (so `node_modules` is `app/node_modules` relative to the staging root,
// not the bare root itself) sidesteps the hardcoded check entirely.
const staging = path.join(root, "electron", "app-server-staging");
fs.rmSync(staging, { recursive: true, force: true });
fs.cpSync(standalone, path.join(staging, "app"), { recursive: true });

console.log("Staged .next/standalone into electron/app-server-staging/app for packaging.");

// `sharp` (+ its native @img/sharp-* binaries, ~27MB) powers Next's built-in
// /_next/image optimizer, which every Next app registers unconditionally —
// even this one, with zero next/image usages and images.unoptimized: true
// in next.config.ts. Next's own build-trace code only skips sharp from the
// standalone output when building *on Vercel's infrastructure*
// (collect-build-traces.js gates it behind an internal hasNextSupport
// check) — there's no next.config.ts flag that reaches a plain local build
// like this one, so it's always traced in regardless of config. Since the
// optimizer code path that would require() it is provably unreachable here,
// it's safe to just delete post-build instead.
const deadWeightDirs = ["sharp", "@img"].map((name) => path.join(staging, "app", "node_modules", name));
for (const dir of deadWeightDirs) {
  fs.rmSync(dir, { recursive: true, force: true });
}
console.log("Pruned unused node_modules/{sharp,@img} (Next's image optimizer isn't used by this app).");
