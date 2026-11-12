import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getPromptPage } from "../prompts-queries";
import { PromptTable } from "./prompt-table";

/** Render inside `<Suspense>`: the filtered prompt registry for the URL's state. */
export async function PromptList({ query }: { query: Promise<OpsListQuery> }) {
  const page = await query.then(getPromptPage);

  return <PromptTable items={page.items} nextCursor={page.nextCursor} />;
}

export function PromptListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
