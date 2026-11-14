import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import { loadUsageRange } from "@/features/ai-usage/ai-usage-search-params";
import {
  UsageOverview,
  UsageOverviewSkeleton,
} from "@/features/ai-usage/components/usage-overview";

export const ensureStatic = "prefetch";
export const instant = true;

export default function AiUsagePage({
  searchParams,
}: PageProps<"/[locale]/assistant/usage">) {
  const t = useExtracted("aiUsage");

  return (
    <>
      <PageHeader
        title={t("AI usage")}
        description={t(
          "Tokens and spend of your runs, by day and by model, with the gateway's own cost.",
        )}
      />
      <Suspense fallback={<UsageOverviewSkeleton />}>
        {loadUsageRange(searchParams).then(({ range }) => (
          <UsageOverview range={range} />
        ))}
      </Suspense>
    </>
  );
}
