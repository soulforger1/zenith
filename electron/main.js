// Electron main process. CommonJS (no "type": "module" in package.json).
// This file is esbuild-bundled (see electron/scripts/build-electron.js)
// before packaging, so it must have zero runtime requires beyond Node
// builtins, `electron`, and `postgres` — all resolved at bundle time, not
// left for electron-builder to trace out of node_modules. `uiohook-napi` is
// the one deliberate exception: it ships a compiled .node binary that
// esbuild can't inline, so it's marked external in build-electron.js and
// shipped as a real node_modules folder instead — see electron-builder.yml's
// `files`/`asarUnpack` entries for it.
const { app, BrowserWindow, ipcMain, systemPreferences } = require("electron");
const path = require("node:path");
const fs = require("node:fs");
const net = require("node:net");
const { spawn, spawnSync } = require("node:child_process");
const postgres = require("postgres");

const APP_NAME = "Zenith";
app.setName(APP_NAME);

const isDev = !app.isPackaged;
const configPath = () => path.join(app.getPath("userData"), "config.json");

let nextServerProcess = null;
let mainWindow = null;

/** GUI-launched macOS apps (double-clicked, not run from a terminal) often
 * get a minimal PATH (e.g. /usr/bin:/bin:/usr/sbin:/sbin) that doesn't
 * include wherever the `claude` CLI is actually installed (nvm/homebrew/etc,
 * only set up in shell rc files) — the AI features depend on that CLI being
 * resolvable via PATH when @anthropic-ai/claude-agent-sdk spawns it inside
 * the Next server child process. Fixed by asking the user's actual login
 * shell what PATH it resolves to and adopting that — the same technique the
 * well-known `fix-path` package uses, inlined here to avoid an ESM-only
 * dependency (fix-path v5+ is ESM-only, which fights esbuild's CJS bundling
 * and electron-builder's file inclusion for no real benefit over 20 lines
 * of plain code). No-op on Windows, which doesn't have this problem. */
function fixPath() {
  if (process.platform === "win32") return;
  const shell = process.env.SHELL || "/bin/zsh";
  const marker = "___PATH_MARKER___";
  try {
    const result = spawnSync(shell, ["-ilc", `echo -n "${marker}"; echo -n "$PATH"`], {
      encoding: "utf8",
      timeout: 10_000,
    });
    const output = result.stdout || "";
    const idx = output.lastIndexOf(marker);
    if (idx === -1) return;
    const shellPath = output.slice(idx + marker.length).trim();
    if (shellPath) process.env.PATH = shellPath;
  } catch {
    // Best-effort — leave PATH as-is if the shell probe fails for any reason.
  }
}

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(configPath(), "utf8"));
  } catch {
    return null;
  }
}

function writeConfig(config) {
  fs.mkdirSync(app.getPath("userData"), { recursive: true });
  fs.writeFileSync(configPath(), JSON.stringify(config, null, 2));
}

/** Real connectivity check, not just "is this a well-formed URL" — a typo'd
 * password/host fails immediately here instead of surfacing later as a
 * silently blank app. */
async function validateDatabaseUrl(databaseUrl) {
  const sql = postgres(databaseUrl, { prepare: false, connect_timeout: 8 });
  try {
    await sql`select 1`;
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  } finally {
    await sql.end({ timeout: 1 });
  }
}

function getFreePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, "127.0.0.1", () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
    srv.on("error", reject);
  });
}

