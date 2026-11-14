import { MessagesSquareIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { ConversationPanel } from "@/features/inbox/components/conversation-panel";
import { Link } from "@/i18n/navigation";

import { loadDealConversations } from "../pipeline/deal-conversations";

export function DealConversationSkeleton() {
  return <Skeleton className="h-128 rounded-xl" aria-busy="true" />;
}

/**
 * The buyer's unibox thread on the deal desk: the same panel as the inbox, so a
 * reply, a note or an assignment here lands in the queue. Several threads show
 * as links above the open one.
 */
export async function DealConversation({
  dealId,
  selected,
}: {
  dealId: string;
  selected: string | undefined;
}) {
  const [t, conversations] = await Promise.all([
    getExtracted("sales"),
    loadDealConversations(dealId),
  ]);

  const open =
    conversations.find((conversation) => conversation.id === selected) ??
    conversations[0];

  if (!open) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MessagesSquareIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No conversation yet")}</EmptyTitle>
          <EmptyDescription>
            {t(
              "A thread shows here once a person linked to this deal writes to the inbox.",
            )}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {conversations.length > 1 ? (
        <nav aria-label={t("Conversations")} className="flex flex-wrap gap-2">
          {conversations.map((conversation) => (
            <Link
              key={conversation.id}
              href={`/crm/deals/${dealId}?tab=conversation&conversation=${conversation.id}`}
              aria-current={conversation.id === open.id ? "page" : undefined}
              className={buttonVariants({
                variant: conversation.id === open.id ? "secondary" : "ghost",
                size: "sm",
              })}
            >
              {conversation.subject ?? conversation.contactName}
            </Link>
          ))}
        </nav>
      ) : null}
      <div className="h-128 overflow-hidden rounded-xl border">
        <ConversationPanel key={open.id} conversationId={open.id} />
      </div>
    </div>
  );
}
