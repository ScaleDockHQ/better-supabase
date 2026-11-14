import { Skeleton } from "@/components/ui/skeleton";

import { getOpenInvitations } from "../organization-invitations";
import { InvitationsGrid } from "./invitations-grid";

/**
 * The open invitations the `organizations` block lists through
 * `invitationsPage`.
 */
export async function InvitationsOverview() {
  const rows = await getOpenInvitations().catch(() => null);

  return <InvitationsGrid rows={rows} />;
}

export function InvitationsOverviewSkeleton() {
  return (
    <div aria-busy="true" className="flex flex-col gap-2">
      <Skeleton className="h-8" />
      <Skeleton className="h-8" />
      <Skeleton className="h-8" />
    </div>
  );
}
