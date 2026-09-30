import { Suspense } from "react";

import { Panel, PanelSkeleton } from "@/components/ui/panel";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function SettingsPage() {
  return (
    <>
      <h1>Settings</h1>
      <Suspense fallback={<PanelSkeleton />}>
        <PermissionGate permission="settings.manage">
          <Panel>
            <p>Organization settings.</p>
          </Panel>
        </PermissionGate>
      </Suspense>
    </>
  );
}
