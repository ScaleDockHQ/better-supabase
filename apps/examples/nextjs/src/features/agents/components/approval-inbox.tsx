import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getApprovalInbox } from "../agents-queries";
import { ApprovalTable } from "./approval-table";

/** Render inside `<Suspense>`: the filtered inbox for the URL's state. */
export async function ApprovalInbox({
  query,
}: {
  query: Promise<OpsListQuery>;
}) {
  const { items, tools } = await query.then(getApprovalInbox);

  return <ApprovalTable items={items} tools={tools} />;
}

export function ApprovalInboxSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
