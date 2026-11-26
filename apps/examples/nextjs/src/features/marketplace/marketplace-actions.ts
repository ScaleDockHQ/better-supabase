"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
    tags: () => [tags.marketplace()],
    refresh: true,
  },
  async ({ configurationId }, { tenant }) => {
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

    return ok(configurationId);
  },
);
