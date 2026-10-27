import type { NextOptions } from "better-supabase/next";

import "server-only";
import { permissionsAuthorizer } from "better-supabase/blocks/permissions";
import { createNext } from "better-supabase/next";

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
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
  // `permission` on actions, routes and resources: granted from the token's
  // `permissions` claim, and from `my_permissions` when the token can't say.
  authorizer: permissionsAuthorizer({ permissions, load: myPermissions }),
};

export const bsb = createNext(betterSupabase, options);

/**
 * The caller's keys from `my_permissions`, for a token whose claim is missing
 * or truncated. The authorizer calls it once per request.
 */
async function myPermissions(): Promise<readonly string[] | undefined> {
  const { db } = await bsb.cached();
  const result = await db.permissions.permissions();

  return result.ok ? result.data.keys : undefined;
}
