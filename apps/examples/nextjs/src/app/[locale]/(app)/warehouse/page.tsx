import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import { ActionButton } from "@/features/sales/components/action-button";
import { PermissionGate } from "@/features/user/components/permission-gate";
import {
  CountOverview,
  CreateCountPlanDialog,
  CreateAllocationDialog,
  CreatePickListDialog,
  CreateRuleDialog,
  CreateWaveDialog,
  ReceiveOrderDialog,
  PickOverview,
  PutawayOverview,
  WarehouseListSkeleton,
  WaveOverview,
} from "@/features/warehouse/components/warehouse-overviews";
import { runCountPlans } from "@/features/warehouse/warehouse-actions";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header, the tabs and the list frame at once; the
// rows render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function WarehousePage({
  searchParams,
}: PageProps<"/[locale]/warehouse">) {
  const t = useExtracted("warehouse");

  return (
    <>
      <PageHeader
        title={t("Warehouse")}
        description={t(
          "Pick lists and waves, putaway rules and slotting, and the cycle counts that keep the stock honest.",
        )}
      />
      <Suspense fallback={<WarehouseListSkeleton />}>
        {searchParams.then((raw) => {
          const view = activeTab(raw, ["picks", "waves", "putaway", "counts"]);

          return (
            <>
              <RecordDetailTabs
                base="/warehouse"
                active={view}
                tabs={[
                  { value: "picks", label: t("Pick lists") },
                  { value: "waves", label: t("Waves") },
                  { value: "putaway", label: t("Putaway") },
                  { value: "counts", label: t("Cycle counts") },
                ]}
              />
              <Suspense fallback={null}>
                <PermissionGate permission="warehouse.manage">
                  <div className="flex flex-wrap gap-2">
                    {view === "picks" ? (
                      <>
                        <CreatePickListDialog />
                        <CreateAllocationDialog />
                      </>
                    ) : null}
                    {view === "waves" ? <CreateWaveDialog /> : null}
                    {view === "putaway" ? (
                      <>
                        <CreateRuleDialog />
                        <ReceiveOrderDialog />
                      </>
                    ) : null}
                    {view === "counts" ? (
                      <>
                        <CreateCountPlanDialog />
                        <ActionButton
                          action={runCountPlans}
                          input={{}}
                          label={t("Open counts that are due")}
                          successMessage={t("Counts opened")}
                        />
                      </>
                    ) : null}
                  </div>
                </PermissionGate>
              </Suspense>
              {view === "waves" ? (
                <WaveOverview query={parseBlockList(raw)} />
              ) : view === "putaway" ? (
                <PutawayOverview query={parseBlockList(raw)} />
              ) : view === "counts" ? (
                <CountOverview query={parseBlockList(raw)} />
              ) : (
                <PickOverview query={parseBlockList(raw)} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
