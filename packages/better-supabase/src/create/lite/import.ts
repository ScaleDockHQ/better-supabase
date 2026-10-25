import type { AppOnDeleteAction } from "../../config/index.ts";
import type { LiteRuntime } from "../../lite/runtime.ts";
import type { AppColumn, AppTable, Design } from "../design.ts";
import type { Issue } from "../issue.ts";
import type { PresetMigrationFile } from "../types.ts";

import { appDefaultError } from "../../config/app-defaults.ts";
import { LITE_INSTALL, loadLite } from "../../lite/runtime.ts";
import { SUPABASE_PRELUDE } from "./prelude.ts";

/** Anything that runs a read-only query and returns rows: PGlite, `pg`, a shim. */
export interface ImportQueryable {
  query(sql: string): Promise<{ readonly rows: readonly unknown[] }>;
}

/**
 * Where a project is read from (ADR 0100).
 *
 * - `files`: a declarative schema folder or a migrations folder, as path and
 *   contents. They are applied in path order to a throwaway PGlite database.
 * - `queryable`: a database you can query, such as a `pg` pool or a PGlite
 *   instance.
 * - `supabase`: a project ref and an access token, read through the Management
 *   API's read-only query endpoint.
 */
export type ImportSource =
  | { readonly kind: "files"; readonly files: readonly ImportFile[] }
  | { readonly kind: "queryable"; readonly queryable: ImportQueryable }
  | {
      readonly kind: "supabase";
      readonly projectRef: string;
      readonly accessToken: string;
      readonly fetch?: typeof fetch;
      readonly apiUrl?: string;
    };

export interface ImportFile {
  readonly path: string;
  readonly contents: string;
}

export interface ImportProjectOptions {
  readonly source: ImportSource;
  /** The schemas to read. Defaults to `public`. */
  readonly schemas?: readonly string[];
  /** A loaded `@supabase/lite`, for `files` sources. Loaded on demand. */
  readonly runtime?: LiteRuntime;
}

/** How far a table is along the adoption ladder (ADR 0102). */
export type AdoptionRung = "open" | "locked" | "protected";

export interface ImportedTable {
  readonly schema: string;
  readonly name: string;
  readonly rung: AdoptionRung;
  /** `false` when the table is kept as it is, outside the design. */
  readonly modeled: boolean;
  readonly columns: number;
}

/** An object the import keeps verbatim and never drops. */
export interface PreservedObject {
  readonly kind:
    | "table"
    | "view"
    | "column"
    | "foreign_key"
    | "index"
    | "default"
    | "function"
    | "trigger"
    | "policy";
  readonly name: string;
  readonly reason: string;
}

export interface ImportReport {
  readonly counts: {
    readonly tables: number;
    readonly modeledTables: number;
    readonly columns: number;
    readonly views: number;
    readonly functions: number;
    readonly triggers: number;
    readonly policies: number;
  };
  readonly tables: readonly ImportedTable[];
  /** Tables created by a block (`bsb_` names), which a design never models. */
  readonly blockOwned: readonly string[];
  readonly preserved: readonly PreservedObject[];
  /** SQL errors from `files` and the security findings (`source: "verifier"`). */
  readonly issues: readonly Issue[];
}

export interface ImportResult {
  readonly design: Design;
  readonly report: ImportReport;
}

interface RawColumn {
  readonly name: string;
  readonly type: string;
  readonly nullable: boolean;
  readonly default: string | null;
  readonly identity: string | null;
  readonly generated: boolean;
  readonly comment: string | null;
}

interface RawConstraint {
  readonly type: "p" | "u" | "f";
  readonly columns: readonly string[];
  readonly refSchema: string | null;
  readonly refTable: string | null;
  readonly refColumns: readonly string[] | null;
  readonly onDelete: string | null;
}

interface RawIndex {
  readonly columns: readonly string[];
  readonly plain: boolean;
}

