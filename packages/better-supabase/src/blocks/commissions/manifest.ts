import type { BlockOf } from "../define-block.ts";
import type { CommissionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCommissions } from "./commissions.ts";
import { commissionsEvents } from "./events.ts";
import {
  commissionListSurface,
  commissionPlanListSurface,
  commissionStatementListSurface,
} from "./lists.ts";
import { commissionsSqlOptions } from "./options.ts";

/** The `commissions` block's manifest. */
export const commissionsBlock: BlockOf<
  "commissions",
  typeof createCommissions,
  CommissionsEvents
> = defineBlock({
  name: "commissions",
  sql: ["commissions"],
  events: commissionsEvents,
  schemas: {},
  options: { commissions: commissionsSqlOptions },
  create: createCommissions,
  recipes: [],
  category: "commerce",
  entities: {
    commission_plan: {
      ...commissionPlanListSurface,
      mutability: "editable",
      emits: { create: true, update: true },
      permissions: {
        read: "commissions.read",
        create: "commissions.write",
        update: "commissions.write",
        manage: "commissions.manage",
      },
    },
    commission_assignment: { mutability: "read-only" },
    commission: { ...commissionListSurface, mutability: "state-machine" },
    commission_statement: {
      ...commissionStatementListSurface,
      mutability: "state-machine",
    },
  },
  concerns: ["lifecycle"],
  description:
    "Commission plans (flat or marginal tiers) assigned to sellers, commissions accrued on the ledger from paid records, statements per period with a payout, and the lines payroll adds.",
});
