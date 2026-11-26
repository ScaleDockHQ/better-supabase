"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Approves, hides, removes or restores a moderated item. */
export const decideItem = bsb.action(
  {
    input: v.object({
      itemId: Id,
      decision: v.picklist(["approve", "hide", "remove", "restore"]),
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "moderation.manage",
    tags: () => [tags.moderation()],
    refresh: true,
  },
  async ({ itemId, decision, reason }, { db }) => {
    const decided = reason
      ? await db.moderation.decide({ itemId, decision, reason })
      : await db.moderation.decide({ itemId, decision });

    if (!decided.ok) {
      return decided;
    }

    return ok(decided.data.id);
  },
);

/** Lifts a ban. */
export const liftBan = bsb.blockAction(({ db }) => db.moderation, "unban", {
  input: v.object({ banId: Id }),
  requireTenant: true,
  permission: "moderation.ban",
  tags: () => [tags.moderation()],
  refresh: true,
  args: ({ banId }) => [banId],
});
