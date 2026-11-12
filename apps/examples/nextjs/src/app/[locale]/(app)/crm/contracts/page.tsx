import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  ContractOverview,
  CreateContractDialog,
  SalesListSkeleton,
} from "@/features/sales/components/crm-overviews";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function ContractsPage({
  searchParams,
}: PageProps<"/[locale]/crm/contracts">) {
  const t = useExtracted("sales");

  return (
    <>
      <PageHeader
        title={t("Contracts")}
        description={t(
          "Contracts from draft to signature, with renewal and notice dates.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="contracts.write">
              <CreateContractDialog />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <ContractOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
