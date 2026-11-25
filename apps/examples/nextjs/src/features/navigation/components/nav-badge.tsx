import { SidebarMenuBadge } from "@/components/ui/sidebar";
import { getShell } from "@/features/shell/shell-queries";

/** Pending approval requests the caller can see, from the shell's one entry. */
async function pendingApprovals(): Promise<number> {
  const shell = await getShell();

  if (!shell.tenant) {
    return 0;
  }

  return shell.data?.approvals_pending ?? 0;
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
