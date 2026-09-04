import { config } from "dotenv";
import { defineConfig } from "drizzle-kit";

// drizzle-kit does no env loading of its own; load .env.local explicitly.
config({ path: ".env.local" });

// Migrations need a direct (non-pooled) session connection — Supavisor's
// transaction-pooling mode (used at runtime via DATABASE_URL) doesn't
// support the session-level operations drizzle-kit needs to run DDL.
const directUrl = process.env.DIRECT_URL;

if (!directUrl) {
  throw new Error("DIRECT_URL is not set. Copy .env.example to .env.local and fill it in.");
}

export default defineConfig({
  schema: "./db/schema.ts",
  out: "./drizzle/migrations",
  dialect: "postgresql",
  dbCredentials: {
    url: directUrl,
  },
  strict: true,
  verbose: true,
});
