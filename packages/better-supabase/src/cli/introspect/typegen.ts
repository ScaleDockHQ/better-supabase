/**
 * The only module that imports `@supabase/postgrest-typegen`. It is alpha and
 * pinned to an exact version, so every use goes through here.
 */
import {
  type GeneratorMetadata,
  generatorMetadataJsonSchema,
  introspect,
  parseGeneratorMetadata,
  type Queryable,
  serializeGeneratorMetadata,
  sortGeneratorMetadata,
} from "@supabase/postgrest-typegen";
import {
  generateTypescript,
  pgTypeToTsType,
} from "@supabase/postgrest-typegen/generation";

export type {
  GeneratorMetadata,
  PostgresColumn,
  PostgresFunction,
  Queryable,
} from "@supabase/postgrest-typegen";

/** Introspects `schemas`, keeping only the types they reference. */
export async function readGeneratorMetadata(
  db: Queryable,
  schemas: readonly string[],
): Promise<GeneratorMetadata> {
  const metadata = await introspect(db, { includedSchemas: [...schemas] });
  return pruneTypes(metadata, schemas);
}

/** Postgres assigns oids below this to built-in objects; those are stable. */
const FIRST_NORMAL_OID = 16384;

/**
 * Replaces the oids of user objects with ids derived from their names and
 * zeroes size estimates, so a snapshot of the same schema is byte-identical
 * after `supabase db reset` or on another machine. Returns the id mapping
 * for data keyed by the old oids.
 */
export function stabilizeMetadata(metadata: GeneratorMetadata): {
  metadata: GeneratorMetadata;
  ids: ReadonlyMap<number, number>;
} {
  const ids = new Map<number, number>();
  const assign = (
    base: number,
    entries: readonly { id: number; key: string }[],
  ): void => {
    [...entries]
      .sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0))
      .forEach((entry, index) => {
        if (entry.id >= FIRST_NORMAL_OID) ids.set(entry.id, base + index);
      });
  };
  assign(
    1_000_000,
    [
      ...metadata.tables,
      ...metadata.foreignTables,
      ...metadata.views,
      ...metadata.materializedViews,
    ].map((entry) => ({ id: entry.id, key: `${entry.schema}.${entry.name}` })),
  );
  assign(
    2_000_000,
    metadata.types.map((entry) => ({
      id: entry.id,
      key: `${entry.schema}.${entry.name}`,
    })),
  );
  assign(
    3_000_000,
    metadata.functions.map((entry) => ({
      id: entry.id,
      key: `${entry.schema}.${entry.name}(${entry.identity_argument_types})`,
    })),
  );
  assign(
    4_000_000,
    metadata.schemas.map((entry) => ({ id: entry.id, key: entry.name })),
  );
  const map = (id: number): number => ids.get(id) ?? id;
  const mapNullable = (id: number | null): number | null =>
    id === null ? null : map(id);

  const stable: GeneratorMetadata = {
    ...metadata,
    schemas: metadata.schemas.map((entry) => ({ ...entry, id: map(entry.id) })),
    tables: metadata.tables.map((entry) => ({
      ...entry,
      id: map(entry.id),
      bytes: 0,
      size: "0 bytes",
      live_rows_estimate: 0,
      dead_rows_estimate: 0,
    })),
    foreignTables: metadata.foreignTables.map((entry) => ({
      ...entry,
      id: map(entry.id),
    })),
    views: metadata.views.map((entry) => ({ ...entry, id: map(entry.id) })),
    materializedViews: metadata.materializedViews.map((entry) => ({
      ...entry,
      id: map(entry.id),
    })),
    columns: metadata.columns.map((entry) => ({
      ...entry,
      table_id: map(entry.table_id),
      id: `${map(entry.table_id)}.${entry.ordinal_position}`,
    })),
    primaryKeys: metadata.primaryKeys.map((entry) => ({
      ...entry,
      table_id: map(entry.table_id),
    })),
    functions: metadata.functions.map((entry) => ({
      ...entry,
      id: map(entry.id),
      return_type_id: map(entry.return_type_id),
      return_type_relation_id: mapNullable(entry.return_type_relation_id),
      args: entry.args.map((arg) => ({ ...arg, type_id: map(arg.type_id) })),
    })),
    types: metadata.types.map((entry) => ({
      ...entry,
      id: map(entry.id),
      type_relation_id: mapNullable(entry.type_relation_id),
      attributes: entry.attributes.map((attribute) => ({
        ...attribute,
        type_id: map(attribute.type_id),
      })),
    })),
  };
  return { metadata: sortGeneratorMetadata(stable), ids };
}

