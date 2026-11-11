import { tenantOf } from "better-supabase/next";
import { forbidden } from "next/navigation";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { getConversations } from "../inbox-queries";
import { ConversationQueue, QueueSkeleton } from "./conversation-queue";

/** Render inside `<Suspense>`. */
export async function InboxQueue() {
  const [session, permissions] = await Promise.all([
    getSession(),
    getPermissions(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  if (!can(permissions, "inbox.read")) {
    forbidden();
  }

  const conversations = await getConversations();

  return (
    <ConversationQueue
      organizationId={organizationId}
      initial={conversations}
    />
  );
}

export function InboxQueueSkeleton() {
  return (
    <div className="p-3">
      <QueueSkeleton />
    </div>
  );
}
