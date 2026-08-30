// Ambient type for the bridge electron/preload-main.js exposes on `window`
// inside the packaged desktop app. Undefined in a plain browser tab (e.g.
// `next dev` outside Electron) — every consumer must optional-chain it.
export {};

declare global {
  interface Window {
    zenithDesktop?: {
      /** Fires when the global double-tap-Option shortcut is triggered from
       * anywhere on the system — see startOptionDoubleTapListener in
       * electron/main.js. Returns an unsubscribe function. */
      onOpenPasteTaskModal: (callback: () => void) => () => void;
    };
  }
}
