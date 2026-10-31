import "server-only";
import {
  createRetention,
  sqlTransport,
} from "better-supabase/blocks/data-lifecycle";
import { seedTenantOnCreate } from "better-supabase/testing";

import { betterSupabase } from "@/lib/supabase";

import { postgres } from "../developer/postgres";
import { seed } from "./tenant-seed";

/**
 * Twenty years is the Dutch WGBO term for medical records. Confirm the term for
 * your sector and country before you copy it.
 */
const CLIENT_RECORDS_TERM = "20 years";

/**
 * In `next dev`, gives each organization created through the organizations
 * block the demo rows in `tenant-seed.ts`, and keeps client records for the
 * care preset's term. Needs `WORKFLOW_POSTGRES_URL` for the service-role
 * connection, and does nothing without it.
 */
export function seedNewTenants(): void {
  const connection = postgres();

  if (!connection) {
    return;
  }

  seedTenantOnCreate(betterSupabase, seed, { sql: connection.admin });

  void createRetention({ transport: sqlTransport(connection.admin) })
    .setPolicy("client_records", CLIENT_RECORDS_TERM)
    .then((result) => {
      if (!result.ok) {
        console.error(
          "better-supabase: the client records retention could not be set",
          result.error,
        );
      }
    });
}
