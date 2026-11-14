import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RuleList,
  RuleListSkeleton,
} from "@/features/rules/components/rule-list";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function RulesPage() {
  const t = useExtracted("rules");

  return (
    <>
      <PageHeader
        title={t("Rules")}
        description={t(
          "Conditions on customer fields, tested in the database when a customer is saved.",
        )}
      />
      <Suspense fallback={<RuleListSkeleton />}>
        <RuleList />
      </Suspense>
    </>
  );
}
