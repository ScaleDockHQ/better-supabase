import type {
  Catalog,
  CatalogPolicy,
  CatalogTable,
  Snapshot,
} from "../introspect/types.ts";
import type { DoctorContext, SqlObject } from "./rules.ts";

import { toCatalog } from "../introspect/catalog.ts";

const catalogs = new WeakMap<Snapshot, Catalog>();

/** The snapshot joined per table and function, computed once per snapshot. */
export function catalogOf(context: DoctorContext): Catalog {
  let catalog = catalogs.get(context.snapshot);
  if (!catalog) {
    catalog = toCatalog(context.snapshot);
    catalogs.set(context.snapshot, catalog);
  }
  return catalog;
}

export const exposed = (context: DoctorContext): CatalogTable[] =>
  catalogOf(context).tables.filter((table) =>
    context.config.schemas.includes(table.schema),
  );

export const qualified = (table: CatalogTable): string =>
  `${table.schema}.${table.name}`;

export const tableObject = (table: CatalogTable): SqlObject => ({
  kind: "table",
  schema: table.schema,
  name: table.name,
});

export const policyObject = (
  table: CatalogTable,
  policy: CatalogPolicy,
): SqlObject => ({
  kind: "policy",
  schema: table.schema,
  name: policy.name,
});

/** Line number (1-based) of the first line matching `pattern`. */
export function lineOf(text: string, pattern: RegExp): number | undefined {
  const index = text.split("\n").findIndex((line) => pattern.test(line));
  return index === -1 ? undefined : index + 1;
}
