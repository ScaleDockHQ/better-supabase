import type { BlockScope } from "../../config/blocks.ts";
import type { AppTableConfig } from "../../config/types/app-tables.ts";
import type { BlockSqlLayout } from "../module-types.ts";

/** The scope an app table's rows live in: its own, or the layout's. */
export function appTableScope(
  table: AppTableConfig,
  layout: BlockSqlLayout,
): BlockScope {
  switch (table.scope) {
    case "user":
    case "none": {
      return table.scope;
    }

    case undefined:
    case "inherit": {
      return layout.scope ?? "tenant";
    }

    default: {
      const never: never = table.scope;

      throw new TypeError(`Unknown app table scope "${String(never)}"`);
    }
  }
}
