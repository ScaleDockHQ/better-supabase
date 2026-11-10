// #region recipe:notification-bell
"use client";

import type { NotificationCounts } from "better-supabase/blocks/notifications";

import { tenantOf } from "better-supabase/next";
import { useBlockEnv } from "better-supabase/react";
import { BellIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useCallback } from "react";

import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { useNotifications } from "@/hooks/use-notifications";
import { Link } from "@/i18n/navigation";
import { useAuth } from "@/lib/hooks";

/**
 * The badge numbers through the browser client: the `notification_counts`
 * function on the block's `api` schema, which `notifications.counts()` calls on
 * the server. Calling it directly keeps the notifications client, which renders
 * and delivers, out of the shell's first load (ADR 0643). Pass it as `load` to
 * `useNotifications`.
 */
function useNotificationCountsLoader(): () => Promise<
  readonly NotificationCounts[]
> {
  const { supabase } = useBlockEnv();
  const tenant = tenantOf(useAuth());

  return useCallback(async () => {
    if (tenant === undefined) {
      return [];
    }

    const result: { readonly data: unknown } = await supabase
      .schema("api")
      .rpc("notification_counts", { tenant, actionable: [] });

    // SAFETY: the function returns `{ unread, actionable, actionable_subjects }` as jsonb numbers.
    const counts = result.data as Record<string, number> | null;

    return counts
      ? [
          {
            unread: counts["unread"] ?? 0,
            actionable: counts["actionable"] ?? 0,
            actionableSubjects: counts["actionable_subjects"] ?? 0,
          },
        ]
      : [];
  }, [supabase, tenant]);
}

const unreadOf = (counts: readonly NotificationCounts[]): number =>
  counts[0]?.unread ?? 0;

/**
 * The unread count from the block's `counts()`, loaded again after each
 * broadcast on the caller's private topic `notifications:<user id>`.
 */
export function useUnreadCount() {
  const auth = useAuth();
  const userId = auth.user?.id;
  const load = useNotificationCountsLoader();

  const { items, count, status } = useNotifications({
    topic: userId ? `notifications:${userId}` : null,
    load,
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
        {count === undefined ? "–" : count >= 100 ? "99+" : count}
      </Badge>
    </Link>
  );
}

// #endregion recipe:notification-bell

/** The summary on /notifications, live on the same topic as the badge. */
export function UnreadSummary() {
  const t = useExtracted("notifications");
  const { count } = useUnreadCount();

  return (
    <p className="text-sm text-muted-foreground" data-testid="unread-summary">
      {count === undefined
        ? t("Counting…")
        : count >= 100
          ? t("99+ unread")
          : t("{count, number} unread", { count })}
    </p>
  );
}
