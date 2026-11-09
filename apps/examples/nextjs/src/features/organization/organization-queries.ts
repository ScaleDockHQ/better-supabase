import "server-only";
import * as v from "valibot";

import { avatars, avatarSrc } from "@/lib/buckets";
import { Role } from "@/lib/claims";
import { bsbShell as bsb } from "@/lib/supabase/server-shell";

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
 * One page of the caller's organizations, most recently used first.
 * `public.my_organizations` takes `page_size` and a cursor of
 * `after_last_used_at`, `after_name` and `after_id`. The generated argument
 * type stays empty until `db gen` sees the new signature, so the page is passed
 * through a cast. The SQL default is the same page of 50.
 */
export async function getMyOrganizations(): Promise<
  readonly OrganizationSummary[]
> {
  "use cache: private";
  const { db, session } = await bsb.cached();

  if (session.kind !== "user") {
    return [];
  }

  // SAFETY: the function arguments are page_size, after_last_used_at,
  // after_name and after_id. Generated Args are still empty.
  const page = { page_size: 50 } as never;
  const rows = await db.$rpc("my_organizations", page).orThrow();

  return toOrganizationSummaries(rows);
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

  return readMembers(await bsb.cached(), organizationId);
}

/** The same read for a function that already runs in a private scope. */
export async function readMembers(
  { db, supabase }: Awaited<ReturnType<typeof bsb.cached>>,
  organizationId: string,
): Promise<readonly Member[]> {
  const rows = await db
    .$rpc("organization_members", { organization: organizationId })
    .orThrow();

  return toMembers(rows, supabase);
}

/**
 * Pending invitations, from `organizations.overview`. The function refuses
 * callers without `members.invite`.
 */
export async function getInvitations(
  organizationId: string,
): Promise<readonly PendingInvitation[]> {
  "use cache: private";
  const { db } = await bsb.cached();

  const { invitations } = await db.$blocks.organizations
    .overview(organizationId)
    .orThrow();

  return invitations.map((invitation) => ({
    id: invitation.id,
    email: invitation.email,
    role: roleOrMember(invitation.role),
    expiresAt: invitation.expiresAt?.toString() ?? "",
  }));
}

export interface InvitationSummary {
  readonly status: "pending" | "accepted" | "declined" | "revoked" | "expired";
  readonly email: string;
  readonly role: Role;
  readonly organizationName: string | null;
  /** ISO 8601. */
  readonly expiresAt: string;
}

/**
 * What an invitation link points to, callable without a session
 * (`invitation_preview`). `null` for an unknown token.
 */
export async function getInvitationPreview(
  token: string,
): Promise<InvitationSummary | null> {
  "use cache: private";
  const { db } = await bsb.cached();

  const preview = await db.$blocks.organizations
    .previewInvitation(token)
    .orThrow();

  if (!preview) {
    return null;
  }

  const name = preview.organization?.["name"];

  return {
    status: preview.status,
    email: preview.email,
    role: v.is(Role, preview.role) ? preview.role : "member",
    organizationName: v.is(v.string(), name) ? name : null,
    expiresAt: preview.expiresAt.toString(),
  };
}
