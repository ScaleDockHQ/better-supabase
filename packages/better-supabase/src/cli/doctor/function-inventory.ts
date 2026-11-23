import type { FindingInput, Rule } from "./rules.ts";

import {
  FUNCTION_CALLERS,
  functionCounts,
  listFunctions,
} from "../../sql/index.ts";

export const FUNCTION_INVENTORY_RULES: readonly Rule[] = [
  {
    code: "BS643",
    severity: "info",
    title: "Functions by caller",
    description:
      "One finding per schema with how many of its functions a policy calls, a trigger runs, `anon` or `authenticated` may execute (app RPC), only `service_role` may execute (service only), or nothing names (unreferenced). An unreferenced function may still be called by another function. `better-supabase config functions --all` lists each one. Information only; doctor drops nothing. Snapshots saved before this release have no inventory and skip it.",
    check: (context) => {
      const inventory = context.snapshot.extras.functionInventory;

      if (inventory === undefined) {
        return [];
      }

      return Object.entries(functionCounts(listFunctions(inventory))).map(
        ([schema, row]): FindingInput => ({
          message: `${schema}: ${FUNCTION_CALLERS.map((caller) => `${String(row[caller])} ${caller}`).join(", ")}. Run \`better-supabase config functions --all\` for the list.`,
          target: schema,
        }),
      );
    },
  },
];
