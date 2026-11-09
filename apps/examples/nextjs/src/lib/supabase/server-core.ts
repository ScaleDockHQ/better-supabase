import type { NextOptions } from "better-supabase/next";

import "server-only";
import { permissionsAuthorizer } from "better-supabase/blocks/permissions";
import { createNext } from "better-supabase/next";

import { env } from "@/env";

import { permissions } from "./blocks.config";
import { betterSupabaseCore } from "./core";

const options: NextOptions = {
  debug: {
    enabled: env.EXPOSE_TESTING_API === "1",
    budget: { calls: 8, waves: 2 },
    route: "/api/bs-stats",
  },
  replicas: { pinMs: 5000 },
  authorizer: permissionsAuthorizer({ permissions, load: myPermissions }),
};

/**
 * `bsb` over the core block set, for routes that need no other block. It has
 * its own session memo, so a route imports this or `server.ts`, not both.
 */
export const bsbCore = createNext(betterSupabaseCore, options);

/** The caller's keys from `my_permissions`, once per request. */
async function myPermissions(): Promise<readonly string[] | undefined> {
  const { db } = await bsbCore.cached();
  const result = await db.permissions.permissions();

  return result.ok ? result.data.keys : undefined;
}
