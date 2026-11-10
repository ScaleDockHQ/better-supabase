import type { AnyPlugin } from "../core/plugin.ts";
import type {
  AnyFunctions,
  AnyModels,
  RelationMeta,
  Schema,
  SchemaMeta,
  TableMeta,
} from "./types.ts";

/**
 * Binds generated model types to runtime metadata. Called from the generated
 * module; apps import the returned `schema`, never call this themselves.
 */
/*#__NO_SIDE_EFFECTS__*/
export function defineSchema<
  M extends AnyModels,
  D = unknown,
  F extends AnyFunctions = AnyFunctions,
  S extends string = string,
  E = unknown,
>(
  meta: SchemaMeta,
  extensions: readonly AnyPlugin[] = [],
): Schema<M, D, F, S, E> {
  return { meta: validateMeta(meta), extensions };
}

/**
 * A table's runtime metadata with its key as a literal type. Called from a
 * generated `tables/<table>.ts` module, so a page that imports one table ships
 * only that table's metadata.
 */
/*#__NO_SIDE_EFFECTS__*/
export function defineTable<const K extends string>(
  meta: TableMeta & { readonly key: K },
): TableModule<K> {
  return meta;
}

/** What a generated `tables/<table>.ts` exports as the table's runtime value. */
export type TableModule<K extends string = string> = TableMeta & {
  readonly key: K;
};

function validateMeta(meta: SchemaMeta): SchemaMeta {
  // oxlint-disable-next-line typescript/no-unnecessary-condition -- generated files from another release can carry another version.
  if (meta.version !== 1) {
    throw new TypeError(
      `better-supabase: unsupported schema metadata version ${String(meta.version)}. Run \`better-supabase gen\` again.`,
    );
  }

  if (meta.lazyTables !== true && meta.loadFunctions === undefined) {
    return meta;
  }

  return {
    ...meta,
    ...(meta.lazyTables === true ? { tables: { ...meta.tables } } : {}),
    ...(meta.loadFunctions === undefined
      ? {}
      : { functions: { ...meta.functions } }),
  };
}

export function tableMeta(meta: SchemaMeta, table: string): TableMeta {
  const found = meta.tables[table];

  if (!found) {
    throw new TypeError(`better-supabase: unknown table "${table}"`);
  }

  return found;
}

export function relationMeta(
  meta: SchemaMeta,
  table: TableMeta,
  relation: string,
): { relation: RelationMeta; target: TableMeta } {
  const found = table.relations[relation];

  if (!found) {
    throw new TypeError(
      `better-supabase: unknown relation "${relation}" on "${table.key}"`,
    );
  }

  return { relation: found, target: tableMeta(meta, found.table) };
}

/**
 * Adds `table` to the metadata of a schema that sets `lazyTables`. Returns
 * whether it was new.
 */
export function addLazyTable(meta: SchemaMeta, table: TableMeta): boolean {
  if (meta.lazyTables !== true) {
    throw new TypeError(
      `better-supabase: cannot register table "${table.key}": the schema lists its tables. Use client.db.${table.key}.`,
    );
  }

  const tables: Record<string, TableMeta> = meta.tables;

  if (Object.hasOwn(tables, table.key)) {
    return false;
  }

  tables[table.key] = table;

  return true;
}

/**
 * Fills `functions` from `loadFunctions`. The object is the copy `defineSchema`
 * made.
 */
export function installFunctions(
  meta: SchemaMeta,
  functions: SchemaMeta["functions"],
): void {
  const target: Record<string, SchemaMeta["functions"][string]> =
    meta.functions;

  for (const [name, fn] of Object.entries(functions)) {
    target[name] = fn;
  }
}
