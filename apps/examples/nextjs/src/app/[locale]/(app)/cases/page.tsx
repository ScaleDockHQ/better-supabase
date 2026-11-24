import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { KpiBandSkeleton } from "@/components/record-list/kpi-band";
import {
  activeView,
  RecordViewSwitch,
} from "@/components/record-list/record-view-switch";
import {
  CaseKpis,
  CaseListSkeleton,
  CaseOverview,
} from "@/features/cases/components/case-overviews";
import {
  CaseBoardSection,
  CaseBoardSectionSkeleton,
  CaseDetailSection,
  CaseDetailSectionSkeleton,
} from "@/features/cases/components/case-sections";
import { openTicket } from "@/features/composites/composites-actions";
import { ActionDialog } from "@/features/sales/components/action-dialog";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/block-overview-query";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function CasesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const t = useExtracted("cases");

  return (
    <>
      <PageHeader
        title={t("Cases")}
        description={t(
          "Nonconformities, complaints, incidents and the other cases of the organization, from report to a verified close.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="tasks.write">
              <ActionDialog
                action={openTicket}
                title={t("Open a ticket")}
                description={t(
                  "Creates the ticket as a task and starts its response clocks.",
                )}
                trigger={t("Open ticket")}
                submitLabel={t("Open ticket")}
                successMessage={t("Ticket opened")}
                variant="outline"
                fields={[
                  {
                    name: "title",
                    label: t("Title"),
                    kind: "text",
                    required: true,
                  },
                  { name: "body", label: t("Details"), kind: "textarea" },
                ]}
              />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<CaseBoardSectionSkeleton />}>
        {searchParams.then((raw) => {
          const views = ["board", "table"] as const;
          const view = activeView(raw, views);

          return (
            <>
              <RecordViewSwitch base="/cases" active={view} views={views} />
              {view === "table" ? (
                <PermissionGate permission="cases.read">
                  <Suspense fallback={<KpiBandSkeleton />}>
                    <CaseKpis />
                  </Suspense>
                  <Suspense fallback={<CaseListSkeleton />}>
                    <CaseOverview query={parseBlockList(raw)} />
                  </Suspense>
                </PermissionGate>
              ) : (
                <>
                  <Suspense fallback={<CaseBoardSectionSkeleton />}>
                    <PermissionGate permission="cases.read">
                      <CaseBoardSection />
                    </PermissionGate>
                  </Suspense>
                  <Suspense fallback={<CaseDetailSectionSkeleton />}>
                    <PermissionGate permission="cases.read">
                      <CaseDetailSection query={raw} />
                    </PermissionGate>
                  </Suspense>
                </>
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
