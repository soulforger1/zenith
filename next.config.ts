import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Cache Components implements Partial Prerendering: a static shell (nav
  // chrome, layout structure) is served instantly while dynamic,
  // per-request DB reads stream in behind <Suspense> boundaries — the
  // replacement for the old experimental.ppr flag in this Next version.
  cacheComponents: true,
  // Requires cacheComponents. Links prefetch a shared App Shell per route
  // instead of a full per-link prefetch — safe here, no <Link prefetch>
  // usages in the app to audit.
  partialPrefetching: true,
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
