import type { AuthSession } from 'better-supabase/react';

// A deliberately small, hand-written permission check that runs on the server
// and the client. For real apps use PermDock (https://github.com/ScaleDockHQ/PermDock):
// `subjectFromSupabase(session.claims)` reads the same `user_role` claim.

export type Role = 'admin' | 'member';

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

const isRole = (value: unknown): value is Role =>
  value === 'admin' || value === 'member';

/**
 * `user_role` as the custom access token hook writes it (top level), else
 * from `app_metadata`. Never `user_metadata`: users can edit that.
 */
export function rolesOf(claims: Readonly<Record<string, unknown>>): Role[] {
  const app = claims['app_metadata'];
  const raw =
    claims['user_role'] ??
    (typeof app === 'object' && app !== null
      ? (app as Readonly<Record<string, unknown>>)['user_role']
      : undefined);
  return (Array.isArray(raw) ? raw : [raw]).filter(isRole);
}

export function can(session: AuthSession, permission: Permission): boolean {
  if (session.kind !== 'user') return false;
  return rolesOf(session.claims).some((role) =>
    grants[role].includes(permission),
  );
}
