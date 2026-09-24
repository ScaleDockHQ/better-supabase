import type {
  GeneratorMetadata,
  PostgresColumn,
  PostgresFunction,
} from './typegen.ts';
import type {
  Catalog,
  CatalogColumn,
  CatalogEnum,
  CatalogForeignKey,
  CatalogFunction,
  CatalogTable,
  ExtrasTable,
  Snapshot,
} from './types.ts';

const byName = (a: { schema: string; name: string }, b: typeof a): number =>
  a.schema === b.schema
    ? a.name < b.name
      ? -1
      : a.name > b.name
        ? 1
        : 0
    : a.schema < b.schema
      ? -1
      : 1;

function toColumn(column: PostgresColumn): CatalogColumn {
  const isArray = column.data_type === 'ARRAY';
  const udt = isArray ? column.format.replace(/^_/, '') : column.format;
  const defaultValue =
    column.default_value === null || column.default_value === undefined
      ? null
      : String(column.default_value);
  return {
    name: column.name,
    udt,
    format: column.format,
    typeSchema: column.type_schema,
    isArray,
    isEnum: column.enums.length > 0,
    nullable: column.is_nullable,
    hasDefault:
      defaultValue !== null ||
      column.identity_generation !== null ||
      column.is_generated,
    default: defaultValue,
    identity:
      column.identity_generation === 'ALWAYS'
        ? 'always'
        : column.identity_generation === 'BY DEFAULT'
          ? 'by default'
          : null,
    generated: column.is_generated,
    updatable: column.is_updatable,
    comment: column.comment,
  };
}

function toFunction(
  fn: PostgresFunction,
  typeName: (id: number) => string | undefined,
  relationName: (id: number | null) => string | null,
): CatalogFunction {
  const args: CatalogFunction['args'][number][] = [];
  const table: { name: string; udt: string }[] = [];
  fn.args.forEach((arg, index) => {
    const raw = typeName(arg.type_id) ?? 'unknown';
    const name = arg.name || `arg${index + 1}`;
    if (arg.mode === 'in' || arg.mode === 'inout' || arg.mode === 'variadic') {
      const isArray = raw.startsWith('_');
      args.push({
        name,
        udt: isArray ? raw.slice(1) : raw,
        isArray,
        hasDefault: arg.has_default === true,
      });
    }
    if (arg.mode === 'table' || arg.mode === 'out' || arg.mode === 'inout')
      table.push({ name, udt: raw });
  });
  const searchPath = fn.config_params?.['search_path'];
  return {
    schema: fn.schema,
    name: fn.name,
    signature: fn.identity_argument_types,
    args,
    returnsTable: fn.args.some((arg) => arg.mode === 'table') ? table : null,
    returns: typeName(fn.return_type_id) ?? fn.return_type,
    returnsRelation: relationName(fn.return_type_relation_id),
    returnsSet: fn.is_set_returning_function,
    volatility: fn.behavior.toLowerCase() as CatalogFunction['volatility'],
    securityDefiner: fn.security_definer,
    language: fn.language,
    searchPath:
      searchPath === undefined ? null : searchPath.replace(/^""$/, ''),
  };
}

