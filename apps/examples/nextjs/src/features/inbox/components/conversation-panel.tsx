"use client";

import { useAction } from "better-supabase/react";
import {
  BotIcon,
  CheckCheckIcon,
  CheckIcon,
  MoonIcon,
  RotateCcwIcon,
  StickyNoteIcon,
  UserCheckIcon,
  UserMinusIcon,
  UserRoundIcon,
} from "lucide-react";
import { useExtracted, useFormatter, useNow } from "next-intl";
import { useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Bubble, BubbleContent, BubbleGroup } from "@/components/ui/bubble";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Marker, MarkerContent, MarkerIcon } from "@/components/ui/marker";
import {
  Message,
  MessageContent,
  MessageFooter,
  MessageHeader,
} from "@/components/ui/message";
import {
  MessageScroller,
  MessageScrollerButton,
  MessageScrollerContent,
  MessageScrollerItem,
  MessageScrollerProvider,
  MessageScrollerViewport,
} from "@/components/ui/message-scroller";
import { Skeleton } from "@/components/ui/skeleton";
import { useConversation } from "@/hooks/use-inbox";
import { useAuth } from "@/lib/hooks";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ConversationRow, MessageRow } from "../inbox-types";

import {
  assign,
  loadMessage,
  loadThread,
  setBotMode,
  setStatus,
  snooze,
} from "../inbox-actions";
import { unwrap } from "../inbox-load";
import { slaStateOf, whatsappWindowOpen } from "../inbox-types";
import { Composer } from "./composer";
import { ChannelBadge, SlaBadge, StatusBadge } from "./conversation-badges";
import { LaterItems } from "./later-items";
import { ScheduledReplies } from "./scheduled-replies";

const dayOf = (iso: string): string => iso.slice(0, 10);

export function ConversationPanel({
  conversationId,
}: {
  conversationId: string;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const userId = useAuth().user?.id ?? null;

  // A full load also brings the header; a ping fetches only its message.
  const [conversation, setConversation] = useState<ConversationRow | null>();
  const [scheduledVersion, setScheduledVersion] = useState(0);
  const nowDate = useNow({ updateInterval: 60_000 });
  const now = nowDate.getTime();

  const thread = useConversation({
    conversationId,
    load: async () => {
      const loaded = unwrap(await loadThread({ conversationId }));
      setConversation(loaded.conversation);

      return loaded.messages;
    },
    get: async (messageId) => unwrap(await loadMessage({ messageId })),
  });

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const onSuccess = () => {
    void thread.refresh();
  };

  const assignAction = useAction(assign, { onError, onSuccess });
  const mode = useAction(setBotMode, { onError, onSuccess });
  const status = useAction(setStatus, { onError, onSuccess });
  const snoozeAction = useAction(snooze, { onError, onSuccess });

  if (thread.items === undefined || conversation === undefined) {
    return (
      <div className="flex flex-col gap-2 p-4" aria-busy="true">
        {Array.from({ length: 4 }, (_, index) => (
          <Skeleton key={index} className="h-10 w-full" />
        ))}
      </div>
    );
  }

  if (conversation === null) {
    return (
      <p className="p-4 text-sm text-muted-foreground">
        {t("This conversation is gone.")}
      </p>
    );
  }

  const resolved = conversation.status === "resolved";

  const snoozedUntil =
    conversation.status === "snoozed" && conversation.snoozedUntil !== null
      ? new Date(conversation.snoozedUntil)
      : null;

  const mine = userId !== null && conversation.assigneeId === userId;

  const contactReadAt =
    conversation.contactReadAt === null
      ? null
      : Date.parse(conversation.contactReadAt);

  const seen = (message: MessageRow): boolean =>
    contactReadAt !== null && Date.parse(message.createdAt) <= contactReadAt;

  const busy =
    assignAction.pending ||
    mode.pending ||
    status.pending ||
    snoozeAction.pending;

  const windowOpen = whatsappWindowOpen(conversation, now);

  return (
    <section
      aria-label={conversation.subject ?? t("Conversation")}
      className="flex h-full min-h-0 flex-col"
    >
      <header className="flex flex-col gap-3 border-b px-4 py-3">
        <div className="flex flex-wrap items-center gap-2">
          <div className="min-w-0 flex-1">
            <h2 className="truncate font-medium">
              {conversation.subject ?? t("No subject")}
            </h2>
            <p className="truncate text-xs text-muted-foreground">
              {conversation.contactName || t("Visitor")}
              {conversation.inboxName ? ` · ${conversation.inboxName}` : ""}
            </p>
          </div>
          <ChannelBadge channel={conversation.channel} />
          <StatusBadge row={conversation} />
          <SlaBadge state={slaStateOf(conversation, now)} />
          {snoozedUntil === null ? null : (
            <Badge variant="secondary">
              {t("Until {time}", {
                time: format.dateTime(snoozedUntil, {
                  dateStyle: "medium",
                  timeStyle: "short",
                }),
              })}
            </Badge>
          )}
          <Badge variant="outline">
            {conversation.botMode === "bot"
              ? t("Bot answers")
              : conversation.botMode === "paused"
                ? t("Bot paused")
                : t("Staff answer")}
          </Badge>
        </div>
        <div className="flex flex-wrap items-center gap-2">
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
                void mode.run({ conversationId, mode: "human" });
              }}
            >
              <UserRoundIcon />
              {t("Take over from the bot")}
            </Button>
          ) : (
            <Button
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() => {
                void mode.run({ conversationId, mode: "bot" });
              }}
            >
              <BotIcon />
              {t("Hand back to the bot")}
            </Button>
          )}
          {resolved ? null : (
            <DropdownMenu>
              <DropdownMenuTrigger
                disabled={busy}
                render={<Button size="sm" variant="outline" />}
              >
                <MoonIcon />
                {t("Snooze")}
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <LaterItems
                  onSelect={(until) => {
                    void snoozeAction.run({ conversationId, until });
                  }}
                />
              </DropdownMenuContent>
            </DropdownMenu>
          )}
          <Button
            size="sm"
            variant={resolved ? "outline" : "default"}
            className="ml-auto"
            disabled={busy}
            onClick={() => {
              void status.run({ conversationId, resolved: !resolved });
            }}
          >
            {resolved ? <RotateCcwIcon /> : <CheckIcon />}
            {resolved ? t("Reopen") : t("Resolve")}
          </Button>
        </div>
      </header>
      <MessageScrollerProvider autoScroll>
        <MessageScroller>
          <MessageScrollerViewport>
            <MessageScrollerContent className="gap-4 p-4">
              {thread.items.map((message, index) => {
                const previous = thread.items?.[index - 1];

                const newDay =
                  previous === undefined ||
                  dayOf(previous.createdAt) !== dayOf(message.createdAt);

                return (
                  <MessageScrollerItem
                    key={message.id}
                    messageId={message.id}
                    scrollAnchor={message.authorType === "agent"}
                  >
                    {newDay ? (
                      <Marker variant="separator" className="mb-4">
                        <MarkerContent>
                          {format.dateTime(new Date(message.createdAt), {
                            dateStyle: "medium",
                          })}
                        </MarkerContent>
                      </Marker>
                    ) : null}
                    <ThreadMessage
                      message={message}
                      contactName={conversation.contactName || t("Visitor")}
                      seen={seen(message)}
                    />
                  </MessageScrollerItem>
                );
              })}
            </MessageScrollerContent>
          </MessageScrollerViewport>
          <MessageScrollerButton />
        </MessageScroller>
      </MessageScrollerProvider>
      {thread.typing.length > 0 ? (
        <output className="block px-4 pb-2 text-xs text-muted-foreground">
          {t("Someone is typing…")}
        </output>
      ) : null}
      <ScheduledReplies
        key={scheduledVersion}
        conversationId={conversationId}
      />
      <Composer
        conversationId={conversationId}
        channel={conversation.channel}
        windowOpen={windowOpen}
        onTyping={thread.setTyping}
        onSent={thread.refresh}
        onScheduled={() => {
          setScheduledVersion((current) => current + 1);
        }}
      />
    </section>
  );
}

