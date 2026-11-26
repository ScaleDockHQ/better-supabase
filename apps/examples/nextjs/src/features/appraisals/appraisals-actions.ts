"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const AppraisalId = v.pipe(v.string(), v.uuid());

const Rating = v.pipe(
  v.string(),
  v.toNumber(),
  v.integer(),
  v.minValue(1),
  v.maxValue(5),
);

/** A form sends one value as a string and repeated fields as an array. */
const Repeated = <T extends v.GenericSchema<string, unknown>>(item: T) =>
  v.pipe(
    v.union([item, v.array(item)]),
    v.transform((value): v.InferOutput<T>[] =>
      Array.isArray(value) ? value : [value],
    ),
  );

/**
 * Signs an appraisal off. With the approvals block the sign-off waits for its
 * approval.
 */
export const signOffAppraisal = bsb.blockAction(
  ({ db }) => db.appraisals,
  "signOff",
  {
    input: v.object({ appraisalId: AppraisalId }),
    requireTenant: true,
    permission: "appraisals.manage",
    tags: () => [tags.appraisals()],
    refresh: true,
    args: ({ appraisalId }) => [appraisalId],
  },
  (signed) => ({ status: signed.status }),
);

/**
 * Submits the caller's review. A rubric cycle takes one rating per competency
 * (`competency` and `rating` repeat in the same order); a cycle without one
 * takes a single `rating`. The last review moves the appraisal to reviewed.
 */
export const submitAppraisalReview = bsb.action(
  {
    input: v.object({
      reviewId: v.pipe(v.string(), v.uuid()),
      competency: v.optional(Repeated(v.pipe(v.string(), v.minLength(1)))),
      rating: Repeated(Rating),
      comments: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(4000))),
    }),
    requireTenant: true,
    permission: "appraisals.review",
    tags: () => [tags.appraisals()],
    refresh: true,
  },
  async ({ reviewId, competency, rating, comments }, { db }) => {
    const scores =
      competency === undefined
        ? { rating: rating[0] ?? 0 }
        : {
            ratings: competency.map((key, index) => ({
              competency: key,
              rating: rating[index] ?? 0,
            })),
          };

    const submitted = await db.appraisals.submitReview({
      reviewId,
      input:
        comments === undefined || comments === ""
          ? scores
          : { ...scores, comments },
    });

    if (!submitted.ok) {
      return submitted;
    }

    return ok({ status: submitted.data.status });
  },
);

/**
 * Moves the rating of a reviewed appraisal in a calibration session; the reason
 * and the previous rating stay on the appraisal.
 */
export const calibrateAppraisal = bsb.blockAction(
  ({ db }) => db.appraisals,
  "calibrate",
  {
    input: v.object({
      appraisalId: AppraisalId,
      rating: Rating,
      reason: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(2000)),
    }),
    requireTenant: true,
    permission: "appraisals.manage",
    tags: () => [tags.appraisals()],
    refresh: true,
  },
  (calibrated) => ({ status: calibrated.status }),
);
