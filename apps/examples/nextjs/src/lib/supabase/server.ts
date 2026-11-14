import type { NextOptions } from "better-supabase/next";

import "server-only";
import { permissionsAuthorizer } from "better-supabase/blocks/permissions";
import { createNext, supportSessions } from "better-supabase/next";
import { createPostgres } from "better-supabase/postgres";
import { createServer, sqlSupportStore } from "better-supabase/server";

import { env } from "@/env";

import { permissions } from "./blocks.generated";
import { betterSupabase } from "./index";
import { sharedCounters } from "./session-counters";

const options: NextOptions = {
  debug: {
    // The testing build checks each navigation's budget against `next start`.
    enabled: env.EXPOSE_TESTING_API === "1",
    budget: { calls: 8, waves: 2 },
    // Matches `src/app/api/bs-stats/route.ts`, where `bsb.debugRoute()` is mounted.
    route: "/api/bs-stats",
  },
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
  // `permission` on actions, routes and resources: granted from the token's
  // `permissions` claim, and from `my_permissions` when the token can't say.
  authorizer: permissionsAuthorizer({ permissions, load: myPermissions }),
};

const counters = sharedCounters();

/**
 * Support sessions need the `better_supabase` schema, which the Data API does
 * not serve, so the store connects with `DATABASE_URL`. Without it the app runs
 * with no "View as" action and `startSupport` refuses.
 */
const support = env.DATABASE_URL
  ? supportSessions({
      store: sqlSupportStore(
        createPostgres({ connectionString: env.DATABASE_URL, max: 3 }),
      ),
      // The database decides who may start one (`is_platform('impersonation.start')`),
      // and a second admin approves the request on /approvals.
      authorize: "store",
      policy: { ttl: 30 * 60, requireReason: true },
    })
  : undefined;

// Built here, not inside `createNext`, so the testing route can read its
// session memo: how many renders verified a token instead of reusing one.
const serverOptions = { ...options, sessions: { counters } };

const bsbServer = createServer(
  betterSupabase,
  support ? { ...serverOptions, support } : serverOptions,
);

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
  // Not a private cache scope: a Server Action checks permissions too, and a private
  // cache scope can't open there (EX-1107).
  const { db } = await bsb.context();
  const result = await db.permissions.permissions();

  return result.ok ? result.data.keys : undefined;
}