interface RawTable {
  readonly schema: string;
  readonly name: string;
  readonly kind: string;
  readonly rls: boolean;
  readonly comment: string | null;
  readonly columns: readonly RawColumn[];
  readonly constraints: readonly RawConstraint[];
  readonly indexes: readonly RawIndex[];
  readonly policies: number;
  readonly triggers: number;
}

interface RawCatalog {
  readonly tables: readonly RawTable[];
  readonly functions: readonly string[];
}

const BLOCK_PREFIX = "bsb_";

function schemaList(schemas: readonly string[]): string {
  return schemas.map((name) => `'${name.replaceAll("'", "''")}'`).join(", ");
}

/**
 * One query that returns the whole catalog as JSON, so it runs through the
 * Management API's read-only endpoint in a single call.
 */
export function catalogQuery(schemas: readonly string[] = ["public"]): string {
  const list = schemaList(schemas);

  return `select json_build_object(
  'tables', (
    select coalesce(json_agg(t order by t.schema, t.name), '[]'::json) from (
      select n.nspname as schema, c.relname as name, c.relkind::text as kind,
        c.relrowsecurity as rls,
        obj_description(c.oid, 'pg_class') as comment,
        (select coalesce(json_agg(json_build_object(
            'name', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull,
            'default', pg_get_expr(d.adbin, d.adrelid),
            'identity', nullif(a.attidentity::text, ''),
            'generated', a.attgenerated::text <> '',
            'comment', col_description(c.oid, a.attnum)
          ) order by a.attnum), '[]'::json)
          from pg_attribute a
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as columns,
        (select coalesce(json_agg(json_build_object(
            'type', k.contype::text,
            'columns', (select json_agg(a.attname order by u.ord)
              from unnest(k.conkey) with ordinality as u(attnum, ord)
              join pg_attribute a on a.attrelid = k.conrelid and a.attnum = u.attnum),
            'refSchema', fn.nspname,
            'refTable', fc.relname,
            'refColumns', (select json_agg(a.attname order by u.ord)
              from unnest(k.confkey) with ordinality as u(attnum, ord)
              join pg_attribute a on a.attrelid = k.confrelid and a.attnum = u.attnum),
            'onDelete', k.confdeltype::text
          )), '[]'::json)
          from pg_constraint k
          left join pg_class fc on fc.oid = k.confrelid
          left join pg_namespace fn on fn.oid = fc.relnamespace
          where k.conrelid = c.oid and k.contype in ('p', 'u', 'f')) as constraints,
        (select coalesce(json_agg(json_build_object(
            'columns', (select json_agg(a.attname order by u.ord)
              from unnest(i.indkey::int2[]) with ordinality as u(attnum, ord)
              join pg_attribute a on a.attrelid = i.indrelid and a.attnum = u.attnum),
            'plain', (not i.indisunique and not i.indisprimary
              and i.indpred is null and i.indexprs is null
              and am.amname = 'btree')
          )), '[]'::json)
          from pg_index i
          join pg_class ic on ic.oid = i.indexrelid
          join pg_am am on am.oid = ic.relam
          where i.indrelid = c.oid and not i.indisprimary and not i.indisunique) as indexes,
        (select count(*)::int from pg_policy p where p.polrelid = c.oid) as policies,
        (select count(*)::int from pg_trigger g
          where g.tgrelid = c.oid and not g.tgisinternal) as triggers
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in (${list}) and c.relkind in ('r', 'p', 'v', 'm')
    ) t
  ),
  'functions', (
    select coalesce(json_agg(n.nspname || '.' || p.proname order by n.nspname, p.proname), '[]'::json)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in (${list}) and p.prokind in ('f', 'p')
  )
) as catalog`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function str(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function strings(value: unknown): readonly string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function records(value: unknown): readonly Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter((item) => isRecord(item)) : [];
}

function readColumn(row: Record<string, unknown>): RawColumn {
  return {
    name: str(row["name"]) ?? "",
    type: str(row["type"]) ?? "",
    nullable: row["nullable"] !== false,
    default: str(row["default"]),
    identity: str(row["identity"]),
    generated: row["generated"] === true,
    comment: str(row["comment"]),
  };
}

function readConstraint(row: Record<string, unknown>): RawConstraint {
  const type = str(row["type"]);

  return {
    type: type === "p" || type === "u" ? type : "f",
    columns: strings(row["columns"]),
    refSchema: str(row["refSchema"]),
    refTable: str(row["refTable"]),
    refColumns: Array.isArray(row["refColumns"])
      ? strings(row["refColumns"])
      : null,
    onDelete: str(row["onDelete"]),
  };
}

function readTable(row: Record<string, unknown>): RawTable {
  return {
    schema: str(row["schema"]) ?? "public",
    name: str(row["name"]) ?? "",
    kind: str(row["kind"]) ?? "r",
    rls: row["rls"] === true,
    comment: str(row["comment"]),
    columns: records(row["columns"]).map((each) => readColumn(each)),
    constraints: records(row["constraints"]).map((each) =>
      readConstraint(each),
    ),
    indexes: records(row["indexes"]).map((each) => ({
      columns: strings(each["columns"]),
      plain: each["plain"] === true,
    })),
    policies: typeof row["policies"] === "number" ? row["policies"] : 0,
    triggers: typeof row["triggers"] === "number" ? row["triggers"] : 0,
  };
}

/** Reads the one row `catalogQuery` returns; the JSON may arrive as text. */
function readCatalog(rows: readonly unknown[]): RawCatalog {
  const [row] = rows;
  const cell = isRecord(row) ? row["catalog"] : undefined;

  const catalog: unknown = typeof cell === "string" ? JSON.parse(cell) : cell;

  if (!isRecord(catalog)) {
    throw new TypeError("The catalog query returned an unexpected result.");
  }

  return {
    tables: records(catalog["tables"]).map((each) => readTable(each)),
    functions: strings(catalog["functions"]),
  };
}

const SIMPLE_TYPES: readonly (readonly [RegExp, AppColumn["type"]])[] = [
  [
    /^(?:text|character varying(?:\(\d+\))?|character(?:\(\d+\))?|citext)$/u,
    "text",
  ],
  [/^uuid$/u, "uuid"],
  [/^(?:integer|smallint)$/u, "integer"],
  [/^bigint$/u, "bigint"],
  [/^numeric(?:\(\d+(?:,\d+)?\))?$/u, "numeric"],
  [/^boolean$/u, "boolean"],
  [/^timestamp with time zone$/u, "timestamptz"],
  [/^date$/u, "date"],
  [/^(?:jsonb|json)$/u, "jsonb"],
  [/^(?:text|character varying(?:\(\d+\))?)\[\]$/u, "text[]"],
];

function columnType(type: string): AppColumn["type"] | undefined {
  return SIMPLE_TYPES.find(([pattern]) => pattern.test(type))?.[1];
}

/** `'x'::text` and `(0)::bigint` print as `'x'` and `0`. */
function plainDefault(value: string): string {
  return value
    .replace(/^\((.*)\)(?:::[\w\s."[\]]+)$/u, "$1")
    .replace(/^('(?:[^']|'')*')(?:::[\w\s."[\]]+)$/u, "$1");
}

function onDelete(code: string | null): AppOnDeleteAction {
  // `code` is `pg_constraint.confdeltype`: a, r, c, n or d (set default).
  switch (code ?? "a") {
    case "r": {
      return "restrict";
    }

    case "c": {
      return "cascade";
    }

    case "n": {
      return "set null";
    }

    default: {
      return "no action";
    }
  }
}

function rungOf(table: RawTable): AdoptionRung {
  if (!table.rls) {
    return "open";
  }

  return table.policies === 0 ? "locked" : "protected";
}

const qualified = (table: { schema: string; name: string }): string =>
  `${table.schema}.${table.name}`;

/** A table the design can model: `public`, a single `id` key, no generated id. */
function idOf(table: RawTable): "uuid" | "bigint" | undefined {
  const keys = table.constraints.filter((each) => each.type === "p");

  if (keys.length !== 1 || keys[0]?.columns.length !== 1) {
    return undefined;
  }

  if (keys[0].columns[0] !== "id") {
    return undefined;
  }

  const type = table.columns.find((each) => each.name === "id")?.type;

  if (type === "uuid") {
    return "uuid";
  }

  return type === "bigint" ? "bigint" : undefined;
}

function modelTable(
  table: RawTable,
  modeled: ReadonlySet<string>,
  preserved: PreservedObject[],
): AppTable | undefined {
  const id = idOf(table);

  if (id === undefined) {
    return undefined;
  }

  const names = new Set(table.columns.map((each) => each.name));

  const timestamps = ["created_at", "updated_at"].every(
    (name) =>
      table.columns.find((each) => each.name === name)?.type ===
      "timestamp with time zone",
  );

  const implicit = new Set([
    "id",
    ...(timestamps ? ["created_at", "updated_at"] : []),
  ]);

  const unique = new Set<string>();
  const uniqueSets: string[][] = [];
  const references = new Map<string, NonNullable<AppColumn["references"]>>();

  for (const constraint of table.constraints) {
    if (constraint.type === "u") {
      if (
        constraint.columns.length === 1 &&
        constraint.columns[0] !== undefined
      ) {
        unique.add(constraint.columns[0]);
      } else {
        uniqueSets.push([...constraint.columns]);
      }
    }

    if (constraint.type !== "f") {
      continue;
    }

    const [column] = constraint.columns;
    const target = `${constraint.refSchema ?? ""}.${constraint.refTable ?? ""}`;
    const onlyOne = constraint.columns.length === 1 && column !== undefined;
    const toId = constraint.refColumns?.join(",") === "id";

    if (onlyOne && toId && target === "auth.users") {
      references.set(column, {
        table: "auth.users",
        onDelete: onDelete(constraint.onDelete),
      });
    } else if (
      onlyOne &&
      toId &&
      constraint.refSchema === "public" &&
      modeled.has(target)
    ) {
      references.set(column, {
        table: constraint.refTable ?? "",
        onDelete: onDelete(constraint.onDelete),
      });
    } else {
      preserved.push({
        kind: "foreign_key",
        name: `${qualified(table)}(${constraint.columns.join(", ")})`,
        reason: `References ${target}, which a design can't express.`,
      });
    }
  }

  const columns: Record<string, AppColumn> = {};

  for (const column of table.columns) {
    if (implicit.has(column.name)) {
      continue;
    }

    const type = columnType(column.type);

    if (type === undefined || column.generated) {
      preserved.push({
        kind: "column",
        name: `${qualified(table)}.${column.name}`,
        reason: column.generated
          ? "A generated column is kept as it is."
          : `The type ${column.type} is kept as it is.`,
      });
      continue;
    }

    const reference = references.get(column.name);
    let fallback: string | undefined;

    if (column.default !== null) {
      const value = plainDefault(column.default);

      if (appDefaultError({ type }, value) === undefined) {
        fallback = value;
      } else {
        preserved.push({
          kind: "default",
          name: `${qualified(table)}.${column.name}`,
          reason: `The default ${column.default} is kept as it is.`,
        });
      }
    }

    columns[column.name] = {
      type,
      ...(column.nullable ? {} : { nullable: false }),
      ...(fallback === undefined ? {} : { default: fallback }),
      ...(unique.has(column.name) ? { unique: true } : {}),
      ...(reference === undefined ? {} : { references: reference }),
      ...(column.identity === null ? {} : { identity: true }),
      ...(column.comment === null ? {} : { comment: column.comment }),
    };
  }

  const indexes: string[][] = [];

  for (const index of table.indexes) {
    if (index.plain && index.columns.every((name) => names.has(name))) {
      indexes.push([...index.columns]);
    } else {
      preserved.push({
        kind: "index",
        name: `${qualified(table)}(${index.columns.join(", ")})`,
        reason: "An expression, partial or non-btree index is kept as it is.",
      });
    }
  }

  return {
    columns,
    scope: "none",
    ...(timestamps ? {} : { timestamps: false }),
    ...(id === "bigint" ? { id } : {}),
    ...(uniqueSets.length === 0 ? {} : { unique: uniqueSets }),
    ...(indexes.length === 0 ? {} : { indexes }),
    ...(table.comment === null ? {} : { comment: table.comment }),
  };
}

/** Turns a catalog into a design and the report the import shows. */
export function designFromCatalog(
  catalog: RawCatalog,
  issues: readonly Issue[] = [],
): ImportResult {
  const preserved: PreservedObject[] = [];
  const verifier: Issue[] = [];
  const blockOwned: string[] = [];
  const imported: ImportedTable[] = [];
  const appTables: Record<string, AppTable> = {};

  const candidates = catalog.tables.filter((table) => {
    if (table.kind === "v" || table.kind === "m") {
      preserved.push({
        kind: "view",
        name: qualified(table),
        reason: "A view is kept as it is.",
      });

      return false;
    }

    if (table.name.startsWith(BLOCK_PREFIX)) {
      blockOwned.push(qualified(table));

      return false;
    }

    return true;
  });

  // A reference can only point at a table that is itself modeled, so settle
  // which tables are modelable before reading their keys.
  const modeled = new Set(
    candidates
      .filter((table) => table.schema === "public" && idOf(table) !== undefined)
      .map((table) => qualified(table)),
  );

  for (const table of candidates) {
    const model = modeled.has(qualified(table))
      ? modelTable(table, modeled, preserved)
      : undefined;

    if (model === undefined) {
      preserved.push({
        kind: "table",
        name: qualified(table),
        reason:
          table.schema === "public"
            ? "It has no single uuid or bigint id key, so it is kept as it is."
            : "Only the public schema is modeled.",
      });
    } else {
      appTables[table.name] = model;
    }

    imported.push({
      schema: table.schema,
      name: table.name,
      rung: rungOf(table),
      modeled: model !== undefined,
      columns: table.columns.length,
    });

    if (!table.rls) {
      verifier.push({
        code: "verify_rls_disabled",
        severity: "error",
        source: "verifier",
        path: "",
        table: table.name,
        message: `${qualified(table)} has row level security off, so the Data API exposes every row.`,
      });
    } else if (table.policies === 0) {
      verifier.push({
        code: "verify_no_policies",
        severity: "info",
        source: "verifier",
        path: "",
        table: table.name,
        message: `${qualified(table)} has row level security on and no policies, so only the service role can read it.`,
      });
    }

    if (table.triggers > 0) {
      preserved.push({
        kind: "trigger",
        name: qualified(table),
        reason: `${String(table.triggers)} trigger(s) are kept as they are.`,
      });
    }

    if (table.policies > 0) {
      preserved.push({
        kind: "policy",
        name: qualified(table),
        reason: `${String(table.policies)} polic${table.policies === 1 ? "y is" : "ies are"} kept as ${table.policies === 1 ? "it is" : "they are"}.`,
      });
    }
  }

  for (const name of catalog.functions) {
    preserved.push({
      kind: "function",
      name,
      reason: "A function is kept as it is.",
    });
  }

  return {
    design: Object.keys(appTables).length === 0 ? {} : { appTables },
    report: {
      counts: {
        tables: candidates.length,
        modeledTables: Object.keys(appTables).length,
        columns: candidates.reduce(
          (sum, table) => sum + table.columns.length,
          0,
        ),
        views: catalog.tables.filter(
          (table) => table.kind !== "r" && table.kind !== "p",
        ).length,
        functions: catalog.functions.length,
        triggers: catalog.tables.reduce(
          (sum, table) => sum + table.triggers,
          0,
        ),
        policies: catalog.tables.reduce(
          (sum, table) => sum + table.policies,
          0,
        ),
      },
      tables: imported,
      blockOwned,
      preserved,
      issues: [...issues, ...verifier],
    },
  };
}

function messageOf(error: unknown): string {
  return (error instanceof Error ? error.message : String(error))
    .replaceAll(/\s+/gu, " ")
    .slice(0, 300);
}

async function readFiles(
  files: readonly ImportFile[],
  schemas: readonly string[],
  runtime: LiteRuntime | undefined,
): Promise<ImportResult> {
  const lite = runtime ?? (await loadLite());

  if (lite === undefined) {
    throw new Error(LITE_INSTALL);
  }

  const connection = await lite.createPgliteConnection();

  try {
    const { driver } = connection;
    const issues: Issue[] = [];

    await driver.exec(SUPABASE_PRELUDE);

    const ordered = files.toSorted((left, right) =>
      left.path.localeCompare(right.path),
    );

    for (const file of ordered) {
      try {
        await driver.exec(file.contents);
      } catch (error) {
        issues.push({
          code: "sql_error",
          severity: "error",
          source: "sql",
          path: "",
          table: file.path,
          file: file.path,
          message: messageOf(error),
        });
      }
    }

    const { rows } = await driver.query(catalogQuery(schemas));

    return designFromCatalog(readCatalog(rows), issues);
  } finally {
    await connection.close();
  }
}

async function readSupabase(
  source: Extract<ImportSource, { kind: "supabase" }>,
  schemas: readonly string[],
): Promise<ImportResult> {
  const base = (source.apiUrl ?? "https://api.supabase.com").replace(
    /\/$/u,
    "",
  );

  const call = source.fetch ?? fetch;

  const response = await call(
    `${base}/v1/projects/${encodeURIComponent(source.projectRef)}/database/query/read-only`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${source.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ query: catalogQuery(schemas) }),
    },
  );

  if (!response.ok) {
    throw new Error(
      `Supabase answered ${String(response.status)} for project ${source.projectRef}.`,
    );
  }

  const rows: unknown = await response.json();

  if (!Array.isArray(rows)) {
    throw new TypeError(
      `Supabase sent an unexpected body for project ${source.projectRef}.`,
    );
  }

  return designFromCatalog(readCatalog(rows));
}

/**
 * Reads an existing project into a `Design` and a report (ADR 0100). The design
 * models the tables Create can express: `public` tables with a single `uuid` or
 * `bigint` `id` key, their columns, references to other modeled tables or
 * `auth.users`, unique keys and plain indexes. Everything else is listed under
 * `report.preserved` and is never dropped: a deploy applies only what the
 * design adds. Tables named `bsb_*` belong to blocks. The report also carries
 * each table's adoption rung and the security findings (`source: "verifier"`).
 *
 * Throws when a `files` source needs `@supabase/lite` and it isn't installed,
 * or when a `supabase` source answers with an error.
 */
export async function importProject(
  options: ImportProjectOptions,
): Promise<ImportResult> {
  const schemas = options.schemas ?? ["public"];
  const { source } = options;

  switch (source.kind) {
    case "files": {
      return readFiles(source.files, schemas, options.runtime);
    }

    case "queryable": {
      const { rows } = await source.queryable.query(catalogQuery(schemas));

      return designFromCatalog(readCatalog(rows));
    }

    case "supabase": {
      return readSupabase(source, schemas);
    }

    default: {
      const exhaustive: never = source;

      return exhaustive;
    }
  }
}

/** Files in the shape `previewFiles` returns, for callers that hold those. */
export function importFilesOf(
  files: readonly PresetMigrationFile[],
): readonly ImportFile[] {
  return files
    .filter((file) => !file.path.includes("/tests/"))
    .map(({ path, contents }) => ({ path, contents }));
}
