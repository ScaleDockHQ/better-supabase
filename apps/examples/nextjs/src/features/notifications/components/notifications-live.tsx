"use client";

import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";

import { useUnreadCount } from "./unread-badge";

/**
 * A "3 new" banner on the caller's private topic. It refreshes the page when
 * clicked, so the list never reflows while it is being read.
 */
export function NotificationsLive({
  initialUnread,
}: {
  initialUnread: number;
}) {
  const t = useExtracted("notifications");
  const router = useRouter();
  const { count } = useUnreadCount();

  const fresh = count === undefined ? 0 : count - initialUnread;

  if (fresh <= 0) {
    return null;
  }

  return (
    <Button
      variant="secondary"
      size="sm"
      className="justify-self-start"
      data-testid="notifications-new"
      onClick={() => {
        router.refresh();
      }}
    >
      {t("{count, number} new", { count: fresh })}
    </Button>
  );
}
