import type {
  AnyFunctions,
  AnyModels,
  RelationMeta,
  Schema,
  SchemaMeta,
  TableMeta,
} from './types.ts';

/**
 * Binds generated model types to runtime metadata. Called from the generated
 * module; apps import the returned `schema`, never call this themselves.
 */
export function defineSchema<
  M extends AnyModels,
  D = unknown,
  F extends AnyFunctions = AnyFunctions,
>(meta: SchemaMeta): Schema<M, D, F> {
  return { meta: validateMeta(meta) };
}

function validateMeta(meta: SchemaMeta): SchemaMeta {
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

/** Database column name for an app column name. */
export function dbColumn(table: TableMeta, column: string): string {
  const found = table.columns[column];
  if (!found) {
    throw new TypeError(
      `better-supabase: unknown column "${column}" on "${table.key}"`,
    );
  }
  return found.db;
}

/** App column name for a database column name, if the table has it. */
export function appColumn(table: TableMeta, db: string): string | undefined {
  for (const [app, column] of Object.entries(table.columns)) {
    if (column.db === db) return app;
  }
  return undefined;
}
