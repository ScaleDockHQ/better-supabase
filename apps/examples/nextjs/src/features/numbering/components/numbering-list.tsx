import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getNumbering } from "../numbering-queries";
import { NumberingRecordList } from "./numbering-record-list";

/** Render inside `<Suspense>`; the fallback is `NumberingListSkeleton`. */
export async function NumberingList() {
  const page = await getNumbering();

  if (!page) {
    forbidden();
  }

  return <NumberingRecordList initial={page} />;
}

export function NumberingListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
