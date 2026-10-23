"use server";

import { ok } from "better-supabase";

import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

/** A notification as plain data, so it crosses the server boundary. */
export interface NotificationRow {
  readonly id: string;
  readonly title: string;
  readonly readAt: string | null;
  readonly createdAt: string;
}

/**
 * The caller's latest notifications in the active organization, for
 * `useNotifications`.
 */
export const loadNotifications = bsb.action(
  { requireOrganization: true },
  async (_input, { tenant, supabase }) => {
    const items = await blocks(supabase).notifications.list({
      tenant,
      limit: 20,
    });

    if (!items.ok) {
      return items;
    }

    return ok(
      items.data.map((item): NotificationRow => ({
        id: item.id,
        title: item.text?.title ?? item.summary ?? item.type,
        readAt: item.readAt?.toString() ?? null,
        createdAt: item.createdAt.toString(),
      })),
    );
  },
);

/** The badge numbers, loaded again after each broadcast on the caller's topic. */
export const loadNotificationCounts = bsb.action(
  { requireOrganization: true },
  async (_input, { tenant, supabase }) =>
    blocks(supabase).notifications.counts({ tenant }),
);

/** Marks the caller's notifications in the active organization read. */
export const markAllRead = bsb.action(
  { requireOrganization: true },
  async (_input, { tenant, supabase }) => {
    const updated = await blocks(supabase).notifications.markRead({ tenant });

    return updated.ok ? ok(updated.data.count) : updated;
  },
);
