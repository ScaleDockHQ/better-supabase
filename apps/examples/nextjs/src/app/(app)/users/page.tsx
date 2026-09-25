import { Suspense } from 'react';

import { Panel, PanelSkeleton } from '@/components/ui/panel';
import { PermissionGate } from '@/features/user/components/permission-gate';

export const instant = true;

export default function UsersPage() {
  return (
    <>
      <h1>Users</h1>
      <Suspense fallback={<PanelSkeleton />}>
        <PermissionGate permission="users.manage">
          <Panel>
            <p>Invite people and assign roles (rbac.user_roles).</p>
          </Panel>
        </PermissionGate>
      </Suspense>
    </>
  );
}
