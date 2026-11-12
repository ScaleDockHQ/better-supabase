"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { REVIEWS_TAG } from "./reviews-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Publishes a pending review on the storefront. */
export const publishReview = bsb.action(
  {
    input: v.object({ reviewId: Id }),
    requireTenant: true,
    permission: "reviews.manage",
  },
  async ({ reviewId }, { db, auth }) => {
    const published = await db.reviews.publish(reviewId);

    if (!published.ok) {
      return published;
    }

    await refreshCaller(auth, [REVIEWS_TAG]);

    return ok(published.data.id);
  },
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
  },
  async ({ reviewId, kind, text }, { db, auth }) => {
    const done =
      kind === "reject"
        ? await db.reviews.reject({ reviewId, reason: text })
        : await db.reviews.reply({ reviewId, reply: text });

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, [REVIEWS_TAG]);

    return ok(done.data.id);
  },
);
