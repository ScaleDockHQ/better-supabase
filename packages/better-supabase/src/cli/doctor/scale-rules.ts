import type { Rule } from "./rules.ts";

import { FUNCTION_INVENTORY_RULES } from "./function-inventory.ts";
import { POLICY_COUNT_RULES } from "./policy-count.ts";

/**
 * The rules that report how a schema grows: policies per table and the function
 * inventory (ADR 1216).
 */
export const SCALE_RULES: readonly Rule[] = [
  ...POLICY_COUNT_RULES,
  ...FUNCTION_INVENTORY_RULES,
];
