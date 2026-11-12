import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import {
  NewTillDialog,
  OpenSessionDialog,
  SessionOverview,
  TillOverview,
  TillsListSkeleton,
} from "@/features/tills/components/tills-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header, the tabs and the list frame at once; the
// rows render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function TillsPage({
  searchParams,
}: PageProps<"/[locale]/tills">) {
  const t = useExtracted("tills");

  return (
    <>
      <PageHeader
        title={t("Tills")}
        description={t(
          "Each shift starts with a float and ends with a count that books any difference, then the cash goes to the bank.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="tills.write">
              <OpenSessionDialog />
            </PermissionGate>
            <PermissionGate permission="tills.manage">
              <NewTillDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<TillsListSkeleton />}>
        {searchParams.then((raw) => {
          const view = activeTab(raw, ["sessions", "tills"]);

          return (
            <>
              <RecordDetailTabs
                base="/tills"
                active={view}
                tabs={[
                  { value: "sessions", label: t("Sessions") },
                  { value: "tills", label: t("Tills") },
                ]}
              />
              {view === "tills" ? (
                <TillOverview query={parseBlockList(raw)} />
              ) : (
                <SessionOverview query={parseBlockList(raw)} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
