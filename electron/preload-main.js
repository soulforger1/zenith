// Preload for the main app window (the Next.js renderer). contextIsolation
// is on and nodeIntegration is off there (see openMainWindow in main.js), so
// this is the only bridge between the main process and the app's React
// code. Kept to exactly what's needed: notifying the renderer when the
// global double-tap-Option shortcut fires (see startOptionDoubleTapListener
// in main.js) so it can pop the paste-task modal open regardless of which
// route is currently mounted — read via window.zenithDesktop in
// components/layout/app-shell.tsx.
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("zenithDesktop", {
  onOpenPasteTaskModal(callback) {
    const listener = () => callback();
    ipcRenderer.on("open-paste-task-modal", listener);
    return () => ipcRenderer.removeListener("open-paste-task-modal", listener);
  },
});
