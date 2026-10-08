import { tenantOf } from "better-supabase/next";

import { getSession } from "@/features/user/user-queries";

import { WorkflowRuns } from "./workflow-runs";

/** Render inside `<Suspense>`: reads the session for the active organization. */
export async function TenantWorkflowRuns() {
  const tenant = tenantOf(await getSession()) ?? null;
  return <WorkflowRuns tenant={tenant} />;
}
