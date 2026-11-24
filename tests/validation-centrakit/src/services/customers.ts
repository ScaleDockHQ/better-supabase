import type { SqlClient } from "better-supabase/postgres";

import { postgresExecutor } from "better-supabase/postgres";

import { betterSupabase } from "./schema.ts";

/** The JWT claims CentraKit's pool connection runs with. */
export type CallerClaims = { readonly sub?: string; readonly role?: string };

/**
 * The db CentraKit's request context builds: over the app's own Postgres pool,
 * with the caller's claims, so the connection runs as the caller under RLS.
 */
export const contextDb = (sql: SqlClient, claims: CallerClaims) =>
  betterSupabase.connect(postgresExecutor(sql), { claims });

export type CentraKitDb = ReturnType<typeof contextDb>;

/**
 * CentraKit's customer service: it gets `db` from the app's request context and
 * pages through one organization's customers.
 */
export function customerService(db: CentraKitDb) {
  return {
    page: (organizationId: string) =>
      db.customers.page({ where: { organizationId }, size: 20 }),
    members: (organizationId: string) =>
      db.organizationUsers.list({ where: { organizationId } }),
  };
}
