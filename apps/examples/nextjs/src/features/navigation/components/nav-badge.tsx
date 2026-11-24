import { tenantOf } from "better-supabase/next";
import { cacheLife, cacheTag } from "next/cache";

import { SidebarMenuBadge } from "@/components/ui/sidebar";
import { APPROVALS_TAG } from "@/features/approvals/approvals-cache";
import { bsb } from "@/lib/supabase/server";

/** Pending approval requests the caller can see; a short private cache. */
async function pendingApprovals(): Promise<number> {
  "use cache: private";
  cacheLife({ stale: 30, revalidate: 60, expire: 300 });
  cacheTag(APPROVALS_TAG);

  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return 0;
  }

  const counted = await db.approvals.count({
    filters: { status: ["pending"] },
  });

  return counted.ok ? counted.data.value : 0;
}

/**
 * The count badge of the approvals entry. Render it inside `<Suspense>` with no
 * fallback: the entry is stable chrome and the number is the only value.
 */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function ApprovalsNavBadge() {
  const count = await pendingApprovals();

  return count === 0 ? null : <SidebarMenuBadge>{count}</SidebarMenuBadge>;
}
