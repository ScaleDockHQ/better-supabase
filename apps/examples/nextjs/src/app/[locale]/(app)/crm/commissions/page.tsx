import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import { SalesListSkeleton } from "@/features/sales/components/crm-overviews";
import {
  BuildStatementDialog,
  CommissionOverview,
  CreatePlanDialog,
} from "@/features/sales/components/revenue-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

const TABS = ["commissions", "statements", "plans"] as const;

export default function CommissionsPage({
  searchParams,
}: PageProps<"/[locale]/crm/commissions">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Commissions")}
        description={t("What your sellers earn on the deals they close.")}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="commissions.manage">
              <BuildStatementDialog />
              <CreatePlanDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => {
          const tab = activeTab(raw, TABS);

          return (
            <>
              <RecordDetailTabs
                base="/crm/commissions"
                active={tab}
                tabs={[
                  { value: "commissions", label: t("Commissions") },
                  { value: "statements", label: t("Statements") },
                  { value: "plans", label: t("Plans") },
                ]}
              />
              <CommissionOverview
                query={parseBlockList(raw)}
                tab={
                  tab === "plans" || tab === "statements" ? tab : "commissions"
                }
              />
            </>
          );
        })}
      </Suspense>
    </>
  );
}
