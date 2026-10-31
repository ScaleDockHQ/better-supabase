import type { EntitySchema } from "../entity-schema.ts";
import type {
  AppraisalCycleInput,
  AppraisalReviewInput,
} from "./appraisals.ts";

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
    },
  });

/** What `submitReview` takes. */
export const appraisalReviewInputSchema: EntitySchema<AppraisalReviewInput> =
  entitySchema<AppraisalReviewInput>({
    title: "AppraisalReviewInput",
    fields: {
      rating: { kind: "integer", minimum: 1, maximum: 5 },
      comments: { kind: "string", optional: true, maxLength: 10_000 },
      submissionId: {
        kind: "uuid",
        optional: true,
        description: "The forms submission that holds the longer answers.",
      },
    },
  });
