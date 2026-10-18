import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { CreateQuoteDialog } from "@/features/crm/components/create-quote-dialog";
import {
  QuoteList,
  QuoteListSkeleton,
} from "@/features/crm/components/quote-list";

export const instant = true;

export default function QuotesPage() {
  const t = useExtracted("crm");

  return (
    <>
      <PageHeader
        title={t("Quotes")}
        description={t(
          "Line items, discounts and totals, sent for acceptance.",
        )}
        actions={<CreateQuoteDialog />}
      />
      <Suspense fallback={<QuoteListSkeleton />}>
        <QuoteList />
      </Suspense>
    </>
  );
}
