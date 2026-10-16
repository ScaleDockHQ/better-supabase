"use server";

import { ok } from "better-supabase";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * Runs after `useApiKeys` created a key from the browser (the api-keys
 * module checks and audits it itself): completes the onboarding step.
 */
export const apiKeyCreated = bs.action(
  {
    requireTenant: true,
    authorize: (session) => can(session, "api_keys.own"),
  },
  async (_input, { tenant: organizationId, supabase }) => {
    await blocks(supabase).onboarding.complete("api-key", organizationId);
    return ok(true);
  },
);