function ThreadMessage({
  message,
  contactName,
  seen,
}: {
  message: MessageRow;
  contactName: string;
  seen: boolean;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();

  if (message.authorType === "system") {
    return (
      <Marker>
        <MarkerIcon>
          <StickyNoteIcon />
        </MarkerIcon>
        <MarkerContent>{message.body}</MarkerContent>
      </Marker>
    );
  }

  const inbound = message.authorType === "contact";
  const note = message.kind === "note";
  const bot = message.authorType === "bot";

  const author = inbound ? contactName : bot ? t("Bot") : t("Team");

  return (
    <Message align={inbound ? "start" : "end"}>
      <MessageContent>
        <MessageHeader>
          {note ? `${t("Internal note")} · ${author}` : author}
        </MessageHeader>
        <BubbleGroup>
          <Bubble
            align={inbound ? "start" : "end"}
            variant={
              note
                ? "tinted"
                : inbound
                  ? "muted"
                  : bot
                    ? "secondary"
                    : "default"
            }
          >
            <BubbleContent className="whitespace-pre-wrap">
              {message.deleted ? (
                <span className="italic opacity-70">
                  {t("Message deleted")}
                </span>
              ) : (
                message.body
              )}
            </BubbleContent>
          </Bubble>
        </BubbleGroup>
        <MessageFooter>
          <span className="flex items-center gap-1 text-xs text-muted-foreground">
            {format.dateTime(new Date(message.createdAt), {
              timeStyle: "short",
            })}
            {message.delivery === "failed" ? (
              <Badge variant="destructive-light">{t("Not delivered")}</Badge>
            ) : null}
            {!inbound && message.kind === "message" && seen ? (
              <span className="flex items-center gap-0.5">
                <CheckCheckIcon className="size-3" aria-hidden />
                {t("Seen")}
              </span>
            ) : message.delivery === "delivered" ||
              message.delivery === "read" ? (
              <span className="flex items-center gap-0.5">
                <CheckIcon className="size-3" aria-hidden />
                {t("Delivered")}
              </span>
            ) : null}
          </span>
        </MessageFooter>
      </MessageContent>
    </Message>
  );
}
