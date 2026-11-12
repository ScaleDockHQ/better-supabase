"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { ANNOUNCEMENTS_TAG } from "./announcements-cache";

/** Hides an announcement for the signed-in user. */
export const dismissAnnouncement = bsb.action(
  { input: v.object({ id: v.pipe(v.string(), v.uuid()) }) },
  async ({ id }, { db, auth }) => {
    const dismissed = await db.announcements.dismiss(id);

    if (!dismissed.ok) {
      return dismissed;
    }

    await refreshCaller(auth, [ANNOUNCEMENTS_TAG]);

    return ok(dismissed.data);
  },
);
