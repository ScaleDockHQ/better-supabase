import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  CaseBoardSection,
  CaseBoardSkeleton,
  CaseDetailSection,
  CaseDetailSkeleton,
} from "@/features/cases/components/case-sections";
import { PermissionGate } from "@/features/user/components/permission-gate";

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
      />
      <Suspense fallback={<CaseBoardSkeleton />}>
        <PermissionGate permission="cases.read">
          <CaseBoardSection />
        </PermissionGate>
      </Suspense>
      <Suspense fallback={<CaseDetailSkeleton />}>
        <PermissionGate permission="cases.read">
          <CaseDetailSection searchParams={searchParams} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
