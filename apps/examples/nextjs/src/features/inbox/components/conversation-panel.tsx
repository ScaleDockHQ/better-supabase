"use client";

import { useConversation } from "better-supabase/blocks/inbox/react";
import { useAction } from "better-supabase/react";
import {
  CheckCheckIcon,
  CheckIcon,
  RotateCcwIcon,
  UserCheckIcon,
  UserMinusIcon,
  UserRoundIcon,
} from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/lib/hooks";
import { useErrorMessage } from "@/lib/use-error-message";
import { cn } from "@/lib/utils";

import type { MessageRow } from "../inbox-types";

import { assign, loadThread, setStatus, takeOver } from "../inbox-actions";
import { unwrap } from "../inbox-load";
import { Composer } from "./composer";

export function ConversationPanel({
  conversationId,
}: {
  conversationId: string;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const userId = useAuth().user?.id ?? null;
  const thread = useConversation({
    conversationId,
    load: async () => [unwrap(await loadThread({ conversationId }))],
  });
  const loaded = thread.items?.[0];
  const conversation = loaded?.conversation ?? null;
  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };
  const assignAction = useAction(assign, { onError });
  const mode = useAction(takeOver, { onError });
  const status = useAction(setStatus, { onError });

  if (loaded === undefined) {
    return (
      <div className="space-y-2 rounded-xl border p-4" aria-busy="true">
        {Array.from({ length: 4 }, (_, index) => (
          <Skeleton key={index} className="h-10 w-full" />
        ))}
      </div>
    );
  }
  if (conversation === null) {
    return (
      <p className="text-muted-foreground rounded-xl border p-4 text-sm">
        {t("This conversation is gone.")}
      </p>
    );
  }
  const resolved = conversation.status === "resolved";
  const mine = userId !== null && conversation.assigneeId === userId;
  const contactReadAt =
    conversation.contactReadAt === null
      ? null
      : Date.parse(conversation.contactReadAt);
  const seen = (message: MessageRow): boolean =>
    contactReadAt !== null && Date.parse(message.createdAt) <= contactReadAt;
  const busy = assignAction.pending || mode.pending || status.pending;

  return (
    <section
      aria-label={conversation.subject ?? t("Conversation")}
      className="flex min-h-0 flex-col rounded-xl border"
    >
      <header className="flex flex-wrap items-center gap-2 border-b px-4 py-3">
        <div className="min-w-0 flex-1">
          <h2 className="truncate font-medium">
            {conversation.subject ?? t("No subject")}
          </h2>
          <p className="text-muted-foreground truncate text-xs">
            {conversation.contactName || t("Visitor")}
            {conversation.inboxName ? ` · ${conversation.inboxName}` : ""}
          </p>
        </div>
        <Badge variant={resolved ? "secondary" : "default"}>
          {resolved ? t("Resolved") : t("Open")}
        </Badge>
        <Badge variant="outline">
          {conversation.botMode === "bot"
            ? t("Bot answers")
            : t("Staff answer")}
        </Badge>
        <Button
          size="sm"
          variant="outline"
          disabled={busy}
          onClick={() => {
            void assignAction.run({ conversationId, toMe: !mine });
          }}
        >
          {mine ? <UserMinusIcon /> : <UserCheckIcon />}
          {mine ? t("Unassign") : t("Assign to me")}
        </Button>
        {conversation.botMode === "bot" ? (
          <Button
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => {
              void mode.run({ conversationId });
            }}
          >
            <UserRoundIcon />
            {t("Take over from the bot")}
          </Button>
        ) : null}
        <Button
          size="sm"
          variant={resolved ? "outline" : "default"}
          disabled={busy}
          onClick={() => {
            void status.run({ conversationId, resolved: !resolved });
          }}
        >
          {resolved ? <RotateCcwIcon /> : <CheckIcon />}
          {resolved ? t("Reopen") : t("Resolve")}
        </Button>
      </header>
      <ol className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
        {loaded.messages.map((message) => {
          const outbound = message.authorType !== "contact";
          return (
            <li
              key={message.id}
              className={cn(
                "flex flex-col gap-1",
                outbound ? "items-end" : "items-start",
              )}
            >
              <div
                className={cn(
                  "max-w-4/5 rounded-lg px-3 py-2 text-sm whitespace-pre-wrap",
                  message.kind === "note"
                    ? "border-chart-4/60 bg-chart-4/10 border border-dashed"
                    : outbound
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted",
                )}
              >
                {message.deleted ? (
                  <span className="italic opacity-70">
                    {t("Message deleted")}
                  </span>
                ) : (
                  message.body
                )}
              </div>
              <span className="text-muted-foreground flex items-center gap-1 text-xs">
                {message.kind === "note" ? `${t("Note")} · ` : ""}
                {format.dateTime(new Date(message.createdAt), {
                  timeStyle: "short",
                })}
                {outbound && message.kind === "message" && seen(message) ? (
                  <span className="flex items-center gap-0.5">
                    <CheckCheckIcon className="size-3" aria-hidden />
                    {t("Seen")}
                  </span>
                ) : null}
              </span>
            </li>
          );
        })}
      </ol>
      {thread.typing.length > 0 ? (
        <output className="text-muted-foreground block px-4 pb-2 text-xs">
          {t("Someone is typing…")}
        </output>
      ) : null}
      <Composer
        conversationId={conversationId}
        onTyping={thread.setTyping}
        onSent={thread.refresh}
      />
    </section>
  );
}
