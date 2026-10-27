import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { PageHeader } from "@/components/page-header";
import {
  RuleList,
  RuleListSkeleton,
} from "@/features/rules/components/rule-list";

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
