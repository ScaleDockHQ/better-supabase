import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { AdminBackLink } from "@/features/admin-lists/admin-detail-page";
import {
  CreditTransactionDetail,
  CreditTransactionSkeleton,
} from "@/features/credits/components/credit-transaction-detail";

// A navigation here shows the back link at once; the transaction streams in.
export const instant = true;

export default function CreditTransactionPage({
  params,
}: PageProps<"/[locale]/settings/billing/credits/[id]">) {
  const t = useExtracted("credits");

  return (
    <>
      <AdminBackLink href="/settings/billing/credits">
        {t("All credit entries")}
      </AdminBackLink>
      <Suspense fallback={<CreditTransactionSkeleton />}>
        {params.then(({ id }) => (
          <CreditTransactionDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
