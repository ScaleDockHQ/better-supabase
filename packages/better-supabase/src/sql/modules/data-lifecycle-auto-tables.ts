import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

/** `options.autoTables`: every table in `schemas` with the tenant (or user) column. */
export interface AutoTables {
  readonly schemas: readonly string[];
  readonly tenant: string | undefined;
  readonly user: string | undefined;
  /** `schema.table` names or globs (`public.*_archive`) to leave out. */
  readonly exclude: readonly string[];
  readonly purge: boolean;
}

export function autoTablesOf(ctx: ModuleContext): AutoTables | undefined {
  const where = "sql.modules.data-lifecycle.options.autoTables";
  const option =
    ctx.option("tables") === "auto" ? {} : ctx.option("autoTables");
  if (option === undefined) return undefined;
  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(
      `${where} must be an object of { schemas?, tenant?, user?, exclude?, purge? }`,
    );
  }
  // SAFETY: an object, and each field is checked below.
  const config = option as Record<string, unknown>;
  const list = (
    key: string,
    fallback: readonly string[],
  ): readonly string[] => {
    const value = config[key];
    if (value === undefined) return fallback;
    if (
      !Array.isArray(value) ||
      !value.every((item) => typeof item === "string")
    )
      throw new TypeError(`${where}.${key} must be a list of strings`);
    return value;
  };
  const column = (key: string, fallback?: string): string | undefined => {
    const value = config[key];
    if (value === undefined) return fallback;
    if (value === null) return undefined;
    if (typeof value !== "string" || !IDENT.test(value))
      throw new TypeError(`${where}.${key} must be a lowercase column name`);
    return value;
  };
  const schemas = list("schemas", ["public"]);
  for (const schema of schemas) {
    if (!IDENT.test(schema))
      throw new TypeError(`${where}.schemas: "${schema}" is not a schema name`);
  }
  return {
    schemas,
    tenant: column("tenant", "organization_id"),
    user: column("user"),
    exclude: list("exclude", []),
    purge: config["purge"] !== false,
  };
}

/** The catalog query that lists `auto` tables, minus the explicit ones. */
export function autoTablesSql(
  auto: AutoTables,
  explicit: readonly { readonly name: string }[],
): string {
  const names = [...new Set(explicit.map((entry) => entry.name))].map(
    sqlString,
  );
  const excluded = auto.exclude.map(
    (pattern) =>
      `n.nspname || '.' || c.relname like ${sqlString(pattern.replaceAll("_", "\\_").replaceAll("*", "%"))}`,
  );
  const select = (subject: string, column: string): string => `
  select ${sqlString(subject)}::text, n.nspname || '.' || c.relname, format('%I.%I', n.nspname, c.relname), a.attname::text, ${String(auto.purge)}, '{}'::text[], true
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_attribute a on a.attrelid = c.oid and a.attname = ${sqlString(column)} and not a.attisdropped
  where c.relkind in ('r', 'p')
    and n.nspname in (${auto.schemas.map(sqlString).join(", ")})
    and not c.relispartition${
      names.length > 0
        ? `
    and n.nspname || '.' || c.relname not in (${names.join(", ")})`
        : ""
    }${excluded
      .map(
        (rule) => `
    and not (${rule})`,
      )
      .join("")}`;
  return [
    ...(auto.tenant ? [select("organization", auto.tenant)] : []),
    ...(auto.user ? [select("user", auto.user)] : []),
  ].join("\n  union all");
}
