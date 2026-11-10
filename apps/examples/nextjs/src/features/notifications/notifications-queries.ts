import "server-only";
import { bsb } from "@/lib/supabase/server";

import type { NotificationRow } from "./notification-types";
import type { loadNotificationFilters } from "./notifications-search-params";

import { toNotificationRow } from "./notification-types";
import { NOTIFICATION_PAGE_SIZE } from "./notifications-search-params";

type Notifications = Awaited<
  ReturnType<typeof bsb.cached>
>["db"]["notifications"];

type PageArgs = {
  -readonly [
    K in keyof NonNullable<Parameters<Notifications["page"]>[0]>
  ]: NonNullable<Parameters<Notifications["page"]>[0]>[K];
};

export type NotificationFilters = Awaited<
  ReturnType<typeof loadNotificationFilters>
>;

export interface NotificationPageData {
  readonly items: readonly NotificationRow[];
  /** The `before` of the next, older page, or null on the last. */
  readonly next: string | null;
  readonly unread: number;
}

function cursorOf(before: string | null) {
  const [at, id] = before?.split("|") ?? [];

  return at && id ? { createdAt: Temporal.Instant.from(at), id } : undefined;
}

// A user's inbox changes with every send, so this read stays dynamic.

/**
 * One page of the caller's notifications through the keyset cursor, and the
 * unread count capped at 100.
 */
export async function getNotificationPage(
  tenant: string,
  filters: NotificationFilters,
): Promise<NotificationPageData> {
  const { db } = await bsb.context();
  const cursor = cursorOf(filters.before);

  const options: PageArgs = {
    tenant,
    status: filters.status,
    limit: NOTIFICATION_PAGE_SIZE,
    totalCap: 1,
  };

  if (filters.type) {
    options.types = [filters.type];
  }

  if (cursor) {
    options.cursor = cursor;
  }

  const [page, counts] = await Promise.all([
    db.notifications.page(options).orThrow(),
    db.notifications.counts({ tenant }).orThrow(),
  ]);

  const last = page.items.at(-1);

  return {
    items: page.items.map(toNotificationRow),
    next:
      page.hasMore && last ? `${last.createdAt.toString()}|${last.id}` : null,
    unread: counts.unread,
  };
}
