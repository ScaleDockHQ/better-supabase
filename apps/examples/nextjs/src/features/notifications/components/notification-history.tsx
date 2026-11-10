import { BellIcon } from "lucide-react";
import { getExtracted } from "next-intl/server";

import { buttonVariants } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { Link } from "@/i18n/navigation";

import type { NotificationFilters } from "../notifications-queries";

import { getNotificationPage } from "../notifications-queries";
import { NotificationRows } from "./notification-rows";
import { NotificationsLive } from "./notifications-live";

function hrefOf(filters: NotificationFilters, before: string | null) {
  const query: Record<string, string> = {};

  if (filters.status !== "all") {
    query["status"] = filters.status;
  }

  if (filters.type) {
    query["type"] = filters.type;
  }

  if (before) {
    query["before"] = before;
  }

  return { pathname: "/notifications", query } as const;
}

/**
 * The first page of the caller's notifications, rendered on the server, with
 * the status and type filters in the URL and Older as a link.
 */
export async function NotificationHistory({
  tenant,
  filters,
}: {
  tenant: string;
  filters: NotificationFilters;
}) {
  const [t, page] = await Promise.all([
    getExtracted("notifications"),
    getNotificationPage(tenant, filters),
  ]);

  return (
    <div className="grid gap-4">
      <div className="flex gap-2">
        {(["all", "unread"] as const).map((status) => (
          <Link
            key={status}
            href={hrefOf({ ...filters, status }, null)}
            className={buttonVariants({
              variant: filters.status === status ? "secondary" : "ghost",
              size: "sm",
            })}
          >
            {status === "all" ? t("All") : t("Unread")}
          </Link>
        ))}
      </div>
      <NotificationsLive initialUnread={page.unread} />
      {page.items.length === 0 ? (
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
      ) : (
        <NotificationRows items={page.items} />
      )}
      <div className="flex items-center justify-between gap-2">
        {filters.before ? (
          <Link
            href={hrefOf(filters, null)}
            prefetch={false}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Newest")}
          </Link>
        ) : (
          <span />
        )}
        {page.next ? (
          <Link
            href={hrefOf(filters, page.next)}
            prefetch={false}
            className={buttonVariants({ variant: "outline", size: "sm" })}
          >
            {t("Older")}
          </Link>
        ) : null}
      </div>
    </div>
  );
}

export function NotificationHistorySkeleton() {
  return (
    <div className="space-y-2" aria-busy="true">
      {Array.from({ length: 4 }, (_, index) => (
        <Skeleton key={index} className="h-11 w-full" />
      ))}
    </div>
  );
}
