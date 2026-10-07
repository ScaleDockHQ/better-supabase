import "server-only";
import * as v from "valibot";

import { Role } from "@/lib/claims";
import { bs } from "@/lib/supabase/server";

export interface OrganizationSummary {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly role: Role;
  readonly plan: string;
}

export interface Member {
  readonly userId: string;
  readonly role: Role;
  readonly name: string | null;
  readonly email: string | null;
  readonly avatarUrl: string | null;
  readonly joinedAt: string;
}

export interface PendingInvitation {
  readonly id: string;
  readonly email: string;
  readonly role: Role;
  readonly expiresAt: string;
}

const roleOrMember = (value: string | null): Role =>
  v.is(Role, value) ? value : "member";

/**
 * The caller's organizations, most recently used first, from
 * `public.my_organizations()` (supabase/schemas/950_app_reads.sql).
 */
export async function getMyOrganizations(): Promise<
  readonly OrganizationSummary[]
> {
  "use cache: private";
  const { db, session } = await bs.cached();
  if (session.kind !== "user") return [];
  const rows = await db.$rpc("my_organizations").orThrow();
  return rows.flatMap((row) =>
    row.id && row.name
      ? [
          {
            id: row.id,
            name: row.name,
            slug: row.slug ?? "",
            role: roleOrMember(row.role),
            plan: row.plan ?? "free",
          },
        ]
      : [],
  );
}

/** Takes the organization as an argument: the private cache keys on it. */
export async function getMembers(
  organizationId: string,
): Promise<readonly Member[]> {
  "use cache: private";
  const { db } = await bs.cached();
  const rows = await db
    .$rpc("organization_members", { organization: organizationId })
    .orThrow();
  return rows.flatMap((row) =>
    row.userId
      ? [
          {
            userId: row.userId,
            role: roleOrMember(row.role),
            name: row.fullName,
            email: row.email,
            avatarUrl: row.avatarUrl,
            joinedAt: row.joinedAt ?? "",
          },
        ]
      : [],
  );
}

/** Pending invitations. The function refuses callers without `members.invite`. */
export async function getInvitations(
  organizationId: string,
): Promise<readonly PendingInvitation[]> {
  "use cache: private";
  const { db } = await bs.cached();
  const rows = await db
    .$rpc("organization_invitations", { organization: organizationId })
    .orThrow();
  return rows.flatMap((row) =>
    row.id && row.email
      ? [
          {
            id: row.id,
            email: row.email,
            role: roleOrMember(row.role),
            expiresAt: row.expiresAt ?? "",
          },
        ]
      : [],
  );
}
