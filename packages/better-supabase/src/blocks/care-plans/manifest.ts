import type { BlockOf } from "../define-block.ts";
import type { CarePlansEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCarePlans } from "./care-plans.ts";
import { carePlansEvents } from "./events.ts";
import { carePlansSqlOptions } from "./options.ts";
import {
  carePlanActionInputSchema,
  carePlanGoalInputSchema,
  carePlanInputSchema,
  carePlanProblemInputSchema,
} from "./schemas.ts";

/** The `care-plans` block's manifest (ADR 0029, ADR 0135). */
export const carePlansBlock: BlockOf<
  "care-plans",
  typeof createCarePlans,
  CarePlansEvents
> = defineBlock({
  name: "care-plans",
  sql: ["care-plans"],
  options: { "care-plans": carePlansSqlOptions },
  events: carePlansEvents,
  schemas: {
    care_plan: { input: carePlanInputSchema },
    care_plan_problem: { input: carePlanProblemInputSchema },
    care_plan_goal: { input: carePlanGoalInputSchema },
    care_plan_action: { input: carePlanActionInputSchema },
  },
  create: createCarePlans,
  recipes: ["care-plan-editor", "care-plan-evaluations"],
  category: "people",
  entities: {
    care_plan: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    care_plan_problem: {
      mutability: "editable",
      emits: { create: false, update: false },
    },
    care_plan_goal: {
      mutability: "editable",
      emits: { create: false, update: false },
    },
    care_plan_action: {
      mutability: "editable",
      emits: { create: false, update: false },
    },
    care_plan_evaluation: {
      mutability: "append-only",
      emits: { create: true },
    },
  },
  description:
    "Care plans per client: problems with codes from your code systems, goals and the actions that reach them, evaluations over time, one active plan per client published as a version, agreement through a signature, and restrictive measures that start only once approved.",
  schedules: [
    {
      name: "reviews",
      cron: "0 6 * * *",
      runs: "dueReviews()",
      description:
        "Reports the care plans and actions whose review has come due.",
    },
  ],
});