/** Validates metadata loaded from a snapshot file. */
export function validateGeneratorMetadata(data: unknown): GeneratorMetadata {
  return parseGeneratorMetadata(data);
}

/** JSON Schema of the metadata contract, embedded in `snapshot-v2.json`. */
export function generatorJsonSchema(): Record<string, unknown> {
  // SAFETY: the generator metadata schema is a JSON Schema object with an
  // optional $schema dialect.
  const { $schema: _dialect, ...schema } = generatorMetadataJsonSchema as {
    $schema?: string;
  } & Record<string, unknown>;
  return schema;
}

/** The JSON document out-of-process generators read. */
export function serializeGenerator(metadata: GeneratorMetadata): string {
  return serializeGeneratorMetadata(sortGeneratorMetadata(metadata));
}

/**
 * Keeps only what belongs to `schemas`, so the Database type matches
 * `supabase gen types --schema ...` for exactly those schemas.
 */
export function restrictSchemas(
  metadata: GeneratorMetadata,
  schemas: readonly string[],
): GeneratorMetadata {
  const keep = new Set(schemas);
  return {
    ...metadata,
    schemas: metadata.schemas.filter((schema) => keep.has(schema.name)),
    tables: metadata.tables.filter((table) => keep.has(table.schema)),
    foreignTables: metadata.foreignTables.filter((table) =>
      keep.has(table.schema),
    ),
    views: metadata.views.filter((view) => keep.has(view.schema)),
    materializedViews: metadata.materializedViews.filter((view) =>
      keep.has(view.schema),
    ),
    columns: metadata.columns.filter((column) => keep.has(column.schema)),
    primaryKeys: metadata.primaryKeys.filter((key) => keep.has(key.schema)),
    relationships: metadata.relationships.filter((relationship) =>
      keep.has(relationship.schema),
    ),
    functions: metadata.functions.filter((fn) => keep.has(fn.schema)),
  };
}

export interface DatabaseTypesOptions {
  readonly schemas: readonly string[];
  readonly postgrestVersion: string;
}

/** Renders `database.types.ts`, byte for byte what `supabase gen types` prints. */
export function generateDatabaseTypes(
  metadata: GeneratorMetadata,
  options: DatabaseTypesOptions,
): Promise<string> {
  return generateTypescript(
    sortGeneratorMetadata(restrictSchemas(metadata, options.schemas)),
    {
      postgrestVersion: options.postgrestVersion,
      detectOneToOneRelationships: true,
    },
  );
}

/**
 * TypeScript type for a column or argument, resolved exactly like the
 * `Database` type does (domains, composites, enums in other schemas).
 */
export function tsTypeOf(
  metadata: GeneratorMetadata,
  schema: string,
  format: string,
  typeSchema?: string,
): string {
  const owner = metadata.schemas.find((entry) => entry.name === schema) ?? {
    id: 0,
    name: schema,
    owner: "",
  };
  return pgTypeToTsType(
    owner,
    format,
    {
      types: metadata.types,
      schemas: metadata.schemas,
      tables: metadata.tables,
      views: metadata.views,
      foreignTables: metadata.foreignTables,
      materializedViews: metadata.materializedViews,
    },
    typeSchema,
  );
}

/**
 * `introspect()` returns every type in the database (hundreds of built-ins).
 * Keep the ones in the read schemas and those referenced by columns,
 * functions and composite attributes; built-in scalars resolve by name.
 */
function pruneTypes(
  metadata: GeneratorMetadata,
  schemas: readonly string[],
): GeneratorMetadata {
  const byId = new Map(metadata.types.map((type) => [type.id, type]));
  const byName = new Map(
    metadata.types.map((type) => [`${type.schema}.${type.name}`, type]),
  );
  const keep = new Set<number>();
  const visit = (id: number | null | undefined): void => {
    if (id === null || id === undefined || keep.has(id)) return;
    const type = byId.get(id);
    if (!type) return;
    keep.add(id);
    for (const attribute of type.attributes) visit(attribute.type_id);
  };
  for (const type of metadata.types)
    if (schemas.includes(type.schema)) visit(type.id);
  for (const column of metadata.columns) {
    visit(byName.get(`${column.type_schema}.${column.format}`)?.id);
    visit(
      byName.get(`${column.type_schema}.${column.format.replace(/^_/, "")}`)
        ?.id,
    );
  }
  for (const fn of metadata.functions) {
    visit(fn.return_type_id);
    for (const arg of fn.args) visit(arg.type_id);
  }
  return {
    ...metadata,
    types: metadata.types.filter((type) => keep.has(type.id)),
  };
}
