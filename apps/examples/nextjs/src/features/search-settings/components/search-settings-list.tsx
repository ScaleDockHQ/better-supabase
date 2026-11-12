import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getSearchDocuments } from "../search-settings-queries";
import { SearchDocumentRecordList } from "./search-settings-record-list";

/** Render inside `<Suspense>`; the fallback is `SearchDocumentListSkeleton`. */
export async function SearchDocumentList() {
  const page = await getSearchDocuments();

  if (!page) {
    forbidden();
  }

  return <SearchDocumentRecordList initial={page} />;
}

export function SearchDocumentListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
