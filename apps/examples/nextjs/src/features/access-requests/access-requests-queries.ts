import type { AccessRequestStatus } from "better-supabase/blocks/access-requests";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import type { Role } from "@/lib/claims";

import { getMembers } from "@/features/organization/organization-queries";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can, roleOf } from "@/features/user/user-permissions";
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

  const [{ session, db, auth }, permissions] = await Promise.all([
    bsb.cached(),
    getPermissions(),
  ]);

  const tenant = tenantOf(session);

  if (!tenant || auth.kind !== "user") {
    return null;
  }

  const readsAll = can(permissions, "access_requests.read");

  const [requests, names] = await Promise.all([
    db.accessRequests
      .list({ organizationId: tenant, mine: !readsAll, pageSize: 50 })
      .orThrow(),
    memberNames(tenant),
  ]);

  return {
    canDecide: can(permissions, "members.update_role"),
    requests: requests.flatMap((request) =>
      request.target === "role"
        ? [
            {
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
            },
          ]
        : [],
    ),
    role: roleOf(session),
    userId: auth.user.id,
  };
}
