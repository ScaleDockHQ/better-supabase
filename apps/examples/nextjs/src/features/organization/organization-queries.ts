import "server-only";
import * as v from "valibot";

import { avatars, avatarSrc } from "@/lib/buckets";
import { Role } from "@/lib/claims";
import { bsb } from "@/lib/supabase/server";

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

interface MyOrganizationRow {
  readonly id: string | null;
  readonly name: string | null;
  readonly slug: string | null;
  readonly role: string | null;
  readonly plan: string | null;
}

/** Rows of `public.my_organizations()` as summaries, skipping incomplete ones. */
export function toOrganizationSummaries(
  rows: readonly MyOrganizationRow[],
): readonly OrganizationSummary[] {
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

/**
 * The caller's organizations, most recently used first, from
 * `public.my_organizations()`
 * (supabase/schemas/public/functions/my_organizations.sql).
 */
export async function getMyOrganizations(): Promise<
  readonly OrganizationSummary[]
> {
  "use cache: private";
  const { db, session } = await bsb.cached();

  if (session.kind !== "user") {
    return [];
  }

  return toOrganizationSummaries(await db.$rpc("my_organizations").orThrow());
}

interface MemberRow {
  readonly userId: string | null;
  readonly role: string | null;
  readonly fullName: string | null;
  readonly email: string | null;
  readonly avatarPath: string | null;
  readonly avatarUrl: string | null;
  readonly joinedAt: string | null;
}

/**
 * Rows of `public.organization_members(organization)` with their avatar URLs,
 * skipping incomplete ones. The members table's server action uses it too.
 */
export function toMembers(
  rows: readonly MemberRow[],
  supabase: Parameters<typeof avatars.connect>[0],
): readonly Member[] {
  const storage = avatars.connect(supabase);

  return rows.flatMap((row) =>
    row.userId
      ? [
          {
            userId: row.userId,
            role: roleOrMember(row.role),
            name: row.fullName,
            email: row.email,
            avatarUrl: avatarSrc(storage, row),
            joinedAt: row.joinedAt ?? "",
          },
        ]
      : [],
  );
}

export async function getMembers(
  organizationId: string,
): Promise<readonly Member[]> {
  "use cache: private";
  const { db, supabase } = await bsb.cached();

  const rows = await db
    .$rpc("organization_members", { organization: organizationId })
    .orThrow();

  return toMembers(rows, supabase);
}

/** Pending invitations. The function refuses callers without `members.invite`. */
export async function getInvitations(
  organizationId: string,
): Promise<readonly PendingInvitation[]> {
  "use cache: private";
  const { db } = await bsb.cached();

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
