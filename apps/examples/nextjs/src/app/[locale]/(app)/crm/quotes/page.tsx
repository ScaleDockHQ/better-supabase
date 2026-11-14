import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { CreateQuoteDialog } from "@/features/crm/components/create-quote-dialog";
import { SalesListSkeleton } from "@/features/sales/components/crm-overviews";
import { QuoteOverview } from "@/features/sales/components/quote-overview";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { parseBlockList } from "@/lib/array-list";

// A navigation here shows the header and the list frame at once; the rows
// render on navigation (tests/loading-sequences.spec.ts).
export const instant = true;

export default function QuotesPage({
  searchParams,
}: PageProps<"/[locale]/crm/quotes">) {
  const t = useExtracted("crm");

  return (
    <>
      <PageHeader
        title={t("Quotes")}
        description={t(
          "Line items, discounts and totals, sent for acceptance.",
        )}
        actions={
          <Suspense fallback={null}>
            <PermissionGate permission="quotes.write">
              <CreateQuoteDialog openFromUrl />
            </PermissionGate>
          </Suspense>
        }
      />
      <Suspense fallback={<SalesListSkeleton />}>
        {searchParams.then((raw) => (
          <QuoteOverview query={parseBlockList(raw)} />
        ))}
      </Suspense>
    </>
  );
}
