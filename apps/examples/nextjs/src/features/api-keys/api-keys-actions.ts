"use server";

import { ok } from "better-supabase";

import { gettingStarted } from "@/features/onboarding/checklist";
import { bsbShell } from "@/lib/supabase/server-shell";

/**
 * Runs after `useApiKeys` created a key from the browser (the api-keys module
 * checks and audits it itself): completes the onboarding step.
 */
export const apiKeyCreated = bsbShell.action(
  { requireTenant: true, permission: "api_keys.own" },
  async (_input, { tenant: organizationId, db }) => {
    await db.onboarding.complete({
      checklist: gettingStarted,
      step: "api-key",
      organizationId,
    });

    return ok(true);
  },
);
