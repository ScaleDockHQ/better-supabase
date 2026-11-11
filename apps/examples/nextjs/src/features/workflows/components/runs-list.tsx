import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getRunsPage } from "../workflows-list-data";
import { RunsRecordList } from "./runs-record-list";

/** Render inside `<Suspense>`; the fallback is `RunsListSkeleton`. */
export async function RunsList() {
  const { page, definitions, tenant } = await getRunsPage();

  return (
    <RunsRecordList initial={page} definitions={definitions} tenant={tenant} />
  );
}

export function RunsListSkeleton() {
  return <RecordListSkeleton rows={6} />;
}
