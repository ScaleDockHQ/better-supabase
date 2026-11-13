import type { BlockOf } from "../define-block.ts";
import type { AppraisalsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAppraisals } from "./appraisals.ts";
import { appraisalsEvents } from "./events.ts";
import { appraisalListSurface } from "./lists.ts";
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
  entities: {
    appraisal: {
      ...appraisalListSurface,
      mutability: "state-machine",
      emits: { create: true },
    },
    appraisal_cycle: { mutability: "state-machine", emits: { create: true } },
    appraisal_review: { mutability: "state-machine", emits: { create: false } },
    appraisal_calibration: { mutability: "read-only" },
    appraisal_goal: { mutability: "read-only" },
    appraisal_competency: { mutability: "read-only" },
    appraisal_review_rating: { mutability: "read-only" },
  },
  concerns: ["lifecycle"],
  description:
    "Performance appraisals: review cycles that can follow an enrollment program and carry a rubric of weighted competencies, one appraisal per person with self, peer and manager reviews, anonymous peer reviewers, goals, calibration sessions that keep their reason, and sign-off through approvals.",
});
