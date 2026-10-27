"use server";

import { ok } from "better-supabase";

import { gettingStarted } from "@/features/onboarding/checklist";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

/**
 * Runs after `useApiKeys` created a key from the browser (the api-keys module
 * checks and audits it itself): completes the onboarding step.
 */
export const apiKeyCreated = bsb.action(
  {
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "api_keys.own"),
  },
  async (_input, { tenant: organizationId, db }) => {
    await db.onboarding.complete(gettingStarted, "api-key", organizationId);

    return ok(true);
  },
);
