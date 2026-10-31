import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  AwardUsage,
  AwardUsageSkeleton,
} from "@/features/funding/components/award-usage";

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
    </>
  );
}
