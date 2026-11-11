import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { loadOpsList } from "@/components/ops-list/ops-list-params";
import { PageHeader } from "@/components/page-header";
import {
  EvalSubjectList,
  EvalSubjectListSkeleton,
} from "@/features/evals/components/eval-subject-list";
import { PermissionGate } from "@/features/user/components/permission-gate";

export const ensureStatic = "prefetch";
export const instant = true;

export default function EvalsPage({
  searchParams,
}: PageProps<"/[locale]/assistant/evals">) {
  const t = useExtracted("evals");

  return (
    <>
      <PageHeader
        title={t("Evals")}
        description={t(
          "A dataset per prompt, run against a version and a model. Answers users rate down in the assistant feed the dataset.",
        )}
      />
      <Suspense fallback={<EvalSubjectListSkeleton />}>
        <PermissionGate permission="ai_chat.manage">
          <EvalSubjectList query={loadOpsList(searchParams)} />
        </PermissionGate>
      </Suspense>
    </>
  );
}
