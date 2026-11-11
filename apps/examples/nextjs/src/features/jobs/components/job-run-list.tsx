import { forbidden } from "next/navigation";

import { RecordListSkeleton } from "@/components/record-list/record-list-skeleton";

import { getJobRuns } from "../jobs-runs-queries";
import { JobRecordList } from "./job-record-list";

/** Render inside `<Suspense>`; the fallback is `JobRunListSkeleton`. */
export async function JobRunList() {
  const page = await getJobRuns();

  if (!page) {
    forbidden();
  }

  return <JobRecordList initial={page} />;
}

export function JobRunListSkeleton() {
  return <RecordListSkeleton rows={5} />;
}
