import "server-only";

import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";

import * as schema from "./schema";

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error("DATABASE_URL is not set. Copy .env.example to .env.local and fill it in.");
}

// Uses Supabase's pooled (Supavisor, transaction-mode) connection string.
// `prepare: false` is required in transaction-pooling mode — it disables
// prepared statements, which pgbouncer/Supavisor transaction mode doesn't
// support across pooled connections.
const client = postgres(connectionString, { prepare: false });

export const db = drizzle(client, { schema });
