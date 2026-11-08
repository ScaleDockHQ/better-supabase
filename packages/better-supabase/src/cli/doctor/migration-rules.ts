import type { Rule } from "./rules.ts";

import { NAMING_RENAME_RULES } from "./naming-renames.ts";
import { SHIM_RULES } from "./shims.ts";

/** Rules about names and code the library replaced: BS260 and the shims. */
export const MIGRATION_RULES: readonly Rule[] = [
  ...NAMING_RENAME_RULES,
  ...SHIM_RULES,
];
