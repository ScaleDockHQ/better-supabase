"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * Sends the caller a notification (the notifications SQL module checks
 * `notifications.send`); the badge updates on `notifications:<user id>`.
 */
export const notifyMe = bs.action(
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
    if (!sent.ok) return sent;
    refresh();
    return ok(sent.data?.id ?? null);
  },
);

/** Marks the caller's notifications in the active organization read. */
export const markAllRead = bs.action(
  { requireTenant: true },
  async (_input, { tenant, supabase }) => {
    const updated = await blocks(supabase).notifications.markRead({ tenant });
    if (!updated.ok) return updated;
    refresh();
    return ok(updated.data.count);
  },
);

/** The badge numbers, loaded by `useNotifications` after each broadcast. */
export const loadNotificationCounts = bs.action(
  { requireTenant: true },
  async (_input, { tenant, supabase }) =>
    blocks(supabase).notifications.counts({ tenant }),
);
