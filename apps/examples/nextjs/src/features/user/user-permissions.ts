import type { AuthSession } from 'better-supabase/react';

import type { Claims, Role } from '@/lib/claims';

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

export type Permission =
  | 'customers.read'
  | 'customers.write'
  | 'reports.read'
  | 'users.manage'
  | 'billing.manage'
  | 'audit.read'
  | 'settings.manage';

/** Mirrors `rbac.role_permissions` (supabase/migrations/*_rbac.sql). */
const grants: Readonly<Record<Role, readonly Permission[]>> = {
  admin: [
    'customers.read',
    'customers.write',
    'reports.read',
    'users.manage',
    'billing.manage',
    'audit.read',
    'settings.manage',
  ],
  member: ['customers.read'],
};

const isRole = (role: string): role is Role => Object.hasOwn(grants, role);

/**
 * The global `user_role` the hook writes (top level, else `app_metadata`),
 * plus the roles of the membership in the active tenant (`tenant_id`).
 * Never `user_metadata`: users can edit that.
 */
export function rolesOf(claims: Claims): Role[] {
  const global = claims.user_role ?? claims.app_metadata?.user_role;
  const tenant = claims.tenant_id ?? claims.app_metadata?.tenant_id;
  const membership = claims.memberships?.find(
    (entry) => entry.scope === 'tenant' && entry.id === tenant,
  );
  const roles = new Set<Role>(global ? [global] : []);
  for (const role of membership?.roles ?? []) {
    if (isRole(role)) roles.add(role);
  }
  return [...roles];
}

export function can(
  session: AuthSession<Claims>,
  permission: Permission,
): boolean {
  if (session.kind !== 'user') return false;
  return rolesOf(session.claims).some((role) =>
    grants[role].includes(permission),
  );
}
