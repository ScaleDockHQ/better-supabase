import type { NextOptions } from "better-supabase/next";

import "server-only";
import { permissionsAuthorizer } from "better-supabase/blocks/permissions";
import { createNext } from "better-supabase/next";

import { env } from "@/env";
import { getPermissions } from "@/features/user/permission-snapshot";

import { catalog } from "../permission-catalog";
import { permissions } from "./blocks.config";
import { betterSupabaseCore } from "./core";
import { keptStore } from "./kept-store";
import { sharedCounters } from "./session-counters";

const options: NextOptions = {
  // Record pages read their `can` flags from the token or the shell's one call.
  heldPermissions: getPermissions,
  // The browser client in `client.ts` sets the same `cookies.encode`.
  auth: { cookie: { encode: "tokens-only" } },
  debug: {
    enabled: env.EXPOSE_TESTING_API === "1",
    // First-request timings, read by the harness (`cold=` in the stats header).
    coldStart: env.EXPOSE_TESTING_API === "1",
    budget: { calls: 8, waves: 2 },
    route: "/api/bs-stats",
  },
  replicas: { pinMs: 5000 },
  kept: { store: keptStore() },
  // The same counters as `server.ts`, so `/api/bs-sessions` counts every server.
  sessions: { counters: sharedCounters() },
  authorizer: permissionsAuthorizer({
    permissions,
    catalog,
    load: myPermissions,
  }),
};

/**
 * `bsb` over the core block set, for routes that need no other block. It has
 * its own session memo, so a route imports this or `server.ts`, not both.
 */
export const bsbCore = createNext(betterSupabaseCore, options);

/**
 * The caller's keys from `my_permissions`, once per request. `context()`, not
 * `cached()`: route handlers and actions have no cache scope (`cacheLife()`
 * throws there, and the authorizer reported that as a 403).
 */
async function myPermissions(): Promise<readonly string[] | undefined> {
  const { db } = await bsbCore.context();
  const result = await db.permissions.permissions();

  return result.ok ? result.data.keys : undefined;
}
