import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { MARKETPLACE_TAG } from "./marketplace-cache";

const InstallationRow = v.object({
  configuration_id: v.string(),
  team_id: v.nullable(v.string()),
  status: v.picklist(["active", "suspended", "removed"]),
  created_at: v.string(),
});

const ResourceRow = v.object({
  external_id: v.string(),
  name: v.string(),
  status: v.picklist(["pending", "ready", "suspended", "deleted"]),
  plan_id: v.nullable(v.string()),
  created_at: v.string(),
});

export interface MarketplaceResourceView {
  readonly externalId: string;
  readonly name: string;
  readonly status: "deleted" | "pending" | "ready" | "suspended";
  readonly planId: string | null;
  readonly createdAt: string;
}

export interface MarketplaceInstallationView {
  readonly configurationId: string;
  readonly teamId: string | null;
  readonly status: "active" | "removed" | "suspended";
  readonly createdAt: string;
  readonly resources: readonly MarketplaceResourceView[];
}

export type MarketplaceRead =
  | { readonly kind: "ok"; readonly installation: MarketplaceInstallationView }
  | { readonly kind: "none" }
  | { readonly kind: "error" };

/**
 * The installation linked to the caller's organization and its resources,
 * through the member-readable `marketplace_installation_for` and
 * `marketplace_resources_for` (the tenant-scoped read of PR #902). The reply
 * has no secret handles, so the page needs no service role.
 */
async function loadInstallation(): Promise<
  MarketplaceInstallationView | undefined
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(MARKETPLACE_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return undefined;
  }

  // One wave: both reads are member-scoped by tenant, so neither waits for the other.
  const [installation, resources] = await Promise.all([
    db
      .$api(
        "marketplace_installation_for",
        { tenant },
        { returns: v.nullable(InstallationRow) },
      )
      .orThrow(),
    db
      .$api(
        "marketplace_resources_for",
        { tenant },
        { returns: v.array(ResourceRow) },
      )
      .orThrow(),
  ]);

  if (!installation) {
    return undefined;
  }

  return {
    configurationId: installation.configuration_id,
    teamId: installation.team_id,
    status: installation.status,
    createdAt: installation.created_at,
    resources: resources.map((resource) => ({
      externalId: resource.external_id,
      name: resource.name,
      status: resource.status,
      planId: resource.plan_id,
      createdAt: resource.created_at,
    })),
  };
}

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
export async function getMarketplace(): Promise<MarketplaceRead> {
  try {
    const installation = await loadInstallation();

    return installation ? { kind: "ok", installation } : { kind: "none" };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/**
 * One resource of the organization's installation; `undefined` when it is not
 * there.
 */
export async function getMarketplaceResource(
  externalId: string,
): Promise<
  | {
      readonly installation: MarketplaceInstallationView;
      readonly resource: MarketplaceResourceView;
    }
  | undefined
> {
  const read = await getMarketplace();

  if (read.kind !== "ok") {
    return undefined;
  }

  const resource = read.installation.resources.find(
    (each) => each.externalId === externalId,
  );

  return resource ? { installation: read.installation, resource } : undefined;
}
