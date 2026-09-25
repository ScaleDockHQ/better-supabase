import type { ReactNode } from 'react';

import { type Permission, can } from '../user-permissions';
import { getSession } from '../user-queries';

/**
 * Renders `children` only when the session has `permission`. UI only: the
 * data behind it is still protected by RLS and by each Server Action.
 */
export async function PermissionGate({
  permission,
  children,
}: {
  permission: Permission;
  children: ReactNode;
}) {
  const session = await getSession();
  if (!can(session, permission)) {
    return (
      <p role="alert" className="forbidden">
        You need the <code>{permission}</code> permission to see this page.
      </p>
    );
  }
  return children;
}
