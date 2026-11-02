import type { BlockOf } from "../define-block.ts";
import type { AppraisalsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAppraisals } from "./appraisals.ts";
import { appraisalsEvents } from "./events.ts";
import {
  appraisalCycleInputSchema,
  appraisalReviewInputSchema,
} from "./schemas.ts";

/** The `appraisals` block's manifest (ADR 0029). */
export const appraisalsBlock: BlockOf<
  "appraisals",
  typeof createAppraisals,
  AppraisalsEvents
> = defineBlock({
  name: "appraisals",
  sql: ["appraisals"],
  events: appraisalsEvents,
  schemas: {
    appraisal_cycle: { input: appraisalCycleInputSchema },
    appraisal_review: { input: appraisalReviewInputSchema },
  },
  create: createAppraisals,
  recipes: [],
  category: "work",
  description:
    "Performance appraisals: review cycles that can follow an enrollment program and carry a rubric of weighted competencies, one appraisal per person with self, peer and manager reviews, anonymous peer reviewers, goals, calibration sessions that keep their reason, and sign-off through approvals.",
});
