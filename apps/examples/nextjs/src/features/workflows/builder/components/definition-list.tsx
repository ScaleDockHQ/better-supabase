import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getDefinitionsPage } from "../../workflows-list-data";
import { DefinitionRecordList } from "./definition-record-list";

/** Render inside `<Suspense>`; the fallback is `DefinitionListSkeleton`. */
export async function DefinitionList() {
  const page = await getDefinitionsPage();

  return <DefinitionRecordList initial={page} />;
}

export function DefinitionListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
