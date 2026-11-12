import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getFlags } from "../flags-queries";
import { FlagRecordList } from "./flags-record-list";

/** Render inside `<Suspense>`; the fallback is `FlagListSkeleton`. */
export async function FlagList() {
  const page = await getFlags();

  if (!page) {
    forbidden();
  }

  return <FlagRecordList initial={page} />;
}

export function FlagListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
