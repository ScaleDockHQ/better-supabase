import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { FinanceOverviewPage } from "@/components/finance-pages/finance-pages";
import { PageHeader } from "@/components/page-header";
import {
  AwardUsage,
  AwardUsageSkeleton,
} from "@/features/funding/components/award-usage";

// instant: this overview keeps its own header and sections (the page reads
// the signed-in user's permissions), so it doesn't export `instant`; the
// list and detail pages beside it do.

export default function FundingPage() {
  const t = useExtracted("funding");

  return (
    <>
      <PageHeader
        title={t("Funding")}
        description={t(
          "The units funders award your customers and how much of each award this period used.",
        )}
      />
      <Suspense fallback={<AwardUsageSkeleton />}>
        <AwardUsage />
      </Suspense>
      <FinanceOverviewPage entity="funding" embedded />
    </>
  );
}
