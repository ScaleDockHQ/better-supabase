import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

import { MARKETPLACE_TAG } from "./marketplace-cache";

export interface MarketplaceResourceView {
  readonly externalId: string;
  readonly name: string;
  readonly status: "deleted" | "pending" | "ready" | "suspended";
  readonly planId: string | null;
}

export interface MarketplaceInstallationView {
  readonly configurationId: string;
  readonly teamId: string | null;
  readonly status: "active" | "removed" | "suspended";
  readonly resources: readonly MarketplaceResourceView[];
}

export type MarketplaceRead =
  | { readonly kind: "ok"; readonly installation: MarketplaceInstallationView }
  | { readonly kind: "none" }
  | { readonly kind: "error" };

/**
 * The installation linked to the caller's organization and its resources,
 * through the member-readable `installationFor` and `resourcesFor` (the
 * tenant-scoped read of PR #902). The reply has no secret handles, so the page
 * needs no service role.
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
    db.vercelMarketplace.installationFor(tenant).orThrow(),
    db.vercelMarketplace.resourcesFor(tenant).orThrow(),
  ]);

  if (!installation) {
    return undefined;
  }

  return {
    configurationId: installation.configurationId,
    teamId: installation.teamId ?? null,
    status: installation.status,
    resources: resources.map((resource) => ({
      externalId: resource.externalId,
      name: resource.name,
      status: resource.status,
      planId: resource.planId ?? null,
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
