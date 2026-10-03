"use server";

import { dbError, err } from "better-supabase";
import * as v from "valibot";

import { bs } from "@/lib/supabase/server";

/** Sends the caller a notification; the header badge updates over Realtime. */
export const notifyMe = bs.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
  },
  async ({ title }, { auth, db }) => {
    const organizationId =
      auth.kind === "user" ? auth.claims.app_metadata?.tenant_id : undefined;
    if (!organizationId) {
      return err(dbError("forbidden", "Your account has no organization"));
    }
    return db.notifications.create(
      { organizationId, title },
      { select: ["id"] },
    );
  },
);

export const markAllRead = bs.action({}, async (_input, { db }) =>
  db.notifications.updateMany({
    where: { readAt: null },
    data: { readAt: new Date().toISOString() },
  }),
);
