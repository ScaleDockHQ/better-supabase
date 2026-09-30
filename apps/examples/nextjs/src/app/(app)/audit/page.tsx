import { Suspense } from "react";

import { Panel, PanelSkeleton } from "@/components/ui/panel";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function AuditPage() {
  return (
    <>
      <h1>Audit log</h1>
      <Suspense fallback={<PanelSkeleton />}>
        <PermissionGate permission="audit.read">
          <Panel>
            <p>Who changed what, and when.</p>
          </Panel>
        </PermissionGate>
      </Suspense>
    </>
  );
}
