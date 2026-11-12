import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import {
  CalibrationOverview,
  CreateMeterDialog,
  CreatePlanDialog,
  MaintenanceListSkeleton,
  MeterOverview,
  PlanOverview,
  RecordCalibrationDialog,
} from "@/features/maintenance/components/maintenance-overviews";
import { generateWorkOrders } from "@/features/maintenance/maintenance-actions";
import { ActionButton } from "@/features/sales/components/action-button";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header, the tabs and the list frame at once; the
// rows render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function MaintenancePage({
  searchParams,
}: PageProps<"/[locale]/maintenance">) {
  const t = useExtracted("maintenance");

  return (
    <>
      <PageHeader
        title={t("Maintenance")}
        description={t(
          "Preventive plans by time, meter or calendar, the meters that drive them and the calibrations of your instruments.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="maintenance.manage">
              <ActionButton
                action={generateWorkOrders}
                input={{}}
                label={t("Open work orders for due plans")}
                successMessage={t("Work orders opened")}
              />
              <CreatePlanDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<MaintenanceListSkeleton />}>
        {searchParams.then((raw) => {
          const view = activeTab(raw, ["plans", "meters", "calibrations"]);

          return (
            <>
              <RecordDetailTabs
                base="/maintenance"
                active={view}
                tabs={[
                  { value: "plans", label: t("Plans") },
                  { value: "meters", label: t("Meters") },
                  { value: "calibrations", label: t("Calibrations") },
                ]}
              />
              {view === "meters" ? (
                <>
                  <div className="flex gap-2">
                    <Suspense fallback={null}>
                      <PermissionGate permission="maintenance.manage">
                        <CreateMeterDialog />
                      </PermissionGate>
                    </Suspense>
                  </div>
                  <MeterOverview query={parseBlockList(raw)} />
                </>
              ) : view === "calibrations" ? (
                <>
                  <div className="flex gap-2">
                    <Suspense fallback={null}>
                      <PermissionGate permission="maintenance.record">
                        <RecordCalibrationDialog />
                      </PermissionGate>
                    </Suspense>
                  </div>
                  <CalibrationOverview query={parseBlockList(raw)} />
                </>
              ) : (
                <PlanOverview query={parseBlockList(raw)} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