async function waitForServerReady(port, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/health`);
      if (res.ok) return;
    } catch {
      // not up yet
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("The app server did not start in time.");
}

function serverEntryPath() {
  // In dev, `next dev` is already running (see package.json's electron:dev
  // script) — nothing to spawn. In a packaged app, the standalone build was
  // staged one level deeper than usual (Contents/Resources/app-server/app/,
  // not app-server/ directly) — see copy-standalone-assets.js for why
  // (electron-builder silently drops a copy root's immediate "node_modules"
  // child, so it can't sit right at the app-server/ root).
  return path.join(process.resourcesPath, "app-server", "app", "server.js");
}

function spawnNextServer(port, config) {
  const serverPath = serverEntryPath();
  const child = spawn(process.execPath, [serverPath], {
    // Next's standalone server.js resolves .next/ and public/ relative to
    // its own working directory, not __dirname — without this it inherits
    // Electron's own cwd (unpredictable for a packaged .app, e.g. "/"),
    // can't find its files, and exits immediately.
    cwd: path.dirname(serverPath),
    env: {
      ...process.env, // carries fix-path's corrected PATH through to the `claude` CLI subprocess
      ELECTRON_RUN_AS_NODE: "1", // run Electron's bundled Node as plain Node, no system `node` needed
      NODE_ENV: "production",
      PORT: String(port),
      HOSTNAME: "127.0.0.1",
      DATABASE_URL: config.databaseUrl,
      GITHUB_TOKEN: config.githubToken || "",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  child.stdout.on("data", (chunk) => process.stdout.write(`[next] ${chunk}`));
  child.stderr.on("data", (chunk) => process.stderr.write(`[next] ${chunk}`));
  child.on("exit", (code) => {
    nextServerProcess = null;
    if (code !== 0 && code !== null) {
      showFatalError(`The app server exited unexpectedly (code ${code}). Check that your database is reachable.`);
    }
  });
  return child;
}

function killNextServer() {
  if (!nextServerProcess) return;
  const proc = nextServerProcess;
  nextServerProcess = null;
  proc.kill("SIGTERM");
  const forceKillTimer = setTimeout(() => {
    try {
      proc.kill("SIGKILL");
    } catch {
      // already gone
    }
  }, 5000);
  proc.once("exit", () => clearTimeout(forceKillTimer));
}

function showFatalError(message) {
  const { dialog } = require("electron");
  dialog.showErrorBox(APP_NAME, message);
}

function openMainWindow(port) {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    title: APP_NAME,
    // Hide the native title bar (which reserved a whole colored strip above
    // the app) but keep the traffic-light buttons, repositioned to sit over
    // the sidebar's top-left corner instead — see the matching drag-region
    // spacer above <AppSidebar>'s logo in components/layout/app-sidebar.tsx,
    // which reserves the visual space these buttons float in and keeps the
    // window draggable now that there's no native bar to drag by.
    titleBarStyle: "hidden",
    trafficLightPosition: { x: 16, y: 16 },
    // Electron's default window backing is white — during a live resize,
    // Chromium can't repaint the new area fast enough and that default
    // shows through for a frame, flashing white even though every layer of
    // our own CSS is dark. Matches app/globals.css's dark-mode --background
    // (oklch(0.15 0.006 260)) so any such flash blends in instead.
    backgroundColor: "#0a0b0e",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, "preload-main.js"),
    },
  });
  mainWindow.loadURL(`http://127.0.0.1:${port}`);
}

/** Double-tapping Option, from anywhere on the system (not just while Zenith
 * is focused — same convention as Raycast/Alfred's quick-capture), brings
 * the window to front and pops the paste-task modal open. Requires a raw
 * global key hook (uiohook-napi) since Electron's own globalShortcut API
 * only matches full accelerator combos, not a bare modifier tapped twice —
 * and that hook needs macOS's Accessibility permission, which the app
 * doesn't otherwise need for anything. Fails silently/gracefully at every
 * step (missing permission, unsupported platform, missing window) since
 * nothing else in the app depends on this working. */
let uiohook = null;

