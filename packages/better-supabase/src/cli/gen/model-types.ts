import type { AppColumnType, ResolvedConfig } from "../../config/index.ts";
import type {
  Casing,
  Codec,
  FunctionMeta,
  RelationMeta,
  TableMeta,
} from "../../index.ts";
import type { GeneratorMetadata } from "../introspect/typegen.ts";
import type {
  Catalog,
  CatalogColumn,
  CatalogTable,
} from "../introspect/types.ts";

import { toCamel } from "../../index.ts";

export interface ColumnModel {
  readonly app: string;
  readonly db: string;
  readonly snapshot: CatalogColumn;
  /** TypeScript type without `| null`. */
  readonly tsType: string;
  readonly nullable: boolean;
  /** Optional on insert. */
  readonly optional: boolean;
  /**
   * An insert may leave it out: a default, `insertOptional`, or a
   * CHECK-narrowed column a `before insert` trigger can fill.
   */
  readonly filled: boolean;
  /** Not writable (generated always / identity always). */
  readonly readonly: boolean;
  readonly values: readonly string[] | undefined;
  readonly json: boolean;
  readonly codec: Codec | undefined;
  /** Bucket id from `config.storagePaths`. */
  readonly storage: string | undefined;
  readonly insertable: boolean;
  readonly updatable: boolean;
  /** `false` for an app table column with `access: "server"`. */
  readonly selectable?: false;
}

export interface RelationModel {
  readonly name: string;
  /** The name before casing, from database names. */
  readonly base: string;
  /** Database names of the foreign key's columns and the ones it references. */
  readonly fkColumns: readonly string[];
  readonly refColumns: readonly string[];
  readonly meta: RelationMeta;
}

export interface TableModel {
  readonly key: string;
  readonly snapshot: CatalogTable;
  readonly casing: Casing;
  readonly columns: readonly ColumnModel[];
  readonly relations: readonly RelationModel[];
  readonly meta: TableMeta;
}

export interface EnumModel {
  readonly schema: string;
  readonly name: string;
  /**
   * Key in `meta.enums`: the name, or `schema_name` when another schema has the
   * same enum name.
   */
  readonly key: string;
  /** Constant name for the value array, e.g. `noteKindValues`. */
  readonly constant: string;
  /** Exported type name, e.g. `NoteKind`. */
  readonly typeName: string;
  readonly values: readonly string[];
}

export interface FunctionModel {
  readonly key: string;
  readonly meta: FunctionMeta;
  readonly args: readonly {
    name: string;
    tsType: string;
    optional: boolean;
    values: readonly string[] | undefined;
  }[];
  readonly returns: string;
}

export interface JsonImport {
  readonly name: string;
  /** Path relative to the project root, without the `#Name` part. */
  readonly from: string;
}

export type TableOptions = ResolvedConfig["tables"][string];

/**
 * What every step of `buildModel` reads: the catalog, the lookups and the
 * warnings so far.
 */
export interface ModelContext {
  readonly config: ResolvedConfig;
  readonly catalog: Catalog;
  readonly introspection: GeneratorMetadata;
  readonly enumsByName: ReadonlyMap<string, readonly string[]>;
  readonly jsonImports: Map<string, JsonImport>;
  /** `config.json` keys no column has used yet; `draftTables` removes them. */
  readonly unusedJson: Set<string>;
  readonly included: readonly CatalogTable[];
  readonly keyOf: ReadonlyMap<string, string>;
  readonly warnings: string[];
  /** Informational lines, printed as they are, unlike the warnings. */
  readonly notices: string[];
  readonly tsType: (
    schema: string,
    format: string,
    typeSchema?: string,
  ) => string;
  readonly jsonTypeFor: (
    schema: string,
    table: string,
    column: string,
  ) => string | undefined;
  readonly optionsOf: (table: CatalogTable) => TableOptions | undefined;
}

export interface DraftTable {
  readonly table: CatalogTable;
  readonly casing: Casing;
  readonly columns: readonly ColumnModel[];
  readonly byDb: ReadonlyMap<string, ColumnModel>;
}

export const applyCasing = (name: string, casing: Casing): string =>
  casing === "camel" ? toCamel(name) : name;

/** The Postgres type name of each app column type, as introspection reports it. */
export const APP_COLUMN_UDT: Readonly<Record<AppColumnType, string>> = {
  text: "text",
  integer: "int4",
  bigint: "int8",
  numeric: "numeric",
  boolean: "bool",
  uuid: "uuid",
  timestamptz: "timestamptz",
  date: "date",
  jsonb: "jsonb",
  "text[]": "_text",
};

export const CODEC_TYPE: Record<Codec, string> = {
  instant: "Temporal.Instant",
  plainDateTime: "Temporal.PlainDateTime",
  bigint: "bigint",
  string: "string",
  utcString: "string",
};

export function codecFor(
  udt: string,
  config: ResolvedConfig,
): Codec | undefined {
  const { codecs } = config;

  if (codecs.timestamptz === "utc" && udt === "timestamptz") {
    return "utcString";
  }

  if (codecs.timestamptz === "instant") {
    if (udt === "timestamptz") {
      return "instant";
    }

    if (udt === "timestamp") {
      return "plainDateTime";
    }
  }

  if (udt === "int8" && codecs.int8 !== "number") {
    return codecs.int8;
  }

  if (udt === "numeric" && codecs.numeric === "string") {
    return "string";
  }

  return undefined;
}

export function enumType(values: readonly string[]): string {
  return values.map((value) => JSON.stringify(value)).join(" | ");
}
