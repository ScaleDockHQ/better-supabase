import type { AccessRequestStatus } from "better-supabase/blocks/access-requests";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import type { Role } from "@/lib/claims";

import { getMembers } from "@/features/organization/organization-queries";
import { can, roleOf } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

export interface AccessRequestRow {
  readonly id: string;
  readonly userId: string;
  readonly requester: string;
  readonly role: string;
  readonly reason: string | null;
  readonly duration: string | null;
  readonly status: AccessRequestStatus;
  readonly approvalId: string | null;
  readonly createdAt: string;
  readonly expiresAt: string | null;
}

export interface AccessRequestsData {
  readonly userId: string;
  readonly role: Role | undefined;
  readonly canDecide: boolean;
  readonly requests: readonly AccessRequestRow[];
}

async function memberNames(
  organizationId: string,
): Promise<ReadonlyMap<string, string>> {
  try {
    const members = await getMembers(organizationId);

    return new Map(
      members.map((member) => [
        member.userId,
        member.name ?? member.email ?? member.userId,
      ]),
    );
  } catch (error) {
    unstable_rethrow(error);

    return new Map();
  }
}

/**
 * The active organization's access requests, newest first. Readers of the
 * organization see every request; others see their own. A failed read throws,
 * so it is never cached and Retry reads again.
 */
export async function loadAccessRequests(): Promise<AccessRequestsData | null> {
  "use cache: private";
  const { session, supabase, auth } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant || auth.kind !== "user") {
    return null;
  }

  const readsAll = can(session, "access_requests.read");

  const [requests, names] = await Promise.all([
    blocks(supabase)
      .accessRequests.list(tenant, { mine: !readsAll, pageSize: 50 })
      .orThrow(),
    memberNames(tenant),
  ]);

  return {
    canDecide: can(session, "members.update_role"),
    requests: requests.map((request) => ({
      approvalId: request.approvalId ?? null,
      createdAt: request.createdAt.toString(),
      duration: request.duration?.toString() ?? null,
      expiresAt: request.expiresAt?.toString() ?? null,
      id: request.id,
      reason: request.reason ?? null,
      requester: names.get(request.userId) ?? request.userId,
      role: request.role,
      status: request.status,
      userId: request.userId,
    })),
    role: roleOf(session),
    userId: auth.user.id,
  };
}
