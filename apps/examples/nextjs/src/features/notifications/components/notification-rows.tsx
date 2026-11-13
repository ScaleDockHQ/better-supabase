"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { CheckIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { startTransition, useOptimistic } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import type { NotificationRow } from "../notification-types";

import { markRead } from "../notifications-actions";

/** The rows of a page; marking one read shows at once and the server confirms. */
export function NotificationRows({
  items,
}: {
  items: readonly NotificationRow[];
}) {
  const t = useExtracted("notifications");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const [shown, markShown] = useOptimistic(items, (current, readId: string) =>
    current.map((item) =>
      item.id === readId
        ? { ...item, readAt: item.readAt ?? new Date().toISOString() }
        : item,
    ),
  );

  const read = useAction(markRead, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <ul className="divide-y rounded-xl border" data-testid="notification-rows">
      {shown.map((notification) => (
        <li
          key={notification.id}
          className="flex items-center gap-3 px-4 py-3 text-sm"
        >
          <span className="flex-1">
            {notification.href ? (
              <a href={notification.href} className="underline">
                {notification.title}
              </a>
            ) : (
              notification.title
            )}
          </span>
          {notification.readAt ? null : (
            <>
              <Badge>{t("New")}</Badge>
              <Button
                variant="ghost"
                size="sm"
                aria-label={t("Mark read")}
                onClick={() => {
                  startTransition(() => {
                    markShown(notification.id);
                    void read.run({ ids: [notification.id] });
                  });
                }}
              >
                <CheckIcon />
              </Button>
            </>
          )}
          <span className="text-xs text-muted-foreground tabular-nums">
            {format.dateTime(new Date(notification.createdAt), {
              dateStyle: "medium",
              timeStyle: "short",
            })}
          </span>
        </li>
      ))}
    </ul>
  );
}
