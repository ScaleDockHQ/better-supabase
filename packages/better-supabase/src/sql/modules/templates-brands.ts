import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { quotedTable, SERVICE_CALLER, userGrant } from "../shared.ts";

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

const WHERE = "blocks.templates.options.brand";

/** Where a tenant's brand lives: `{ table, column, tenant? }`, quoted. */
export interface BrandSource {
  readonly table: string;
  readonly column: string;
  readonly tenant: string;
}

/**
 * `options.brand`: the table and column that hold a tenant's brand, and the
 * column with the tenant id (`id` by default, for a column on the tenant
 * table). Undefined when the option is unset.
 */
export function brandOf(ctx: BlockSqlContext): BrandSource | undefined {
  const option = ctx.option("brand");

  if (option === undefined) {
    return undefined;
  }

  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(`${WHERE} must be { table, column, tenant? }`);
  }

  const entries = new Map<string, unknown>(Object.entries(option));

  const ident = (key: string, fallback?: string): string => {
    const value = entries.get(key) ?? fallback;

    if (typeof value !== "string" || !IDENT.test(value)) {
      throw new TypeError(`${WHERE}.${key} must be a lowercase identifier`);
    }

    return sqlIdent(value);
  };

  const table = entries.get("table");

  if (
    typeof table !== "string" ||
    table.split(".").length > 2 ||
    !table.split(".").every((part) => IDENT.test(part))
  ) {
    throw new TypeError(`${WHERE}.table must be "table" or "schema.table"`);
  }

  if (!ctx.has("templates", "scope") || !ctx.has("templates", "brand")) {
    throw new TypeError(
      `${WHERE} needs the templates table's scope and brand columns`,
    );
  }

  return {
    table: quotedTable(table),
    column: ident("column"),
    tenant: ident("tenant", "id"),
  };
}

export interface BrandParts {
  /** The brand column, its checks and indexes, and `template_brand`. */
  readonly ddl: string;
  /** An `or` branch of the read policy: the caller's brands' starters. */
  readonly readable: string;
  /** `or` the row at `prefix` is a starter of the brand of `tenant`. */
  readonly visible: (prefix: string, tenant: string) => string;
  /** The starter's brand in `sync_templates`, or null. */
  readonly starter: string;
  /** The key and default indexes' leading columns: the brand after the tenant. */
  readonly keyColumns: string;
  /** The name of the key or default index, `templates_brand_*` with brands. */
  readonly index: (base: "key" | "default") => string;
}

/**
 * Brand-scoped starters: a template with scope `brand` has no tenant and a
 * brand, and every tenant whose brand matches reads, forks and applies it.
 * Nothing is rendered without `options.brand`.
 */
export function brandParts(
  ctx: BlockSqlContext,
  source: BrandSource | undefined,
  read: string,
): BrandParts {
  const ct = (column: string): string => ctx.col("templates", column);

  if (source === undefined) {
    return {
      ddl: "",
      readable: "",
      visible: () => "",
      starter: "null",
      keyColumns: ct("tenant"),
      index: (base) => ctx.naming.rename(`templates_${base}_idx`),
    };
  }

  const t = ctx.table("templates");
  const fn = ctx.fn("template_brand");
  const id = ctx.idType;
  const { schema, name } = ctx.tableName("templates");
  const scope = (prefix: string): string => `${prefix}${ct("scope")}`;
  const brand = (prefix: string): string => `${prefix}${ct("brand")}`;

  // An adopted table keeps its own checks; the app allows 'brand' in its
  // scope column itself.
  const scopeCheck = sqlIdent(
    `${name}_${ctx.colName("templates", "scope")}_check`,
  );

  const checks = ctx.appOwned.includes("templates")
    ? ""
    : `
alter table ${t} drop constraint if exists ${scopeCheck};
alter table ${t} add constraint ${scopeCheck} check (${scope("")} in ('tenant', 'brand', 'system'));
alter table ${t} drop constraint if exists ${ctx.naming.rename("templates_system_check")};
alter table ${t} add constraint ${ctx.naming.rename("templates_system_check")} check (case ${scope("")}::text
  when 'tenant' then ${ct("tenant")} is not null and ${brand("")} is null
  when 'brand' then ${ct("tenant")} is null and ${brand("")} is not null
  else ${ct("tenant")} is null and ${brand("")} is null end);`;

  return {
    ddl: `
-- Brand starters (options.brand): no tenant, a brand, read by every tenant
-- whose ${source.table}.${source.column} matches. The key and default indexes
-- count the brand, so each brand keeps its own keys and defaults.
alter table ${t} add column if not exists ${brand("")} text check (length(${brand("")}) between 1 and 100);${checks}
drop index if exists ${sqlIdent(schema)}.${ctx.naming.rename("templates_key_idx")};
drop index if exists ${sqlIdent(schema)}.${ctx.naming.rename("templates_default_idx")};
create index if not exists ${ctx.naming.rename("templates_brand_idx")} on ${t} (${brand("")}) where ${brand("")} is not null;

-- The brand of tenant, for the caller who reads templates there; null for
-- anyone else.
create or replace function ${fn}(tenant ${id})
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b.${source.column}::text from ${source.table} b
  where b.${source.tenant} = template_brand.tenant
    and (${SERVICE_CALLER} or ${ctx.scope.can("template_brand.tenant", read)})
  limit 1
$$;
${userGrant(`${fn}(${id})`)}
`,
    readable: `
    or (${scope("")} = 'brand' and ${brand("")} in (select ${fn}(s) from ${ctx.scope.ids(read)} s))`,
    visible: (prefix, tenant) =>
      ` or (${scope(prefix)} = 'brand' and ${brand(prefix)} = ${fn}(${tenant}))`,
    starter: `nullif(v_starter ->> 'brand', '')`,
    keyColumns: `${ct("tenant")}, ${brand("")}`,
    index: (base) => ctx.naming.rename(`templates_brand_${base}_idx`),
  };
}
