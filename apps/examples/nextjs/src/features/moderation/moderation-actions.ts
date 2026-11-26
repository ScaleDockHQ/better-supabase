"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
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
  },
  async ({ itemId, decision, reason }, { db, auth }) => {
    const decided = reason
      ? await db.moderation.decide({ itemId, decision, reason })
      : await db.moderation.decide({ itemId, decision });

    if (!decided.ok) {
      return decided;
    }

    await refreshCaller(auth, [tags.moderation()]);

    return ok(decided.data.id);
  },
);

/** Lifts a ban. */
export const liftBan = bsb.action(
  {
    input: v.object({ banId: Id }),
    requireTenant: true,
    permission: "moderation.ban",
  },
  async ({ banId }, { db, auth }) => {
    const lifted = await db.moderation.unban(banId);

    if (!lifted.ok) {
      return lifted;
    }

    await refreshCaller(auth, [tags.moderation()]);

    return ok(lifted.data);
  },
);
