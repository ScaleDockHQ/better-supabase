import type { NextOptions } from "better-supabase/next";

import "server-only";
import { permissionsAuthorizer } from "better-supabase/blocks/permissions";
import { createNext } from "better-supabase/next";
import { createServer } from "better-supabase/server";

import { env } from "@/env";

import { permissions } from "./blocks.generated";
import { betterSupabase } from "./index";

const options: NextOptions = {
  debug: {
    // The testing build checks each navigation's budget against `next start`.
    enabled: env.EXPOSE_TESTING_API === "1",
    budget: { calls: 8, waves: 2 },
    // Matches `src/app/api/bs-stats/route.ts`, where `bsb.debugRoute()` is mounted.
    route: "/api/bs-stats",
  },
  // `bsb.bootstrap()` calls `api.bootstrap_<rpc>`: the config's `sql.api`,
  // the one module schema PostgREST exposes.
  bootstrapSchema: "api",
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
  // `permission` on actions, routes and resources: granted from the token's
  // `permissions` claim, and from `my_permissions` when the token can't say.
  authorizer: permissionsAuthorizer({ permissions, load: myPermissions }),
};

// Built here, not inside `createNext`, so the testing route can read its
// session memo: how many renders verified a token instead of reusing one.
const bsbServer = createServer(betterSupabase, options);

export const bsb = createNext(betterSupabase, {
  ...options,
  server: bsbServer,
});

/** Hits and misses of the verified-session memo, for `/api/bs-sessions`. */
export function sessionStats() {
  return bsbServer.sessions.stats();
}

/**
 * The caller's keys from `my_permissions`, for a token whose claim is missing
 * or truncated. The authorizer calls it once per request.
 */
async function myPermissions(): Promise<readonly string[] | undefined> {
  const { db } = await bsb.cached();
  const result = await db.permissions.permissions();

  return result.ok ? result.data.keys : undefined;
}
