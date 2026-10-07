import { InboxIcon } from "lucide-react";
import { getExtracted, getFormatter } from "next-intl/server";

import { Badge } from "@/components/ui/badge";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";

import { getNotifications } from "../inbox-queries";

/** Render inside `<Suspense>`. */
export async function NotificationList() {
  const [notifications, t, format] = await Promise.all([
    getNotifications(),
    getExtracted("inbox"),
    getFormatter(),
  ]);
  if (notifications.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <InboxIcon />
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
      {notifications.map((notification) => (
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

export function NotificationListSkeleton() {
  return (
    <div className="space-y-2" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <Skeleton key={index} className="h-11 w-full" />
      ))}
    </div>
  );
}
