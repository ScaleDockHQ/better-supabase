// #region recipe:notification-list
"use client";

import { useNotifications } from "better-supabase/blocks/notifications/react";
import { BellIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { useAuth } from "@/lib/hooks";

import type { NotificationRow } from "../notification-types";

import { loadNotifications } from "../notifications-actions";

async function loadRows(): Promise<readonly NotificationRow[]> {
  const result = await loadNotifications({});
  return result.ok ? result.data : [];
}

/**
 * The caller's latest notifications, loaded again after each broadcast on
 * their private topic `notifications:<user id>`: a new one, or one marked read.
 */
export function NotificationList() {
  const t = useExtracted("notifications");
  const format = useFormatter();
  const auth = useAuth();
  const userId = auth.user?.id;
  const { items } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load: loadRows,
  });
  if (items === undefined) return <NotificationListSkeleton />;
  if (items.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <BellIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Nothing here yet")}</EmptyTitle>
          <EmptyDescription>
            {t("Send yourself a notification to see it arrive.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    );
  }
  return (
    <ul className="divide-y rounded-xl border">
      {items.map((notification) => (
        <li
          key={notification.id}
          className="flex items-center gap-3 px-4 py-3 text-sm"
        >
          <span className="flex-1">{notification.title}</span>
          {notification.readAt ? null : <Badge>{t("New")}</Badge>}
          <span className="text-muted-foreground text-xs tabular-nums">
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

function NotificationListSkeleton() {
  return (
    <div className="space-y-2" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <Skeleton key={index} className="h-11 w-full" />
      ))}
    </div>
  );
}
// #endregion recipe:notification-list
