import type { CatalogTable } from "../introspect/types.ts";
import type { DoctorContext } from "./rules.ts";

import { qualified } from "./shared.ts";

/** A `columns.<table>.tenant` name, when the entry is a string or `{ column }`. */
function mappedTenant(value: unknown): string | undefined {
  if (typeof value === "string" && value !== "") {
    return value;
  }

  if (
    typeof value === "object" &&
    value !== null &&
    "column" in value &&
    typeof value.column === "string" &&
    value.column !== ""
  ) {
    return value.column;
  }

  return undefined;
}

/**
 * The column a table's tenant queries filter on: `columns.<table>.tenant`, then
 * `user_id` for an app table in user scope, then `sql.tenantColumn` or the
 * memberships column.
 */
export function tenantColumnOf(
  context: DoctorContext,
  table: CatalogTable,
): string | undefined {
  const name = `${table.schema}.${table.name}`;

  for (const block of Object.values(context.config.blocks)) {
    if (typeof block !== "object" || !("columns" in block)) {
      continue;
    }

    const columns = block.columns;

    if (typeof columns !== "object") {
      continue;
    }

    const mapped =
      mappedTenant(columns[table.name]?.["tenant"]) ??
      mappedTenant(columns[name]?.["tenant"]);

    if (mapped !== undefined) {
      return mapped;
    }
  }

  const app =
    table.schema === "public"
      ? context.config.appTables[table.name]
      : undefined;

  const scope =
    app === undefined
      ? undefined
      : app.scope === undefined || app.scope === "inherit"
        ? (context.config.sql.scope ?? "tenant")
        : app.scope;

  if (scope === "user") {
    return "user_id";
  }

  return (
    context.config.sql.tenantColumn ?? context.config.extensions.tenant?.column
  );
}

/** Why `column` cannot serve a tenant filter, with the index to add. */
export function tenantIndexGap(
  table: CatalogTable,
  column: string,
): string | undefined {
  const leading = table.indexes.filter((index) => index.columns[0] === column);

  const serves = leading.some(
    (index) => !index.partial || index.predicate === null,
  );

  if (serves) {
    return undefined;
  }

  const fix = `create index on ${qualified(table)} (${column});`;

  const target = `${qualified(table)}.${column}`;

  if (leading.length > 0) {
    return `${target} only has a partial index starting with it, so a query that does not match the predicate scans the table. Run \`${fix}\`.`;
  }

  if (table.indexes.some((index) => index.columns.includes(column))) {
    return `${target} is in an index but not first, so a filter on it cannot use that index. Run \`${fix}\`.`;
  }

  return `${target} has no index starting with it. Run \`${fix}\`.`;
}
