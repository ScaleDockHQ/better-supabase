import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ScoreModelOverview,
  CreateScoreModelDialog,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function ScoringPage({
  searchParams,
}: PageProps<"/[locale]/crm/scoring">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Scoring")}
        description={t(
          "Score models that rank leads and accounts by the rules you set.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="scores.manage">
              <CreateScoreModelDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <ScoreModelOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
