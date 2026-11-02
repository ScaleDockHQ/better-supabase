import type { EntitySchema } from "../entity-schema.ts";
import type {
  AppraisalCycleInput,
  AppraisalReviewInput,
} from "./appraisals.ts";

import { APPRAISAL_ANONYMITY } from "../../sql/modules/appraisals-values.ts";
import { entitySchema } from "../entity-schema.ts";

/** What `createCycle` takes, with the bounds the SQL checks. */
export const appraisalCycleInputSchema: EntitySchema<AppraisalCycleInput> =
  entitySchema<AppraisalCycleInput>({
    title: "AppraisalCycleInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      startsOn: { kind: "string", description: "A date, `YYYY-MM-DD`." },
      endsOn: {
        kind: "string",
        description: "A date on or after `startsOn`, `YYYY-MM-DD`.",
      },
      program: {
        kind: "string",
        optional: true,
        description:
          "The key of an enrollment program the cycle's appraisals follow.",
      },
      anonymity: {
        kind: "enum",
        optional: true,
        values: APPRAISAL_ANONYMITY,
        description:
          "Who learns which peer wrote a review: `none`, `subject` (default) or `all`.",
      },
      shareFeedback: {
        kind: "boolean",
        optional: true,
        description:
          "Whether the appraised person reads the manager and peer reviews once signed off.",
      },
      competencies: {
        kind: "json",
        array: true,
        optional: true,
        description:
          "The rubric, at most 20 items: `{ key, name, weight }` with a weight above 0 (default 1).",
      },
    },
  });

/** What `submitReview` takes. */
export const appraisalReviewInputSchema: EntitySchema<AppraisalReviewInput> =
  entitySchema<AppraisalReviewInput>({
    title: "AppraisalReviewInput",
    fields: {
      rating: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 5,
        description: "The overall rating, for a cycle without a rubric.",
      },
      ratings: {
        kind: "json",
        array: true,
        optional: true,
        description:
          "One `{ competency, rating, comment }` per competency, for a cycle with a rubric.",
      },
      comments: { kind: "string", optional: true, maxLength: 10_000 },
      submissionId: {
        kind: "uuid",
        optional: true,
        description: "The forms submission that holds the longer answers.",
      },
    },
  });
