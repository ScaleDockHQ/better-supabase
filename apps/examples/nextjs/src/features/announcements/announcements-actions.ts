"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Hides an announcement for the signed-in user. */
export const dismissAnnouncement = bsb.action(
  { input: v.object({ id: v.pipe(v.string(), v.uuid()) }) },
  async ({ id }, { db, auth }) => {
    const dismissed = await db.announcements.dismiss(id);

    if (!dismissed.ok) {
      return dismissed;
    }

    await refreshCaller(auth, [tags.announcements()]);

    return ok(dismissed.data);
  },
);
