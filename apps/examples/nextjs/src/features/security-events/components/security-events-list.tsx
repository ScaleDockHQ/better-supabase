import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getSecurityStreams } from "../security-events-queries";
import { SecurityStreamRecordList } from "./security-events-record-list";

/** Render inside `<Suspense>`; the fallback is `SecurityStreamListSkeleton`. */
export async function SecurityStreamList() {
  const page = await getSecurityStreams();

  if (!page) {
    forbidden();
  }

  return <SecurityStreamRecordList initial={page} />;
}

export function SecurityStreamListSkeleton() {
  return <RecordListSkeleton rows={4} />;
}
