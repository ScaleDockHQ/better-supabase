import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  activeTab,
  RecordDetailTabs,
} from "@/components/record-detail/record-detail-tabs";
import {
  LimsListSkeleton,
  MethodOverview,
  NewMethodDialog,
  RegisterSampleDialog,
  SampleOverview,
} from "@/features/lims/components/lims-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header, the tabs and the list frame at once; the
// rows render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function LimsPage({
  searchParams,
}: PageProps<"/[locale]/lims">) {
  const t = useExtracted("lims");

  return (
    <>
      <PageHeader
        title={t("Laboratory")}
        description={t(
          "Samples received for testing, the methods and limits they are tested against, and the nonconformities that out of specification results open.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="lims.write">
              <RegisterSampleDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<LimsListSkeleton />}>
        {searchParams.then((raw) => {
          const view = activeTab(raw, ["samples", "methods"]);

          return (
            <>
              <RecordDetailTabs
                base="/lims"
                active={view}
                tabs={[
                  { value: "samples", label: t("Samples") },
                  { value: "methods", label: t("Methods") },
                ]}
              />
              {view === "methods" ? (
                <>
                  <Suspense fallback={null}>
                    <PermissionGate permission="lims.manage">
                      <div className="flex gap-2">
                        <NewMethodDialog />
                      </div>
                    </PermissionGate>
                  </Suspense>
                  <MethodOverview query={parseBlockList(raw)} />
                </>
              ) : (
                <SampleOverview query={parseBlockList(raw)} />
              )}
            </>
          );
        })}
      </Suspense>
    </>
  );
}
