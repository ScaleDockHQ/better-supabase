"use client";

import type { NotificationCounts } from "better-supabase/blocks/notifications";

import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";

import { Button } from "@/components/ui/button";
import { useNotifications } from "@/hooks/use-notifications";
import { useAuth } from "@/lib/hooks";

import { loadNotificationCounts } from "../notifications-actions";

async function loadCounts(): Promise<readonly NotificationCounts[]> {
  const result = await loadNotificationCounts({});

  return result.ok ? [result.data] : [];
}

const unreadOf = (counts: readonly NotificationCounts[]): number =>
  counts[0]?.unread ?? 0;

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
  const userId = useAuth().user?.id;

  const { items, count } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load: loadCounts,
    count: unreadOf,
  });

  const fresh = items === undefined ? 0 : count - initialUnread;

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
