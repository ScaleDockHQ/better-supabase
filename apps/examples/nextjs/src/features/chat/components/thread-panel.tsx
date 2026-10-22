// #region recipe:thread-panel
"use client";

import type { Message } from "better-supabase/blocks/messaging";

import { useMessages } from "better-supabase/blocks/messaging/react";
import { MessageSquareIcon, RotateCwIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useRef } from "react";

import { Alert, AlertAction, AlertTitle } from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import { MessageComposer } from "./message-composer";
import { MessageItem } from "./message-item";

/** A thread: its root message, the replies, and a composer that replies into it. */
export function ThreadPanel({
  root,
  onClose,
}: {
  /** The top-level message the thread hangs off. */
  root: Message;
  onClose: () => void;
}) {
  const t = useExtracted("chat");
  const errorMessage = useErrorMessage();
  const input = useRef<HTMLTextAreaElement>(null);

  const thread = useMessages({
    conversationId: root.conversationId,
    threadId: root.id,
  });

  return (
    <Card size="sm" className="min-h-0">
      <CardHeader>
        <CardTitle>{t("Thread")}</CardTitle>
        <CardAction>
          <Button
            type="button"
            size="icon-sm"
            variant="ghost"
            aria-label={t("Close the thread")}
            onClick={onClose}
          >
            <XIcon aria-hidden />
          </Button>
        </CardAction>
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col gap-3">
        {thread.error ? (
          <Alert variant="destructive" aria-live="polite">
            <AlertTitle>{errorMessage(thread.error)}</AlertTitle>
            <AlertAction>
              <Button
                type="button"
                size="sm"
                variant="outline"
                onClick={() => void thread.refresh()}
              >
                <RotateCwIcon aria-hidden />
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : null}
        {thread.messages === undefined ? (
          <div
            className="flex flex-col gap-4"
            aria-busy="true"
            aria-live="polite"
          >
            <span className="sr-only">{t("Loading the thread")}</span>
            <Skeleton className="h-12" />
            <Skeleton className="h-12" />
          </div>
        ) : (
          <ScrollArea className="min-h-0 flex-1">
            <div className="flex flex-col gap-4 pr-3">
              <ol>
                <MessageItem message={root} />
              </ol>
              <Separator />
              {thread.messages.length === 0 ? (
                <Empty>
                  <EmptyHeader>
                    <EmptyMedia variant="icon">
                      <MessageSquareIcon />
                    </EmptyMedia>
                    <EmptyTitle>{t("No replies yet")}</EmptyTitle>
                    <EmptyDescription>
                      {t("Replies stay here, out of the channel.")}
                    </EmptyDescription>
                  </EmptyHeader>
                  <EmptyContent>
                    <Button
                      type="button"
                      size="sm"
                      onClick={() => input.current?.focus()}
                    >
                      {t("Reply")}
                    </Button>
                  </EmptyContent>
                </Empty>
              ) : (
                <ol className="flex flex-col gap-4">
                  {thread.messages.map((message) => (
                    <MessageItem key={message.id} message={message} />
                  ))}
                </ol>
              )}
            </div>
          </ScrollArea>
        )}
      </CardContent>
      <CardFooter className="flex-col items-stretch">
        <MessageComposer
          conversationId={root.conversationId}
          inputRef={input}
          placeholder={t("Reply in the thread")}
          onSend={thread.send}
          onTyping={thread.setTyping}
        />
      </CardFooter>
    </Card>
  );
}
// #endregion recipe:thread-panel
