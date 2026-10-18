import type { ModuleContext } from "../context.ts";
import type { ModuleLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { moduleContext } from "../module-context.ts";
import { tableGlobs } from "../schema-scan.ts";
import { autoTablesOf } from "./data-lifecycle-auto-tables.ts";
import { entries } from "./data-lifecycle-entries.ts";

/** Column names that usually hold a credential, matched case-insensitively. */
export const SECRET_COLUMNS = "token|secret|_hash|password|api_key|license_key";

/**
 * `options.omitPattern`: `true` for `SECRET_COLUMNS`, a string for a
 * Postgres regex of its own. Undefined when off.
 */
export function omitPatternOf(ctx: ModuleContext): string | undefined {
  const value = ctx.option("omitPattern");

  if (value === undefined || value === false) {
    return undefined;
  }

  if (value === true) {
    return SECRET_COLUMNS;
  }

  if (typeof value !== "string" || value === "") {
    throw new TypeError(
      "blocks.data-lifecycle.options.omitPattern must be true or a Postgres regular expression",
    );
  }

  return value;
}

/**
 * `body`'s rows with every column of the table whose name matches
 * `pattern` (`~*`) appended to `omit`, read from `pg_attribute` when the
 * function runs.
 */
export function withOmitPattern(body: string, pattern: string): string {
  return `select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* ${sqlString(pattern)}
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  ${body}
  ) as t(subject, name, tbl, col, purge, omit, exported)`;
}

/** What doctor needs to tell which columns a data export reads. */
export interface DataExportPlan {
  /** The listed and module tables an export reads, `schema.table`, with the columns it leaves out. */
  readonly tables: readonly {
    readonly name: string;
    readonly omit: readonly string[];
  }[];
  /** `options.autoTables`: the tables in `schemas` with one of `columns`, minus `excluded` and the listed ones. */
  readonly auto:
    | {
        readonly schemas: readonly string[];
        readonly columns: readonly string[];
        readonly excluded: (name: string) => boolean;
      }
    | undefined;
  /** `options.omitPattern`, resolved. */
  readonly omitPattern: string | undefined;
}

/** The export tables for doctor. Undefined without the `data-lifecycle` module. */
export function dataExportPlan(
  layout: ModuleLayout,
  installed: readonly string[],
): DataExportPlan | undefined {
  if (!installed.includes("data-lifecycle")) {
    return undefined;
  }

  const ctx = moduleContext("data-lifecycle", layout, installed);
  const list = entries(ctx);
  const auto = autoTablesOf(ctx);
  const listed = new Set(list.map((entry) => entry.name));

  const globs = tableGlobs(auto?.exclude ?? []);

  return {
    tables: list
      .filter((entry) => entry.export)
      .map((entry) => ({ name: entry.name, omit: entry.omit })),
    auto:
      auto === undefined
        ? undefined
        : {
            schemas: auto.schemas,
            columns: [auto.tenant, auto.user].filter(
              (column): column is string => column !== undefined,
            ),
            excluded: (name) =>
              listed.has(name) || globs.some((glob) => glob.test(name)),
          },
    omitPattern: omitPatternOf(ctx),
  };
}
