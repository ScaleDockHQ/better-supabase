import "server-only";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

import { PORTAL_TAG } from "./portal-cache";

export interface PortalGrant {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly actions: readonly string[];
  readonly expiresAt: string | null;
}

export interface PortalMembership {
  readonly id: string;
  readonly organizationId: string;
  readonly party: string | null;
  readonly grants: readonly PortalGrant[];
}

export type PortalState =
  | { readonly kind: "ok"; readonly memberships: readonly PortalMembership[] }
  | { readonly kind: "error" };

async function loadPortal(): Promise<readonly PortalMembership[]> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(PORTAL_TAG);

  const memberships = await db.guests.mine().orThrow();

  return memberships.map((guest): PortalMembership => ({
    id: guest.id,
    organizationId: guest.organizationId,
    party: guest.party ? guest.party.type : null,
    grants: guest.grants.map((grant): PortalGrant => ({
      id: grant.id,
      subjectType: grant.subject.type,
      subjectId: grant.subject.id,
      actions: grant.actions,
      expiresAt: grant.expiresAt?.toString() ?? null,
    })),
  }));
}

/** The organizations the caller is a guest of, with the records shared. */
export async function getPortal(): Promise<PortalState> {
  try {
    return { kind: "ok", memberships: await loadPortal() };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
