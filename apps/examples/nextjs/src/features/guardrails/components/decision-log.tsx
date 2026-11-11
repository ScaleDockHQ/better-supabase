import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getDecisionPage } from "../guardrails-queries";
import { DecisionTable } from "./decision-table";

/** Render inside `<Suspense>`: the decision log for the URL's state. */
export async function DecisionLog({ query }: { query: Promise<OpsListQuery> }) {
  const page = await query.then(getDecisionPage);

  return <DecisionTable items={page.items} nextCursor={page.nextCursor} />;
}

export function DecisionLogSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
