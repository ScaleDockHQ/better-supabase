import type { AuthSession } from "better-supabase/react";

import * as v from "valibot";

import { type Claims, MEMBERSHIP_SCOPE, Role } from "@/lib/claims";

// A deliberately small, hand-written permission check that runs on the server
// and the client, over PermDock's claim contract. A real app replaces this
// file with PermDock (https://github.com/ScaleDockHQ/PermDock):
//
//   permdock rls generate                    # helpers and table policies
//   permdock supabase hook generate          # the only access token hook
//   const subject = subjectFromSupabaseSession(session);
//   const permdock = await createPermDock(policy, subject);
//   permdock.can(permissions.customers.read);
//
// `AuthSession` already has the `{ kind, claims }` shape PermDock reads, and
// `anon`, `service` and `invalid` sessions become PermDock's anonymous subject.
// See https://bettersupabase.com/docs/auth/permdock.

export const PERMISSIONS = [
  "customers.read",
  "customers.write",
  "organization.update",
  "organization.delete",
  "members.read",
  "members.invite",
  "members.remove",
  "members.update_role",
  "billing.read",
  "billing.manage",
  "audit.read",
  "settings.read",
  "settings.update",
  "api_keys.manage",
  "api_keys.own",
  "comments.create",
  "comments.moderate",
  "onboarding.complete",
] as const;

export type Permission = (typeof PERMISSIONS)[number];

/**
 * Mirrors `better_supabase.role_permissions` (supabase/schemas/045_access_contract.sql),
 * which RLS and the SQL modules check. Owners hold everything.
 */
const grants = {
  owner: "*",
  admin: [
    "customers.read",
    "customers.write",
    "organization.update",
    "members.read",
    "members.invite",
    "members.remove",
    "members.update_role",
    "billing.read",
    "billing.manage",
    "audit.read",
    "settings.read",
    "settings.update",
    "api_keys.manage",
    "api_keys.own",
    "comments.create",
    "comments.moderate",
    "onboarding.complete",
  ],
  member: [
    "customers.read",
    "members.read",
    "billing.read",
    "settings.read",
    "api_keys.own",
    "comments.create",
  ],
} satisfies Readonly<Record<Role, "*" | readonly Permission[]>>;

const RANK = { owner: 3, admin: 2, member: 1 } satisfies Record<Role, number>;

/** The active organization: the `tenant_id` claim (top level, else `app_metadata`). */
export function activeOrganizationId(
  session: AuthSession<Claims>,
): string | undefined {
  if (session.kind !== "user") return undefined;
  return session.claims.tenant_id ?? session.claims.app_metadata?.tenant_id;
}

/**
 * The role of the membership in the active organization, from the
 * `memberships` claim. Never `user_metadata`: users can edit that.
 */
export function roleOf(session: AuthSession<Claims>): Role | undefined {
  const tenant = activeOrganizationId(session);
  if (session.kind !== "user" || tenant === undefined) return undefined;
  const membership = session.claims.memberships?.find(
    (entry) => entry.scope === MEMBERSHIP_SCOPE && entry.id === tenant,
  );
  const roles = (membership?.roles ?? []).filter((role): role is Role =>
    v.is(Role, role),
  );
  return roles.toSorted((a, b) => RANK[b] - RANK[a])[0];
}

export function can(
  session: AuthSession<Claims>,
  permission: Permission,
): boolean {
  const role = roleOf(session);
  if (role === undefined) return false;
  const granted: "*" | readonly Permission[] = grants[role];
  return granted === "*" || granted.includes(permission);
}

/** The roles `role` may give, as `better_supabase.can_assign_as` decides. */
export function assignableRoles(role: Role): readonly Role[] {
  return (["member", "admin", "owner"] as const).filter(
    (candidate) => RANK[candidate] <= RANK[role],
  );
}

/** Whether the caller may give `role` to someone: as in `better_supabase.can_assign_as`. */
export function canAssign(session: AuthSession<Claims>, role: Role): boolean {
  const own = roleOf(session);
  return (
    own !== undefined &&
    (can(session, "members.invite") || can(session, "members.update_role")) &&
    RANK[own] >= RANK[role]
  );
}
