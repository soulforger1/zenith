import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Plain CommonJS Node scripts (Electron main/preload/build scripts) —
    // a different runtime context from the Next.js app, intentionally
    // using require() rather than the app's ESM/TypeScript conventions.
    "electron/**",
    // electron-builder's packaged app output (bundled/minified third-party
    // code, not source this project owns).
    "release/**",
  ]),
]);

export default eslintConfig;
