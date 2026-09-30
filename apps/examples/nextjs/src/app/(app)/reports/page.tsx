import { Suspense } from "react";

import { Panel, PanelSkeleton } from "@/components/ui/panel";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function ReportsPage() {
  return (
    <>
      <h1>Reports</h1>
      <Suspense fallback={<PanelSkeleton />}>
        <PermissionGate permission="reports.read">
          <Panel>
            <p>Revenue and pipeline reports.</p>
          </Panel>
        </PermissionGate>
      </Suspense>
    </>
  );
}
