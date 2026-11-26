"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

/** Hides an announcement for the signed-in user. */
export const dismissAnnouncement = bsb.blockAction(
  ({ db }) => db.announcements,
  "dismiss",
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    tags: () => [tags.announcements()],
    refresh: true,
    args: ({ id }) => [id],
  },
);
