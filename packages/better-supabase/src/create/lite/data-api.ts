import type { CreateDesign, PresetInput } from "../../preset/index.ts";
import type { SchemaMeta, TableMeta } from "../../schema/types.ts";
import type { SpecDiagnostic } from "../../spec/format.ts";
import type { Issue } from "../issue.ts";
import type { RawCatalog, RawColumn, RawTable } from "./catalog.ts";
import type { SandboxOptions } from "./sandbox.ts";

import { defineApi } from "../../spec/api.ts";
import { loadProject } from "../project.ts";
import { openSandbox } from "./sandbox.ts";

const JSON_TYPES = new Set(["json", "jsonb"]);

function columnMeta(column: RawColumn): TableMeta["columns"][string] {
  const identity =
    column.identity === "a"
      ? "always"
      : column.identity === "d"
        ? "by default"
        : undefined;

  return {
    db: column.name,
    type: column.udt,
    nullable: column.nullable,
    hasDefault: column.default !== null || identity !== undefined,
    ...(column.generated ? { generated: true } : {}),
    ...(identity === undefined ? {} : { identity }),
    ...(column.array ? { array: true } : {}),
    ...(JSON_TYPES.has(column.udt) ? { json: true } : {}),
    ...(column.enumValues.length > 0 ? { enum: column.enumValues } : {}),
    ...(column.comment === null ? {} : { description: column.comment }),
  };
}

function tableMeta(table: RawTable): TableMeta {
  const uniqueKeys: Record<string, readonly string[]> = {};

  for (const constraint of table.constraints) {
    if (constraint.type === "u") {
      uniqueKeys[constraint.name] = constraint.columns;
    }
  }

  return {
    key: table.name,
    name: table.name,
    schema: table.schema,
    kind: table.kind === "r" || table.kind === "p" ? "table" : "view",
    columns: Object.fromEntries(
      table.columns.map((column) => [column.name, columnMeta(column)]),
    ),
    primaryKey:
      table.constraints.find((each) => each.type === "p")?.columns ?? [],
    uniqueKeys,
    relations: {},
    flags: {},
    ...(table.comment === null ? {} : { description: table.comment }),
  };
}

/**
 * The runtime metadata of a catalog's `public` tables and views, in snake
 * casing, keyed by table name. It carries what the Data API document needs:
 * columns, keys and enums. Relations and functions are left out.
 */
export function schemaMetaFromCatalog(catalog: RawCatalog): SchemaMeta {
  const tables = catalog.tables.filter((table) => table.schema === "public");

  const enums: Record<string, readonly string[]> = {};

  for (const table of tables) {
    for (const column of table.columns) {
      if (column.enumValues.length > 0) {
        enums[column.udt] = column.enumValues;
      }
    }
  }

  return {
    version: 1,
    casing: "snake",
    tables: Object.fromEntries(
      tables.map((table) => [table.name, tableMeta(table)]),
    ),
    enums,
    functions: {},
  };
}

export interface DesignDataApiOptions extends SandboxOptions {
  /** The document's `info`. Defaults to the project name `Data API`. */
  readonly title?: string;
  readonly version?: string;
  /** The project URL, which the `/rest/v1` paths resolve against. */
  readonly supabaseUrl?: string;
}

export type DesignDataApi =
  | {
      readonly ok: true;
      /** The OpenAPI 3.1 document of the project's Data API. */
      readonly document: unknown;
      readonly diagnostics: readonly SpecDiagnostic[];
      /** The tables the document describes. */
      readonly tables: readonly string[];
    }
  | { readonly ok: false; readonly issues: readonly Issue[] };

/**
 * The OpenAPI document of the Data API a design produces: the files render to a
 * PGlite database, and the tables that come out become `/rest/v1` paths with
 * row, insert and update schemas. It never touches a project. Throws when
 * `@supabase/lite` isn't installed.
 */
export async function designDataApi(
  preset: PresetInput,
  design: CreateDesign = {},
  options: DesignDataApiOptions = {},
): Promise<DesignDataApi> {
  const loaded = await loadProject(design, { preset });

  if (!loaded.ok) {
    return loaded;
  }

  const sandbox = await openSandbox(loaded.project, options);

  try {
    const catalog = await sandbox.catalog();
    const meta = schemaMetaFromCatalog(catalog);

    const api = defineApi(
      { meta },
      {
        info: {
          title: options.title ?? "Data API",
          version: options.version ?? "1.0.0",
        },
        dataApi: { tables: true },
        ...(options.supabaseUrl === undefined
          ? {}
          : { supabaseUrl: options.supabaseUrl }),
      },
    );

    const { document, diagnostics } = api.openapi();

    return {
      ok: true,
      document,
      diagnostics,
      tables: Object.keys(meta.tables).toSorted(),
    };
  } finally {
    await sandbox.close();
  }
}
