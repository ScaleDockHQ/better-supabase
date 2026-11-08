import { tenantOf } from "better-supabase/next";

import { Skeleton } from "@/components/ui/skeleton";
import { getSession } from "@/features/user/user-queries";

import { WorkflowRuns } from "./workflow-runs";

/** Render inside `<Suspense>`: reads the session for the active organization. */
export async function TenantWorkflowRuns() {
  const tenant = tenantOf(await getSession()) ?? null;

  return <WorkflowRuns tenant={tenant} />;
}

export function TenantWorkflowRunsSkeleton() {
  return (
    <div className="flex flex-col gap-2" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <Skeleton key={index} className="h-11 w-full" />
      ))}
    </div>
  );
}
