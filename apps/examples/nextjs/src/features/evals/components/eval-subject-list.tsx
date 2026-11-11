import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getEvalSubjectPage } from "../evals-queries";
import { EvalSubjectTable } from "./eval-subject-table";

/** Render inside `<Suspense>`: the prompts with an eval workspace. */
export async function EvalSubjectList({
  query,
}: {
  query: Promise<OpsListQuery>;
}) {
  const page = await query.then(getEvalSubjectPage);

  return <EvalSubjectTable items={page.items} nextCursor={page.nextCursor} />;
}

export function EvalSubjectListSkeleton() {
  return <RecordListSkeleton rows={3} />;
}
