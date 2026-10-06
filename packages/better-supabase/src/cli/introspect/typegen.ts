/**
 * The only module that imports `@supabase/postgrest-typegen`. It is alpha and
 * pinned to an exact version, so every use goes through here. It is an
 * optional peer: without it, the functions here throw an install message.
 */
import type * as Generation from "@supabase/postgrest-typegen/generation";
import type * as Oxfmt from "oxfmt";

import type { GeneratorMetadata } from "../../config/index.ts";

import { byCodePoint } from "../compare.ts";
import { TYPEGEN_VERSION } from "./typegen-version.ts";

const TYPEGEN = "@supabase/postgrest-typegen";

/** Why a command that reads or generates schema types stops without the peer. */
export const TYPEGEN_MISSING: string = `better-supabase needs the "${TYPEGEN}" package to read your schema and generate types. Install it: pnpm add -D ${TYPEGEN}@${TYPEGEN_VERSION}`;

/** Thrown by every function here when the optional peer is not installed. */
export class TypegenMissingError extends Error {
  constructor() {
    super(TYPEGEN_MISSING);
    this.name = "TypegenMissingError";
  }
}

const missing = (): never => {
  throw new TypegenMissingError();
};

/**
 * `/generation` is light and its functions are synchronous (`buildModel`
 * calls `tsTypeOf`), so it loads with this module, which the commands that
 * need it import on demand. The package root and `/introspection` build
 * their arktype schemas on import (about 90 ms), so they load when a command
 * reads or validates metadata, not for `--help`.
 */
const generation: typeof Generation | undefined =
  await import("@supabase/postgrest-typegen/generation").catch(() => undefined);
const loadGeneration = (): typeof Generation => generation ?? missing();
const metadataModule = () =>
  import("@supabase/postgrest-typegen").catch(missing);
const introspectionModule = () =>
  import("@supabase/postgrest-typegen/introspection").catch(missing);

export type {
  GeneratorMetadata,
  PostgresColumn,
  PostgresFunction,
} from "../../config/index.ts";

/** A connection `introspect()` reads the catalog through, as postgrest-typegen types it. */
export interface Queryable {
  // oxlint-disable-next-line typescript/no-explicit-any -- matches postgrest-typegen's own signature.
  query(sql: string): Promise<{ rows: any[] }>;
}

/** Introspects `schemas`, keeping only the types they reference. */
export async function readGeneratorMetadata(
  db: Queryable,
  schemas: readonly string[],
): Promise<GeneratorMetadata> {
  const { introspect } = await introspectionModule();
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
      .sort((a, b) => byCodePoint(a.key, b.key))
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
  return { metadata: loadGeneration().sortGeneratorMetadata(stable), ids };
}

/** Validates metadata loaded from a snapshot file. */
export async function validateGeneratorMetadata(
  data: unknown,
): Promise<GeneratorMetadata> {
  const { parseGeneratorMetadata } = await metadataModule();
  return parseGeneratorMetadata(data);
}

/**
 * A `GeneratorMetadata` document `gen --metadata` refuses: not JSON, another
 * `GENERATOR_METADATA_VERSION`, or a shape the schema rejects. `gen` exits 65
 * for it, the code `@supabase/typegen` maps to `MetadataRejectedError`.
 */
export class MetadataRejectedError extends Error {
  /** The document's `version`, when it had one. */
  readonly version: unknown;

  constructor(message: string, version?: unknown) {
    super(message);
    this.name = "MetadataRejectedError";
    this.version = version;
  }
}

/**
 * Parses the JSON document an out-of-process generator reads on stdin,
 * checking its `version` against the `GENERATOR_METADATA_VERSION` this
 * release of `@supabase/postgrest-typegen` writes.
 */
export async function parseMetadataDocument(
  text: string,
): Promise<GeneratorMetadata> {
  const { GENERATOR_METADATA_VERSION, parseGeneratorMetadata } =
    await metadataModule();
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch (cause) {
    throw new MetadataRejectedError(
      text.trim() === ""
        ? "The GeneratorMetadata document is empty."
        : `The GeneratorMetadata document is not JSON: ${cause instanceof Error ? cause.message : String(cause)}`,
    );
  }
  const version =
    typeof data === "object" && data !== null && "version" in data
      ? data.version
      : undefined;
  if (version !== GENERATOR_METADATA_VERSION) {
    throw new MetadataRejectedError(
      version === undefined
        ? `The document has no "version", so it is not GeneratorMetadata. better-supabase reads version ${GENERATOR_METADATA_VERSION}.`
        : `The document is GeneratorMetadata version ${JSON.stringify(version)}, and better-supabase reads version ${GENERATOR_METADATA_VERSION} (${TYPEGEN}@${TYPEGEN_VERSION}). Update better-supabase or the tool that wrote the document so both agree.`,
      version,
    );
  }
  try {
    return parseGeneratorMetadata(data);
  } catch (cause) {
    throw new MetadataRejectedError(
      cause instanceof Error ? cause.message : String(cause),
      version,
    );
  }
}

/** JSON Schema of the metadata contract, embedded in `snapshot-v2.json`. */
export async function generatorJsonSchema(): Promise<Record<string, unknown>> {
  const { generatorMetadataJsonSchema } = await metadataModule();
  // SAFETY: the generator metadata schema is a JSON Schema object with an
  // optional $schema dialect.
  const { $schema: _dialect, ...schema } = generatorMetadataJsonSchema as {
    $schema?: string;
  } & Record<string, unknown>;
  return schema;
}

/** The JSON document out-of-process generators read. */
export async function serializeGenerator(
  metadata: GeneratorMetadata,
): Promise<string> {
  const { serializeGeneratorMetadata } = await metadataModule();
  return serializeGeneratorMetadata(
    loadGeneration().sortGeneratorMetadata(metadata),
  );
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

let oxfmt: Promise<typeof Oxfmt | undefined> | undefined;

/** oxfmt is an optional peer, loaded on demand; `undefined` when it is not installed. */
function loadOxfmt(): Promise<typeof Oxfmt | undefined> {
  oxfmt ??= import("oxfmt").catch(() => undefined);
  return oxfmt;
}

/** Whether `database.types.ts` comes out formatted. */
export async function oxfmtInstalled(): Promise<boolean> {
  return (await loadOxfmt()) !== undefined;
}

/** Formats like `supabase gen types`, or returns `code` as it is without oxfmt. */
async function formatTypes(code: string): Promise<string> {
  const formatter = await loadOxfmt();
  if (!formatter) return code;
  const { code: formatted, errors } = await formatter.format(
    "output.ts",
    code,
    {
      semi: false,
      printWidth: 80,
    },
  );
  if (errors.length > 0) {
    throw new Error(
      `oxfmt failed to format database.types.ts: ${errors.map((error) => error.message).join("; ")}`,
    );
  }
  return formatted;
}

/**
 * Renders `database.types.ts` as `supabase gen types` prints it when oxfmt is
 * installed, plus the `ComputedFields` keys Supabase CLI 2.119 doesn't write.
 */
export function generateDatabaseTypes(
  metadata: GeneratorMetadata,
  options: DatabaseTypesOptions,
): Promise<string> {
  const { generateTypescript, sortGeneratorMetadata } = loadGeneration();
  return generateTypescript(
    sortGeneratorMetadata(restrictSchemas(metadata, options.schemas)),
    {
      postgrestVersion: options.postgrestVersion,
      detectOneToOneRelationships: true,
      format: formatTypes,
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
  return loadGeneration().pgTypeToTsType(
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
