import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createGoals } from "./goals.ts";

/** The `goals` block's manifest (ADR 0029). */
export const goalsBlock: BlockOf<"goals", typeof createGoals> = defineBlock({
  name: "goals",
  sql: ["goals"],
  create: createGoals,
  category: "crm",
  entities: { goal: { mutability: "editable", emits: { update: false } } },
  concerns: ["lifecycle"],
  description:
    "Goals per period for a member, a team or the organization, with progress the database computes for won deals, completed work items and paid invoices, or a value the app keeps.",
  recipes: ["targets-progress"],
});
