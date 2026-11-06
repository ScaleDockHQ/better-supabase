import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { quotedTable } from "../shared.ts";

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

/** Where a tenant's brand lives: `{ table, column, tenant? }`, quoted. */
export interface BrandSource {
  readonly table: string;
  readonly column: string;
  readonly tenant: string;
}

/**
 * `options.brand` of a block: the table and column that hold a tenant's brand,
 * and the column with the tenant id (`id` by default, for a column on the
 * tenant table). Undefined when the option is unset. `where` names the option
 * in error messages.
 */
export function brandSourceOf(
  ctx: BlockSqlContext,
  where: string,
): BrandSource | undefined {
  const option = ctx.option("brand");

  if (option === undefined) {
    return undefined;
  }

  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(`${where} must be { table, column, tenant? }`);
  }

  const entries = new Map<string, unknown>(Object.entries(option));

  const ident = (key: string, fallback?: string): string => {
    const value = entries.get(key) ?? fallback;

    if (typeof value !== "string" || !IDENT.test(value)) {
      throw new TypeError(`${where}.${key} must be a lowercase identifier`);
    }

    return sqlIdent(value);
  };

  const table = entries.get("table");

  if (
    typeof table !== "string" ||
    table.split(".").length > 2 ||
    !table.split(".").every((part) => IDENT.test(part))
  ) {
    throw new TypeError(`${where}.table must be "table" or "schema.table"`);
  }

  return {
    table: quotedTable(table),
    column: ident("column"),
    tenant: ident("tenant", "id"),
  };
}
