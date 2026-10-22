"use client";

import { useAction } from "better-supabase/react";
import { ClockIcon, TriangleAlertIcon, XIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useEffect, useEffectEvent } from "react";
import { toast } from "sonner";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import { cancelScheduled, loadScheduled } from "../inbox-actions";

/**
 * The caller's replies on the conversation that wait to go out. Empty, it
 * renders nothing: the composer's Send later right below adds one. Change its
 * `key` to load it again.
 */
export function ScheduledReplies({
  conversationId,
}: {
  conversationId: string;
}) {
  const t = useExtracted("inbox");
  const format = useFormatter();
  const errorMessage = useErrorMessage();
  const list = useAction(loadScheduled);

  const reload = () => {
    void list.run({ conversationId });
  };

  const cancel = useAction(cancelScheduled, {
    onSuccess: reload,
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const load = useEffectEvent((id: string) => {
    void list.run({ conversationId: id });
  });

  useEffect(() => {
    load(conversationId);
  }, [conversationId]);

  if (list.error !== undefined) {
    return (
      <div className="px-4 pb-2">
        <Alert variant="destructive">
          <TriangleAlertIcon />
          <AlertTitle>{t("The scheduled replies didn't load")}</AlertTitle>
          <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
          <AlertAction>
            <Button size="sm" variant="outline" onClick={reload}>
              {t("Retry")}
            </Button>
          </AlertAction>
        </Alert>
      </div>
    );
  }

  if (list.data === undefined) {
    return (
      <div className="px-4 pb-2" aria-busy="true">
        <Skeleton className="h-8 w-full" />
      </div>
    );
  }

  if (list.data.length === 0) {
    return null;
  }

  return (
    <section
      aria-label={t("Scheduled replies")}
      className="flex flex-col gap-1 px-4 pb-2"
    >
      <h3 className="text-xs font-medium text-muted-foreground">
        {t("Scheduled replies")}
      </h3>
      <ul className="flex flex-col gap-1">
        {list.data.map((scheduled) => (
          <li
            key={scheduled.id}
            className="flex items-center gap-2 text-sm text-muted-foreground"
          >
            <ClockIcon className="size-4 shrink-0" aria-hidden />
            <span className="shrink-0 text-xs tabular-nums">
              {format.dateTime(new Date(scheduled.scheduledFor), {
                dateStyle: "medium",
                timeStyle: "short",
              })}
            </span>
            <span className="min-w-0 flex-1 truncate">{scheduled.body}</span>
            <Button
              size="icon-sm"
              variant="ghost"
              aria-label={t("Cancel scheduled reply")}
              disabled={cancel.pendingInputs.some(
                (input) => input.scheduledId === scheduled.id,
              )}
              onClick={() => {
                void cancel.run({ scheduledId: scheduled.id });
              }}
            >
              <XIcon />
            </Button>
          </li>
        ))}
      </ul>
    </section>
  );
}
