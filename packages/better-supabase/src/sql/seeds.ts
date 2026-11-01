import type { BlockSqlContext } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";
import { serviceGrant } from "./shared.ts";

/**
 * Declared seeds (ADR 0196). A module lists the rows every organization starts
 * with as data, and `renderSeedDefaults` turns them into one idempotent
 * function, so applying the defaults twice leaves the same rows.
 */

/** A value in a seed row. */
export type SeedValue =
  | string
  | number
  | boolean
  | null
  /** The organization the defaults are applied to. */
  | { readonly tenant: true }
  /** The `variant` or `locale` the function was called with. */
  | { readonly param: "variant" | "locale" }
  /** The id (or `column`) of an earlier row of the same organization. */
  | {
      readonly ref: {
        readonly table: string;
        readonly tenantColumn: string;
        readonly match: Readonly<Record<string, string | number | boolean>>;
        readonly column?: string;
      };
    }
  /** A JSON document, cast to `jsonb`. */
  | { readonly json: unknown }
  /** A SQL expression, for what the other forms can't express. */
  | { readonly sql: string };

export interface SeedRow {
  readonly values: Readonly<Record<string, SeedValue>>;
}

/** The rows one table gets for each organization. */
export interface SeedTable {
  /** The table as SQL, schema-qualified (`ctx.table(...)`). */
  readonly table: string;
  /** The physical column that holds the organization. */
  readonly tenantColumn: string;
  /**
   * The columns that identify a row within an organization, such as `key`.
   * Rows whose key columns already exist are kept, so the function can run
   * twice. A table without a unique constraint on them is still safe: the
   * function checks before it inserts.
   */
  readonly key: readonly string[];
  readonly rows: readonly SeedRow[];
  /** The named variant these rows belong to; rows without one are always seeded. */
  readonly variant?: string;
  /** The locales these rows are seeded for; every locale when unset. */
  readonly locales?: readonly string[];
}

/** `BlockSql.seeds`. */
export interface BlockSeeds {
  /** The variants `defaults` knows, listed in the catalog and checked by doctor. */
  readonly variants?: readonly string[];
  /** Rows per organization. */
  readonly defaults?: (ctx: BlockSqlContext) => readonly SeedTable[];
}

export function seedFunctionName(module: string): string {
  return `seed_${module.replaceAll("-", "_")}_defaults`;
}

function valueSql(value: SeedValue): string {
  if (value === null) {
    return "null";
  }

  if (typeof value === "string") {
    return sqlString(value);
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new TypeError(`Seed value ${value} is not a finite number`);
    }

    return String(value);
  }

  if (typeof value === "boolean") {
    return String(value);
  }

  if ("tenant" in value) {
    return "p_tenant";
  }

  if ("param" in value) {
    return `p_${value.param}`;
  }

  if ("json" in value) {
    return `${sqlString(JSON.stringify(value.json))}::jsonb`;
  }

  if ("sql" in value) {
    return `(${value.sql})`;
  }

  const { ref } = value;
  const conditions = [
    `x.${sqlIdent(ref.tenantColumn)} = p_tenant`,
    ...Object.entries(ref.match).map(
      ([column, expected]) =>
        `x.${sqlIdent(column)} = ${valueSql(expected)}`,
    ),
  ];

  return `(select x.${sqlIdent(ref.column ?? "id")} from ${ref.table} x where ${conditions.join(" and ")} limit 1)`;
}

function tableSql(entry: SeedTable): string {
  if (entry.key.length === 0) {
    throw new Error(`Seed table ${entry.table} needs at least one key column`);
  }

  const statements = entry.rows.map((row) => {
    const values = { ...row.values };

    for (const column of entry.key) {
      if (!(column in values)) {
        throw new Error(
          `A seed row of ${entry.table} has no value for its key column "${column}"`,
        );
      }
    }

    const columns = [entry.tenantColumn, ...Object.keys(values)];
    const expressions = [
      "p_tenant",
      ...Object.values(values).map((value) => valueSql(value)),
    ];

    const same = entry.key
      .map((column) => `x.${sqlIdent(column)} is not distinct from ${valueSql(values[column]!)}`)
      .join(" and ");

    return `  insert into ${entry.table} (${columns.map((column) => sqlIdent(column)).join(", ")})
  select ${expressions.join(", ")}
  where not exists (select 1 from ${entry.table} x where x.${sqlIdent(entry.tenantColumn)} = p_tenant and ${same});`;
  });

  const guards = [
    entry.variant === undefined
      ? undefined
      : `p_variant is not distinct from ${sqlString(entry.variant)}`,
    entry.locales === undefined
      ? undefined
      : `p_locale = any (array[${entry.locales.map((locale) => sqlString(locale)).join(", ")}])`,
  ].filter((guard) => guard !== undefined);

  const body = statements.join("\n");

  return guards.length === 0
    ? body
    : `  if ${guards.join(" and ")} then\n${body.replaceAll(/^/gm, "  ")}\n  end if;`;
}

/**
 * The function that seeds one module's defaults for an organization. It
 * inserts only rows whose key is missing, so it can run again after the module
 * gains rows. `name` is the qualified function name, from `ctx.fn`.
 */
export function renderSeedDefaults(
  module: string,
  name: string,
  idType: string,
  tables: readonly SeedTable[],
): string {
  return `
-- Seeds the rows every organization starts with for ${module}. Safe to run
-- again: a row whose key exists is kept. It is not an entry point.
create or replace function ${name}(p_tenant ${idType}, p_variant text default null, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
${tables.map((entry) => tableSql(entry)).join("\n")}
end;
$$;
${serviceGrant(`${name}(${idType}, text, text)`)}
`;
}

/**
 * The function that applies every installed module's defaults for an
 * organization, in the order given. `variants` maps a module name to the
 * variant it should seed.
 */
export function renderSeedUmbrella(
  schema: string,
  idType: string,
  functions: readonly { readonly module: string; readonly fn: string }[],
): string {
  const calls = functions
    .map(
      ({ module, fn }) =>
        `  perform ${fn}(p_tenant, p_variants ->> ${sqlString(module)}, p_locale);`,
    )
    .join("\n");

  return `
-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with \`better-supabase db seed --defaults\`.
create or replace function ${schema}.seed_tenant_defaults(p_tenant ${idType}, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
${calls}
end;
$$;
${serviceGrant(`${schema}.seed_tenant_defaults(${idType}, jsonb, text)`)}
`;
}
