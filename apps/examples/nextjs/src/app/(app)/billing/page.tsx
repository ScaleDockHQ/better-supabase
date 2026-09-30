import { Suspense } from "react";

import { Panel, PanelSkeleton } from "@/components/ui/panel";
import { PlanFeatures } from "@/features/billing/components/plan-features";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function BillingPage() {
  return (
    <>
      <h1>Billing</h1>
      <Suspense fallback={<PanelSkeleton />}>
        <PermissionGate permission="billing.manage">
          <Panel>
            <p>Plans, invoices and payment methods.</p>
            <PlanFeatures />
          </Panel>
        </PermissionGate>
      </Suspense>
    </>
  );
}
