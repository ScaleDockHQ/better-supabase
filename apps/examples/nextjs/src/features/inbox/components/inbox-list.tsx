import { tenantOf } from "better-supabase/next";
import { forbidden } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getConversations } from "../inbox-queries";
import { InboxView } from "./inbox-view";

/** Render inside `<Suspense>`. */
export async function InboxList() {
  const session = await getSession();
  const organizationId = tenantOf(session);
  if (!organizationId) return null;
  if (!can(session, "inbox.read")) forbidden();
  const conversations = await getConversations();
  return <InboxView organizationId={organizationId} initial={conversations} />;
}

export function InboxListSkeleton() {
  return (
    <div className="grid gap-4 lg:grid-cols-3" aria-busy="true">
      <div className="space-y-2">
        {Array.from({ length: 5 }, (_, index) => (
          <Skeleton key={index} className="h-16 w-full" />
        ))}
      </div>
      <Skeleton className="h-96 w-full lg:col-span-2" />
    </div>
  );
}
