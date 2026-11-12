import { forbidden, notFound } from "next/navigation";

import { Skeleton } from "@/components/ui/skeleton";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { getConversationContext } from "../inbox-queries";
import { ConversationContextPanel } from "./conversation-context";
import { ConversationWorkspace } from "./conversation-workspace";

/** Render inside `<Suspense>`. */
export async function ConversationDetail({ id }: { id: string }) {
  const permissions = await getPermissions();

  if (!can(permissions, "inbox.read")) {
    forbidden();
  }

  const context = await getConversationContext(id);

  if (context === null) {
    notFound();
  }

  return (
    <ConversationWorkspace
      conversationId={id}
      context={<ConversationContextPanel context={context} />}
    />
  );
}

export function ConversationDetailSkeleton() {
  return (
    <div className="flex h-full flex-col gap-3 p-4" aria-busy="true">
      <Skeleton className="h-14 w-full" />
      <Skeleton className="h-full min-h-64 w-full" />
    </div>
  );
}
