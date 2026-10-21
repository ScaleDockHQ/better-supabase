import "server-only";
import { seedTenantOnCreate } from "better-supabase/testing";

import { betterSupabase } from "@/lib/supabase";

import { postgres } from "../developer/postgres";
import { seed } from "./tenant-seed";

/**
 * In `next dev`, gives each organization created through the organizations
 * block the demo rows in `tenant-seed.ts`. Needs `WORKFLOW_POSTGRES_URL` for
 * the service-role connection, and does nothing without it.
 */
export function seedNewTenants(): void {
  const connection = postgres();

  if (connection) {
    seedTenantOnCreate(betterSupabase, seed, { sql: connection.admin });
  }
}
