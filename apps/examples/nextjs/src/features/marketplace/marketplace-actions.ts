"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { MARKETPLACE_TAG } from "./marketplace-cache";

/**
 * Links a Vercel configuration to this organization. Only the service role
 * calls `upsert_marketplace_installation`, so the action runs it after the
 * `settings.manage` check. The page then reads the installation back through
 * the member-readable `marketplace_installation_for`.
 */
export const connectInstallation = bsb.action(
  {
    input: v.object({
      configurationId: v.pipe(
        v.string(),
        v.trim(),
        v.minLength(1),
        v.maxLength(120),
      ),
    }),
    requireTenant: true,
    permission: "settings.manage",
  },
  async ({ configurationId }, { tenant, auth }) => {
    const linked = await bsb
      .admin()
      .$client.schema("api")
      .rpc("upsert_marketplace_installation", {
        configuration_id: configurationId,
        tenant,
      });

    if (linked.error) {
      return err(dbError("unexpected", linked.error.message));
    }

    await refreshCaller(auth, [MARKETPLACE_TAG]);

    return ok(configurationId);
  },
);
