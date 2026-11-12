import { notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";

import { getRunDetail } from "../workflows-queries";
import { WorkflowRunDetail } from "./workflow-run-detail";

/** Render inside `<Suspense>`: reads the `run` param. */
export async function RunDetail({ run }: { run: string }) {
  const detail = await getRunDetail(run);

  if (detail === null) {
    notFound();
  }

  return <WorkflowRunDetail detail={detail} />;
}

export function RunDetailSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-busy="true">
      <Skeleton className="h-48 w-full" />
      <Skeleton className="h-64 w-full" />
    </div>
  );
}
