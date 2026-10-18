import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { Skeleton } from "@/components/ui/skeleton";
import { CsvImportWizard } from "@/features/imports/components/csv-import-wizard";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const instant = true;

export default function ImportsPage() {
  const t = useExtracted("imports");

  return (
    <>
      <PageHeader
        title={t("Imports")}
        description={t("Bring customers in from a spreadsheet.")}
      />
      <Suspense fallback={<Skeleton className="h-96 w-full" />}>
        <PermissionGate permission="imports.manage">
          <CsvImportWizard />
        </PermissionGate>
      </Suspense>
    </>
  );
}
