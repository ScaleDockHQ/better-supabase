import type { AuthSession } from 'better-supabase/react';

import type { Claims, Role } from '@/lib/claims';

// A deliberately small, hand-written permission check that runs on the server
// and the client. For real apps use PermDock (https://github.com/ScaleDockHQ/PermDock):
// `subjectFromSupabase(session.claims)` reads the same `user_role` claim.

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

/**
 * `user_role` as the custom access token hook writes it (top level), else
 * from `app_metadata`. Never `user_metadata`: users can edit that.
 */
export function rolesOf(claims: Claims): Role[] {
  const role = claims.user_role ?? claims.app_metadata?.user_role;
  return role ? [role] : [];
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
