"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Hides an announcement for the signed-in user. */
export const dismissAnnouncement = bsb.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    tags: () => [tags.announcements()],
    refresh: true,
  },
  async ({ id }, { db }) => {
    const dismissed = await db.announcements.dismiss(id);

    if (!dismissed.ok) {
      return dismissed;
    }

    return ok(dismissed.data);
  },
);
