"use server";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const Installation = v.object({
  configuration_id: v.string(),
  team_id: v.nullable(v.string()),
  status: v.picklist(["active", "suspended", "removed"]),
});

const Resources = v.array(
  v.object({
    external_id: v.string(),
    name: v.string(),
    status: v.picklist(["pending", "ready", "suspended", "deleted"]),
    plan_id: v.nullable(v.string()),
  }),
);

export interface MarketplaceView {
  readonly configurationId: string;
  readonly teamId: string | null;
  readonly status: "active" | "removed" | "suspended";
  readonly resources: readonly {
    readonly externalId: string;
    readonly name: string;
    readonly status: "deleted" | "pending" | "ready" | "suspended";
    readonly planId: string | null;
  }[];
}

/**
 * Links a Vercel configuration to this organization and returns its resources.
 * Only the service role calls the Marketplace functions, so the action runs
 * them after the `settings.manage` check.
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
  async ({ configurationId }, { tenant }) => {
    const api = bsb.admin().$client.schema("api");

    const linked = await api.rpc("upsert_marketplace_installation", {
      configuration_id: configurationId,
      tenant,
    });

    if (linked.error) {
      return err(dbError("unexpected", linked.error.message));
    }

    const resources = await api.rpc("marketplace_resources", {
      configuration_id: configurationId,
    });

    if (resources.error) {
      return err(dbError("unexpected", resources.error.message));
    }

    const installation = v.parse(Installation, linked.data);

    const view: MarketplaceView = {
      configurationId: installation.configuration_id,
      teamId: installation.team_id,
      status: installation.status,
      resources: v
        .parse(Resources, resources.data)
        .map((resource) => ({
          externalId: resource.external_id,
          name: resource.name,
          status: resource.status,
          planId: resource.plan_id,
        })),
    };

    return ok(view);
  },
);
