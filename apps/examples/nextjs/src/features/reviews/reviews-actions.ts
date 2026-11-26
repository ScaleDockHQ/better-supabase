"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Publishes a pending review on the storefront. */
export const publishReview = bsb.blockAction(
  ({ db }) => db.reviews,
  "publish",
  {
    input: v.object({ reviewId: Id }),
    requireTenant: true,
    permission: "reviews.manage",
    tags: () => [tags.reviews()],
    refresh: true,
    args: ({ reviewId }) => [reviewId],
  },
  (published) => published.id,
);

/** Rejects a review with a reason the author sees, or sets the public reply. */
export const respondToReview = bsb.action(
  {
    input: v.object({
      reviewId: Id,
      kind: v.picklist(["reject", "reply"]),
      text: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(1000)),
    }),
    requireTenant: true,
    permission: "reviews.manage",
    tags: () => [tags.reviews()],
    refresh: true,
  },
  async ({ reviewId, kind, text }, { db }) => {
    const done =
      kind === "reject"
        ? await db.reviews.reject({ reviewId, reason: text })
        : await db.reviews.reply({ reviewId, reply: text });

    if (!done.ok) {
      return done;
    }

    return ok(done.data.id);
  },
);
