"use client";

import type { Message as ChatMessage } from "better-supabase/blocks/messaging";

import { mentionSegments } from "better-supabase/blocks/messaging";
import { LinkIcon, MessageSquareIcon, PaperclipIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { Fragment } from "react";

import { Badge } from "@/components/reui/badge";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Bubble, BubbleContent, BubbleGroup } from "@/components/ui/bubble";
import { Button } from "@/components/ui/button";
import {
  Message,
  MessageAvatar,
  MessageContent,
  MessageFooter,
  MessageHeader,
} from "@/components/ui/message";

const initials = (name: string): string =>
  name
    .split(/\s+/u)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("");

/**
 * A body with its mentions: users in bold, records as chips. Each record
 * mention is also a backlink, listed by `messaging.recordMentions(subject)`.
 */
function MessageBody({ body }: { body: string }) {
  const seen = new Map<string, number>();

  // The same text or mention can repeat in a body, so its key counts repeats.
  const keyOf = (base: string): string => {
    const count = (seen.get(base) ?? 0) + 1;
    seen.set(base, count);

    return `${base}#${String(count)}`;
  };

  return mentionSegments(body).map((segment) => {
    switch (segment.kind) {
      case "text": {
        return (
          <Fragment key={keyOf(`text:${segment.text}`)}>
            {segment.text}
          </Fragment>
        );
      }

      case "user": {
        return (
          <span key={keyOf(`user:${segment.userId}`)} className="font-medium">
            @{segment.name}
          </span>
        );
      }

      case "record": {
        return (
          <Badge
            key={keyOf(`record:${segment.subject.type}/${segment.subject.id}`)}
            variant="outline"
            title={`${segment.subject.type} ${segment.subject.id}`}
          >
            <LinkIcon aria-hidden />
            {segment.name}
          </Badge>
        );
      }

      case "scope": {
        return (
          <span key={keyOf(`scope:${segment.scope}`)} className="font-medium">
            @{segment.scope}
          </span>
        );
      }

      default: {
        const never: never = segment;

        return never;
      }
    }
  });
}

/** One message: author, time, body, files and, at the top level, its replies. */
export function MessageItem({
  message,
  onOpenThread,
}: {
  message: ChatMessage;
  /** Shown on top-level messages; omit it inside a thread. */
  onOpenThread?: (root: ChatMessage) => void;
}) {
  const t = useExtracted("chat");
  const format = useFormatter();
  const name = message.author?.name ?? t("Someone");
  const at = message.sentAt ?? message.createdAt;

  return (
    <Message>
      <MessageAvatar>
        <Avatar size="sm">
          <AvatarFallback>{initials(name)}</AvatarFallback>
        </Avatar>
      </MessageAvatar>
      <MessageContent>
        <MessageHeader className="gap-2 px-0">
          <span className="text-sm font-medium text-foreground">{name}</span>
          <time dateTime={at.toString()} className="tabular-nums">
            {format.dateTime(at.epochMilliseconds, { timeStyle: "short" })}
          </time>
          {message.editedAt ? <span>{t("edited")}</span> : null}
        </MessageHeader>
        <BubbleGroup>
          <Bubble variant="muted">
            <BubbleContent className="break-words whitespace-pre-wrap">
              {message.deletedAt ? (
                <span className="italic opacity-70">
                  {t("This message was deleted.")}
                </span>
              ) : (
                <MessageBody body={message.body} />
              )}
            </BubbleContent>
          </Bubble>
        </BubbleGroup>
        {message.attachments.length > 0 ? (
          <ul className="flex flex-wrap gap-2">
            {message.attachments.map((file) => (
              <li key={file.id}>
                <Badge variant="outline">
                  <PaperclipIcon aria-hidden />
                  {file.name}
                </Badge>
              </li>
            ))}
          </ul>
        ) : null}
        {onOpenThread && message.threadId === undefined ? (
          <MessageFooter className="px-0">
            <Button
              type="button"
              size="xs"
              variant="ghost"
              onClick={() => {
                onOpenThread(message);
              }}
            >
              <MessageSquareIcon aria-hidden />
              {message.replyCount > 0
                ? t("{count, plural, one {# reply} other {# replies}}", {
                    count: message.replyCount,
                  })
                : t("Reply in thread")}
            </Button>
          </MessageFooter>
        ) : null}
      </MessageContent>
    </Message>
  );
}
