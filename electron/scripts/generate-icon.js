// One-off script (not part of the regular build) — regenerates
// electron/build/icon.icns from app/icon.svg. Run manually whenever the
// icon design changes: `node electron/scripts/generate-icon.js`.
const sharp = require("sharp");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const root = path.join(__dirname, "..", "..");
const source = path.join(root, "app", "icon.svg");
const buildDir = path.join(root, "electron", "build");
const iconset = path.join(buildDir, "icon.iconset");

const sizes = [16, 32, 128, 256, 512];

async function main() {
  fs.rmSync(iconset, { recursive: true, force: true });
  fs.mkdirSync(iconset, { recursive: true });

  for (const size of sizes) {
    await sharp(source).resize(size, size).png().toFile(path.join(iconset, `icon_${size}x${size}.png`));
    await sharp(source)
      .resize(size * 2, size * 2)
      .png()
      .toFile(path.join(iconset, `icon_${size}x${size}@2x.png`));
  }

  execFileSync("iconutil", ["-c", "icns", iconset, "-o", path.join(buildDir, "icon.icns")]);
  fs.rmSync(iconset, { recursive: true, force: true });

  console.log("Generated electron/build/icon.icns");
}

main();
