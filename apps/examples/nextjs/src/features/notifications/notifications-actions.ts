"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

import { toNotificationRow } from "./notification-types";

/**
 * Sends the caller a notification (the notifications SQL module checks
 * `notifications.send`); the badge updates on `notifications:<user id>`.
 */
export const notifyMe = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
  },
  async ({ title }, { tenant, auth, supabase }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to get notifications"));
    }

    const sent = await blocks(supabase).notifications.send("test.sent", {
      tenant,
      recipients: [auth.user.id],
      includeActor: true,
      data: { title },
    });

    if (!sent.ok) {
      return sent;
    }

    refresh();

    return ok(sent.data?.id ?? null);
  },
);

/** Marks the caller's notifications in the active organization read. */
export const markAllRead = bsb.action(
  { requireTenant: true },
  async (_input, { tenant, supabase }) => {
    const updated = await blocks(supabase).notifications.markRead({ tenant });

    if (!updated.ok) {
      return updated;
    }

    refresh();

    return ok(updated.data.count);
  },
);

/** The badge numbers, loaded by `useNotifications` after each broadcast. */
export const loadNotificationCounts = bsb.blockAction(
  ({ supabase }) => blocks(supabase).notifications,
  "counts",
  { requireTenant: true, args: (_input, { tenant }) => [{ tenant }] },
);

/**
 * The caller's latest notifications, loaded by `useNotifications` after each
 * broadcast.
 */
export const loadNotifications = bsb.action(
  { requireTenant: true },
  async (_input, { tenant, supabase }) => {
    const items = await blocks(supabase).notifications.list({
      tenant,
      limit: 20,
    });

    return items.ok ? ok(items.data.map(toNotificationRow)) : items;
  },
);
