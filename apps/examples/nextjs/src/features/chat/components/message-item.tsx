"use client";

import type { Message } from "better-supabase/blocks/messaging";

import { MessageSquareIcon, PaperclipIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/reui/badge";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";

const initials = (name: string): string =>
  name
    .split(/\s+/u)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join("");

/** One message: author, time, body, files and, at the top level, its replies. */
export function MessageItem({
  message,
  onOpenThread,
}: {
  message: Message;
  /** Shown on top-level messages; omit it inside a thread. */
  onOpenThread?: (root: Message) => void;
}) {
  const t = useExtracted("chat");
  const format = useFormatter();
  const name = message.author?.name ?? t("Someone");
  const at = message.sentAt ?? message.createdAt;

  return (
    <li className="flex gap-3">
      <Avatar size="sm">
        <AvatarFallback>{initials(name)}</AvatarFallback>
      </Avatar>
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <p className="flex flex-wrap items-baseline gap-2 text-sm">
          <span className="font-medium">{name}</span>
          <time
            dateTime={at.toString()}
            className="text-xs text-muted-foreground tabular-nums"
          >
            {format.dateTime(at.epochMilliseconds, { timeStyle: "short" })}
          </time>
          {message.editedAt ? (
            <span className="text-xs text-muted-foreground">{t("edited")}</span>
          ) : null}
        </p>
        {message.deletedAt ? (
          <p className="text-sm text-muted-foreground italic">
            {t("This message was deleted.")}
          </p>
        ) : (
          <p className="text-sm break-words whitespace-pre-wrap">
            {message.body}
          </p>
        )}
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
          <div>
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
          </div>
        ) : null}
      </div>
    </li>
  );
}