function startOptionDoubleTapListener() {
  if (process.platform !== "darwin") return; // double-tap-Option is a macOS convention; skip elsewhere

  if (!systemPreferences.isTrustedAccessibilityClient(false)) {
    // Triggers macOS's own "Zenith wants to control this computer" prompt
    // and adds the app to System Settings > Privacy & Security >
    // Accessibility (unchecked). The feature just stays off until the user
    // enables it there and relaunches — nothing else depends on this.
    systemPreferences.isTrustedAccessibilityClient(true);
    console.warn(
      "[option-double-tap] Accessibility permission not granted — enable Zenith under " +
        "System Settings > Privacy & Security > Accessibility, then relaunch, to use it.",
    );
    return;
  }

  let UiohookKey;
  try {
    ({ uIOhook: uiohook, UiohookKey } = require("uiohook-napi"));
  } catch (err) {
    console.error("[option-double-tap] uiohook-napi failed to load, feature disabled:", err);
    return;
  }

  const DOUBLE_TAP_WINDOW_MS = 400;
  const MAX_TAP_HOLD_MS = 350; // a long Option hold is a modifier for something else, not a "tap"
  const OPTION_KEYCODES = new Set([UiohookKey.Alt, UiohookKey.AltRight]);

  let optionDownAt = 0;
  let optionHeldCleanly = false; // false once any other key interrupts the current hold
  let lastCleanTapAt = 0;

  uiohook.on("keydown", (e) => {
    if (OPTION_KEYCODES.has(e.keycode)) {
      optionDownAt = Date.now();
      optionHeldCleanly = true;
    } else {
      optionHeldCleanly = false;
    }
  });

  uiohook.on("keyup", (e) => {
    if (!OPTION_KEYCODES.has(e.keycode)) return;
    const wasClean = optionHeldCleanly;
    optionHeldCleanly = false;
    if (!wasClean) return;

    const now = Date.now();
    if (now - optionDownAt > MAX_TAP_HOLD_MS) {
      lastCleanTapAt = 0;
      return;
    }
    if (now - lastCleanTapAt <= DOUBLE_TAP_WINDOW_MS) {
      lastCleanTapAt = 0; // consume the pair so a third tap starts a fresh count
      onOptionDoubleTap();
    } else {
      lastCleanTapAt = now;
    }
  });

  uiohook.start();
}

function stopOptionDoubleTapListener() {
  if (!uiohook) return;
  try {
    uiohook.stop();
  } catch {
    // already stopped
  }
}

function onOptionDoubleTap() {
  if (!mainWindow) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  app.focus({ steal: true });
  mainWindow.webContents.send("open-paste-task-modal");
}

async function startAppServerAndOpenWindow(config) {
  if (isDev) {
    // next dev is already running on 3000 via `bun run dev` (see the
    // electron:dev script) — just wait for it and open the window.
    await waitForServerReady(3000);
    openMainWindow(3000);
    return;
  }
  const port = await getFreePort();
  nextServerProcess = spawnNextServer(port, config);
  await waitForServerReady(port);
  openMainWindow(port);
}

function runSetupWindow() {
  return new Promise((resolve, reject) => {
    let settled = false;
    const setupWindow = new BrowserWindow({
      width: 480,
      height: 420,
      title: `${APP_NAME} — Setup`,
      resizable: false,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        preload: path.join(__dirname, "preload-setup.js"),
      },
    });
    setupWindow.setMenuBarVisibility(false);
    setupWindow.loadFile(path.join(__dirname, "setup", "index.html"));

    ipcMain.handle("setup:submit", async (_event, { databaseUrl, githubToken }) => {
      if (!databaseUrl || !databaseUrl.trim()) {
        return { ok: false, error: "Database URL is required." };
      }
      const check = await validateDatabaseUrl(databaseUrl.trim());
      if (!check.ok) {
        return { ok: false, error: `Couldn't connect: ${check.error}` };
      }
      const config = { databaseUrl: databaseUrl.trim(), githubToken: (githubToken || "").trim() };
      writeConfig(config);
      settled = true;
      ipcMain.removeHandler("setup:submit");
      setupWindow.close();
      resolve(config);
      return { ok: true };
    });

    // Closed without ever successfully submitting (e.g. the user just quit)
    // — reject so the caller quits the app instead of hanging forever.
    setupWindow.on("closed", () => {
      ipcMain.removeHandler("setup:submit");
      if (!settled) reject(new Error("Setup was cancelled."));
    });
  });
}

async function main() {
  // Must happen before spawning anything — see fixPath()'s own comment.
  fixPath();

  await app.whenReady();

  let config = isDev ? {} : readConfig();
  if (!isDev && !config) {
    try {
      config = await runSetupWindow();
    } catch {
      app.quit();
      return;
    }
  }

  try {
    await startAppServerAndOpenWindow(config);
  } catch (err) {
    showFatalError(err instanceof Error ? err.message : String(err));
    app.quit();
    return;
  }

  startOptionDoubleTapListener();
}

app.on("window-all-closed", () => {
  killNextServer();
  app.quit();
});
app.on("before-quit", killNextServer);
app.on("will-quit", killNextServer);
app.on("will-quit", stopOptionDoubleTapListener);

main();
