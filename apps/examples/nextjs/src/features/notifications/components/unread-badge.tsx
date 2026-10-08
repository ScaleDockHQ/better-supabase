"use client";

import type { NotificationCounts } from "better-supabase/blocks/notifications";

import { useNotifications } from "better-supabase/blocks/notifications/react";
import { BellIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Link } from "@/i18n/navigation";
import { useAuth } from "@/lib/hooks";

import { loadNotificationCounts } from "../notifications-actions";

async function loadCounts(): Promise<readonly NotificationCounts[]> {
  const result = await loadNotificationCounts({});
  return result.ok ? [result.data] : [];
}

const unreadOf = (counts: readonly NotificationCounts[]): number =>
  counts[0]?.unread ?? 0;

/**
 * The unread count from the block's `counts()`, loaded again after each
 * broadcast on the caller's private topic `notifications:<user id>`.
 */
function useUnreadCount() {
  const auth = useAuth();
  const userId = auth.user?.id;
  const { items, count, status } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load: loadCounts,
    count: unreadOf,
  });
  return { count: items === undefined ? undefined : count, status };
}

/**
 * The header badge. Part of the static shell, so it loads from the browser
 * instead of adding a database call to every page.
 */
export function UnreadBadge() {
  const t = useExtracted("notifications");
  const { count, status } = useUnreadCount();
  return (
    <Link
      href="/notifications"
      className={buttonVariants({ variant: "ghost", size: "sm" })}
      data-testid="unread-badge"
      data-status={status}
      aria-label={t("Notifications, {count, number} unread", {
        count: count ?? 0,
      })}
    >
      <BellIcon />
      <Badge
        variant={count ? "default" : "secondary"}
        className="tabular-nums"
        data-testid="unread-count"
      >
        {count ?? "–"}
      </Badge>
    </Link>
  );
}

/** The summary on /notifications, live on the same topic as the badge. */
export function UnreadSummary() {
  const t = useExtracted("notifications");
  const { count } = useUnreadCount();
  return (
    <p className="text-muted-foreground text-sm" data-testid="unread-summary">
      {count === undefined
        ? t("Counting…")
        : t("{count, number} unread", { count })}
    </p>
  );
}
