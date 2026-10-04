import type {
  Catalog,
  CatalogPolicy,
  CatalogTable,
  Snapshot,
} from "../introspect/types.ts";
import type { DoctorContext, SqlObject } from "./rules.ts";

import { toCatalog } from "../introspect/catalog.ts";
import { tomlGet } from "../supabase-toml.ts";

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

/** `[api] schemas` from `config.toml`, the schemas PostgREST serves, or `config.schemas` without one. */
export function exposedSchemas(context: DoctorContext): readonly string[] {
  const listed = context.configToml
    ? tomlGet(context.configToml.document, ["api", "schemas"])
    : undefined;
  return Array.isArray(listed) &&
    listed.every((entry): entry is string => typeof entry === "string")
    ? listed
    : context.config.schemas;
}

export const exposed = (context: DoctorContext): CatalogTable[] => {
  const schemas = exposedSchemas(context);
  return catalogOf(context).tables.filter((table) =>
    schemas.includes(table.schema),
  );
};

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

const splitTexts = new Map<string, readonly string[]>();
const SPLIT_CACHE_SIZE = 64;

/** `text` split into lines; doctor locates many objects in the same SQL files. */
function linesOf(text: string): readonly string[] {
  let lines = splitTexts.get(text);
  if (!lines) {
    if (splitTexts.size >= SPLIT_CACHE_SIZE) splitTexts.clear();
    lines = text.split("\n");
    splitTexts.set(text, lines);
  }
  return lines;
}

/** Line number (1-based) of the first line matching `pattern`. */
export function lineOf(text: string, pattern: RegExp): number | undefined {
  const index = linesOf(text).findIndex((line) => pattern.test(line));
  return index === -1 ? undefined : index + 1;
}