/** Joins the typegen metadata and the extras into one record per object. */
export function toCatalog(snapshot: Snapshot): Catalog {
  const meta: GeneratorMetadata = snapshot.generator;
  const extras = new Map<number, ExtrasTable>(
    snapshot.extras.tables.map((table) => [table.id, table]),
  );
  const columns = new Map<number, PostgresColumn[]>();
  for (const column of meta.columns) {
    const list = columns.get(column.table_id);
    if (list) list.push(column);
    else columns.set(column.table_id, [column]);
  }
  const primaryKeys = new Map<number, string[]>();
  for (const key of meta.primaryKeys) {
    const list = primaryKeys.get(key.table_id);
    if (list) list.push(key.name);
    else primaryKeys.set(key.table_id, [key.name]);
  }
  const relationNames = new Map<number, string>();
  for (const list of [
    meta.tables,
    meta.foreignTables,
    meta.views,
    meta.materializedViews,
  ]) {
    for (const entry of list)
      relationNames.set(entry.id, `${entry.schema}.${entry.name}`);
  }

  const foreignKeysOf = (
    schema: string,
    name: string,
    extra: ExtrasTable | undefined,
  ): CatalogForeignKey[] => {
    const actions = new Map(
      (extra?.foreignKeys ?? []).map((fk) => [fk.name, fk]),
    );
    return meta.relationships
      .filter(
        (rel) =>
          rel.schema === schema &&
          rel.relation === name &&
          actions.has(rel.foreign_key_name),
      )
      .map((rel) => {
        const action = actions.get(rel.foreign_key_name);
        return {
          name: rel.foreign_key_name,
          columns: rel.columns,
          refSchema: rel.referenced_schema,
          refTable: rel.referenced_relation,
          refColumns: rel.referenced_columns,
          oneToOne: rel.is_one_to_one,
          onDelete: action?.onDelete ?? 'no action',
          onUpdate: action?.onUpdate ?? 'no action',
        };
      })
      .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  };

  const build = (
    entry: { id: number; schema: string; name: string; comment: string | null },
    shape: Pick<
      CatalogTable,
      | 'kind'
      | 'rls'
      | 'forceRls'
      | 'replicaIdentity'
      | 'insertable'
      | 'updatable'
    >,
  ): CatalogTable => {
    const extra = extras.get(entry.id);
    const own = [...(columns.get(entry.id) ?? [])].sort(
      (a, b) => a.ordinal_position - b.ordinal_position,
    );
    return {
      id: entry.id,
      schema: entry.schema,
      name: entry.name,
      comment: entry.comment,
      ...shape,
      columns: own.map(toColumn),
      primaryKey:
        extra && extra.primaryKey.length > 0
          ? extra.primaryKey
          : (primaryKeys.get(entry.id) ?? []),
      uniques: extra?.uniques ?? [],
      foreignKeys: foreignKeysOf(entry.schema, entry.name, extra),
      checks: extra?.checks ?? [],
      indexes: extra?.indexes ?? [],
      policies: extra?.policies ?? [],
      triggers: extra?.triggers ?? [],
      grants: extra?.grants ?? [],
    };
  };

  const tables: CatalogTable[] = [
    ...meta.tables.map((table) =>
      build(table, {
        kind: 'table',
        rls: table.rls_enabled,
        forceRls: table.rls_forced,
        replicaIdentity: table.replica_identity,
        insertable: true,
        updatable: true,
      }),
    ),
    ...meta.foreignTables.map((table) =>
      build(table, {
        kind: 'table',
        rls: false,
        forceRls: false,
        replicaIdentity: null,
        insertable: true,
        updatable: true,
      }),
    ),
    ...meta.views.map((view) =>
      build(view, {
        kind: 'view',
        rls: false,
        forceRls: false,
        replicaIdentity: null,
        insertable: view.is_insert_enabled ?? view.is_updatable,
        updatable: view.is_update_enabled ?? view.is_updatable,
      }),
    ),
    ...meta.materializedViews.map((view) =>
      build(view, {
        kind: 'view',
        rls: false,
        forceRls: false,
        replicaIdentity: null,
        insertable: false,
        updatable: false,
      }),
    ),
  ].sort(byName);

  const included = new Set(snapshot.schemas);
  const enums: CatalogEnum[] = meta.types
    .filter((type) => type.enums.length > 0 && included.has(type.schema))
    .map((type) => ({
      schema: type.schema,
      name: type.name,
      values: type.enums,
    }))
    .sort(byName);

  const typeNames = new Map(meta.types.map((type) => [type.id, type.name]));
  const functions = meta.functions
    .map((fn) =>
      toFunction(
        fn,
        (id) => typeNames.get(id),
        (id) => (id === null ? null : (relationNames.get(id) ?? null)),
      ),
    )
    .sort(
      (a, b) =>
        byName(a, b) ||
        (a.signature < b.signature ? -1 : a.signature > b.signature ? 1 : 0),
    );

  return {
    schemas: snapshot.schemas,
    tables,
    enums,
    functions,
    buckets: snapshot.extras.buckets,
    realtime: snapshot.extras.realtime,
  };
}
