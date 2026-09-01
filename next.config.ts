import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Produces .next/standalone/server.js — a minimal, self-contained server
  // (pruned node_modules included) for the Electron shell to spawn directly,
  // instead of shipping/reinstalling the full dev node_modules tree.
  output: "standalone",
  // Cache Components implements Partial Prerendering: a static shell (nav
  // chrome, layout structure) is served instantly while dynamic,
  // per-request DB reads stream in behind <Suspense> boundaries — the
  // replacement for the old experimental.ppr flag in this Next version.
  cacheComponents: true,
  // Requires cacheComponents. Links prefetch a shared App Shell per route
  // instead of a full per-link prefetch — safe here, no <Link prefetch>
  // usages in the app to audit.
  partialPrefetching: true,
  // @anthropic-ai/claude-agent-sdk resolves its actual `claude` CLI binary
  // from an optional platform package (e.g. claude-agent-sdk-darwin-arm64)
  // via a *dynamic* require built from process.platform/arch at runtime —
  // Next's build-time file tracer (@vercel/nft) can only follow static
  // require()/import() calls, so it silently drops that package from
  // .next/standalone entirely. Works in `next dev` (full node_modules on
  // disk) but breaks in the packaged Electron app, which only ships what
  // got traced — surfaced as "Native CLI binary for darwin-arm64 not found"
  // from the paste-task/AI modal. This forces it back in for the three
  // routes that actually spawn the SDK (see app/api/ai/*/route.ts).
  outputFileTracingIncludes: {
    "/api/ai/*": ["./node_modules/@anthropic-ai/claude-agent-sdk-darwin-arm64/**/*"],
  },
  // Next registers its /_next/image optimization endpoint (and traces in
  // `sharp` + its native @img/sharp-* binaries, ~27MB) unconditionally in
  // every app, even with zero next/image usages — which this app has none
  // of (images are stored as base64 data URLs, see serverActions
  // .bodySizeLimit below). Route-scoped outputFileTracingExcludes can't
  // reach that internal route since it isn't one of ours; this is the
  // actual purpose-built flag to opt out of the optimizer (and its sharp
  // dependency) entirely.
  images: {
    unoptimized: true,
  },
  // Next's dev server only trusts "localhost" by default and silently blocks
  // cross-origin requests for its own dev assets (HMR socket, JS chunks,
  // fonts) from anything else — including 127.0.0.1, a *different* origin as
  // far as this check is concerned. electron/main.js's dev-mode window
  // explicitly loads http://127.0.0.1:3000 (see startAppServerAndOpenWindow),
  // so without this, every client JS chunk silently fails to load: the page
  // still renders (server HTML is unaffected) but nothing is interactive —
  // no modals, no command palette, no click handlers at all.
  allowedDevOrigins: ["127.0.0.1"],
  experimental: {
    // Next 15+ defaults this to 0 (always refetch on navigation, even for
    // pages you just visited). For a single-user app talking to a remote DB,
    // that means every click pays a full network round trip. 30s lets the
    // client Router Cache reuse recently-visited pages (e.g. flipping
    // between List/Board/Milestones tabs) without a fresh DB hit each time.
    staleTimes: {
      dynamic: 30,
    },
    // Default is 1mb — too small for the space reference-image upload
    // (images are stored inline as base64 data URLs via a Server Action).
    serverActions: {
      bodySizeLimit: "8mb",
    },
  },
};

export default nextConfig;
