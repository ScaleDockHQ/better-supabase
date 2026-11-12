import type { NextOptions } from "better-supabase/next";

import "server-only";
import { permissionsAuthorizer } from "better-supabase/blocks/permissions";
import { createNext } from "better-supabase/next";

import { env } from "@/env";

import { permissions } from "./blocks.config";
import { sharedCounters } from "./session-counters";
import { betterSupabaseShell } from "./shell";

const options: NextOptions = {
  debug: {
    enabled: env.EXPOSE_TESTING_API === "1",
    budget: { calls: 8, waves: 2 },
    route: "/api/bs-stats",
  },
  replicas: { pinMs: 5000 },
  // The same counters as `server.ts`, so `/api/bs-sessions` counts both.
  sessions: { counters: sharedCounters() },
  authorizer: permissionsAuthorizer({ permissions, load: myPermissions }),
};

/**
 * `bsb` over the shell block set, for routes that need no other block. It has
 * its own session memo, so a route imports this or `server.ts`, not both.
 */
export const bsbShell = createNext(betterSupabaseShell, options);

/**
 * The caller's keys from `my_permissions`, once per request. `context()`, not
 * `cached()`: route handlers and actions have no cache scope (`cacheLife()`
 * throws there, and the authorizer reported that as a 403).
 */
async function myPermissions(): Promise<readonly string[] | undefined> {
  const { db } = await bsbShell.context();
  const result = await db.permissions.permissions();

  return result.ok ? result.data.keys : undefined;
}
