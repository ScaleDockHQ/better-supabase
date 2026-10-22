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

function validateMeta(meta: SchemaMeta): SchemaMeta {
  // oxlint-disable-next-line typescript/no-unnecessary-condition -- generated files from another release can carry another version.
  if (meta.version !== 1) {
    throw new TypeError(
      `better-supabase: unsupported schema metadata version ${String(meta.version)}. Run \`better-supabase gen\` again.`,
    );
  }

  return meta;
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
