/* oxlint-disable eslint/no-bitwise -- FNV-1a works on 32-bit integers. */

import type { DisabledRow } from "../config/blocks.ts";
import type { ExtraColumn, ModuleContext } from "./context.ts";

import { MAX_BATCH } from "../core/batch-limit.ts";
import { sqlIdent, sqlString } from "../core/template.ts";

/**
 * What `record` and the other statement helpers return when there is nothing to
 * do.
 */
export const NOTHING = "null;";

/**
 * `alter table ... add column if not exists` for each extra column of a managed
 * table.
 */
export const addExtraColumns = (
  table: string,
  columns: readonly ExtraColumn[],
): string =>
  columns
    .map(
      (column) =>
        `\nalter table ${table} add column if not exists ${column.ident} ${column.type};`,
    )
    .join("");

/**
 * A `jsonb` object of `columns` of row `alias`, keyed by column name, so reads
 * return extra columns without exposing the rest of the row.
 */
export const columnsObject = (
  alias: string,
  columns: readonly string[],
): string =>
  `jsonb_build_object(${columns
    .map((name) => `${sqlString(name)}, ${alias}.${sqlIdent(name)}`)
    .join(", ")})`;

/**
 * `, 'fields', jsonb_build_object(...)` of the extra columns of row `alias`,
 * for a read built with `jsonb_build_object`; empty without any.
 */
export const extraFieldsJson = (
  alias: string,
  extras: readonly ExtraColumn[],
): string =>
  extras.length === 0
    ? ""
    : `, 'fields', ${columnsObject(
        alias,
        extras.map((extra) => extra.name),
      )}`;

/**
 * PL/pgSQL that copies the extra columns from `source`, a `jsonb` object keyed
 * by column name, onto the rows of `table` (alias `x`) that `where` matches. A
 * key `source` leaves out keeps the column's value, so it runs after an insert
 * (the defaults stay) and on a partial update. Empty without extra columns.
 */
export const writeExtraColumns = (
  table: string,
  extras: readonly ExtraColumn[],
  source: string,
  where: string,
  into?: string,
): string =>
  extras.length === 0
    ? ""
    : `
  update ${table} x set ${extras
    .map(
      (extra) =>
        `${extra.ident} = case when ${source} ? ${sqlString(extra.name)} then r.${extra.ident} else x.${extra.ident} end`,
    )
    .join(", ")}
  from jsonb_populate_record(null::${table}, (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(${source}) e where e.key in (${extras
    .map((extra) => sqlString(extra.name))
    .join(", ")}))) r
  where ${where}${into === undefined ? "" : `\n  returning x.* into ${into}`};`;

/**
 * `json` (a `jsonb` expression of row `alias`) with the extra columns under
 * `fields`, or `json` itself without any.
 */
export const withExtraFields = (
  json: string,
  alias: string,
  extras: readonly ExtraColumn[],
): string =>
  extras.length === 0
    ? json
    : `(${json} || jsonb_build_object('fields', ${columnsObject(
        alias,
        extras.map((extra) => extra.name),
      )}))`;

/**
 * The `fields jsonb` parameter of a function that writes extra columns, after
 * its other parameters. Every module that takes `extraColumns` on a write uses
 * it: `param` in the parameter list, `type` in the grants, `contract` in the
 * contract entry, and `drop` before the function.
 */
export interface ExtraFieldsArg {
  /** `, fields jsonb default null`, or nothing without extra columns. */
  readonly param: string;
  /** `, jsonb` for the signature, or nothing. */
  readonly type: string;
  /** The contract's argument types to append. */
  readonly contract: readonly string[];
  /**
   * Drops the signature this build doesn't create (with the parameter when
   * there are no extra columns, without it when there are), so turning
   * `extraColumns` on or off never leaves two overloads a call matches.
   */
  drop(fn: string, types: string): string;
}

/** The `fields jsonb` parameter for `columns`; see `ExtraFieldsArg`. */
export function extraFieldsArg(
  columns: readonly ExtraColumn[],
): ExtraFieldsArg {
  const on = columns.length > 0;

  return {
    param: on ? ", fields jsonb default null" : "",
    type: on ? ", jsonb" : "",
    contract: on ? ["jsonb"] : [],
    drop: (fn, types) =>
      `drop function if exists ${fn}(${on ? types : [types, "jsonb"].filter((type) => type !== "").join(", ")});`,
  };
}

export const SCHEMA = `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`;

/**
 * A SQL condition true for the service role and for a direct admin connection
 * (no JWT, a privileged session user), which may act for others.
 */
export const SERVICE_CALLER =
  "coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')";

/**
 * The `organization.member_added` record for a module that adds a member, so
 * every module writes the same payload. Each value is a SQL expression.
 */
export function memberAddedRecord(
  ctx: ModuleContext,
  member: {
    readonly tenant: string;
    readonly user: string;
    readonly role: string;
  },
): string {
  return ctx.record({
    type: "organization.member_added",
    payload: `jsonb_build_object('organizationId', ${member.tenant}::text, 'userId', ${member.user}, 'role', ${member.role})`,
    subject: `'organizations/' || ${member.tenant}::text`,
    tenant: member.tenant,
    audit: {
      category: "membership",
      targetType: "user",
      recordId: `${member.user}::text`,
    },
  });
}

/**
 * Creates the module's schema when it isn't `better_supabase`, then the module
 * schema.
 */
export function schemaPreamble(ctx: ModuleContext): string {
  if (ctx.schemaName === "better_supabase") {
    return SCHEMA;
  }

  return `${SCHEMA}
create schema if not exists ${ctx.schema};
grant usage on schema ${ctx.schema} to anon, authenticated, service_role;`;
}

/** A claim from the top level of the token, then `app_metadata`. */
export function jwtClaim(name: string): string {
  return `coalesce(auth.jwt() ->> ${sqlString(name)}, auth.jwt() -> 'app_metadata' ->> ${sqlString(name)})`;
}

/** `table` or `schema.table` as `[schema, table]`, in `public` without a schema. */
export function splitTable(name: string): readonly [string, string] {
  const parts = name.split(".");

  if (parts.length > 2 || parts.some((part) => part.length === 0)) {
    throw new TypeError(`"${name}" must be "table" or "schema.table"`);
  }

  return parts.length === 2 ? [parts[0]!, parts[1]!] : ["public", parts[0]!];
}

/** `table` or `schema.table`, quoted. */
export function quotedTable(name: string): string {
  const [schema, table] = splitTable(name);

  return `${sqlIdent(schema)}.${sqlIdent(table)}`;
}

/** `schema.table.column` split into its quoted table and column. */
export function columnRef(
  where: string,
  value: string,
): { readonly table: string; readonly column: string } {
  const parts = value.split(".");

  if (parts.length !== 3 || parts.some((part) => part.length === 0)) {
    throw new TypeError(
      `${where} must be "schema.table.column", got "${value}"`,
    );
  }

  const [schema, table, column] = parts;

  return {
    table: `${sqlIdent(schema!)}.${sqlIdent(table!)}`,
    column: sqlIdent(column!),
  };
}

const QUOTED_IDENT = /^"(.*)"$/s;

/**
 * Replaces the check constraints on one column of a table a module created
 * earlier: `create table if not exists` never changes an inline check, and its
 * generated name follows the table's configured name. For upgrade steps.
 * `column` is a quoted identifier; the catalog stores the bare name.
 */
export function replaceColumnCheck(check: {
  readonly table: string;
  readonly column: string;
  readonly name: string;
  readonly expression: string;
}): string {
  const column =
    QUOTED_IDENT.exec(check.column)?.[1]?.replaceAll('""', '"') ?? check.column;

  return `do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = ${sqlString(check.table)}::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = ${sqlString(column)}
  loop
    execute format('alter table %s drop constraint %I', ${sqlString(check.table)}, v_name);
  end loop;
end;
$$;
alter table ${check.table} add constraint ${sqlIdent(check.name)} check (${check.expression});`;
}

/**
 * Adds a foreign key to a table a module created earlier, once: `create table
 * if not exists` can't add it to a table that already exists, and the
 * referenced table can come from a module that renders later. Existing rows
 * without a match leave the key unvalidated, with a warning.
 */
export function addForeignKey(fk: {
  readonly table: string;
  readonly name: string;
  readonly column: string;
  readonly references: string;
  readonly onDelete: "cascade" | "restrict" | "set null";
}): string {
  return `do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = ${sqlString(fk.table)}::regclass and conname = ${sqlString(fk.name)}
  ) then
    alter table ${fk.table} add constraint ${sqlIdent(fk.name)}
      foreign key (${fk.column}) references ${fk.references} on delete ${fk.onDelete} not valid;
    begin
      alter table ${fk.table} validate constraint ${sqlIdent(fk.name)};
    exception when foreign_key_violation then
      raise warning '% has rows without a match, so only new rows are checked. Delete them, then run: alter table % validate constraint %',
        ${sqlString(fk.table)}, ${sqlString(fk.table)}, ${sqlString(fk.name)};
    end;
  end if;
end;
$$;`;
}

/**
 * Adds a check constraint to a table a module created earlier, once, for the
 * same reason as `addForeignKey`. Existing rows that fail it leave the check
 * unvalidated, with a warning, so an upgrade never stops on old data.
 */
export function addCheck(check: {
  readonly table: string;
  readonly name: string;
  readonly expression: string;
}): string {
  return `do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = ${sqlString(check.table)}::regclass and conname = ${sqlString(check.name)}
  ) then
    alter table ${check.table} add constraint ${sqlIdent(check.name)}
      check (${check.expression}) not valid;
    begin
      alter table ${check.table} validate constraint ${sqlIdent(check.name)};
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        ${sqlString(check.table)}, ${sqlString(check.name)}, ${sqlString(check.table)}, ${sqlString(check.name)};
    end;
  end if;
end;
$$;`;
}

/**
 * An `updated_at` column on a managed table, kept current by the `updated-at`
 * module's `set_updated_at()` (the module must require it).
 */
export function updatedAt(table: string, column: string): string {
  return `alter table ${table} add column if not exists ${column} timestamptz not null default now();
drop trigger if exists bsb_updated_at on ${table};
create trigger bsb_updated_at before update on ${table}
  for each row execute function better_supabase.set_updated_at(${sqlString(column.replaceAll('"', ""))});`;
}

/**
 * Upgrade-step renames for a module table in `schema`. Each runs only while the
 * old name exists and the new one doesn't, so a step can run again.
 */
export interface ModuleRenames {
  readonly schema: string;
  /** The table's current name; `table` in `tables` renames it first. */
  readonly table: string;
  readonly tables?: readonly (readonly [from: string, to: string])[];
  readonly columns?: readonly (readonly [from: string, to: string])[];
  readonly indexes?: readonly (readonly [from: string, to: string])[];
  readonly functions?: readonly (readonly [
    from: string,
    to: string,
    args: string,
  ])[];
}

export function renameSql(renames: ModuleRenames): string {
  const schema = sqlString(renames.schema);

  const q = (name: string): string =>
    `${sqlIdent(renames.schema)}.${sqlIdent(name)}`;

  const lines: string[] = [];
  let table = renames.table;

  for (const [from, to] of renames.tables ?? []) {
    lines.push(`  if to_regclass(${sqlString(`${renames.schema}.${from}`)}) is not null
    and (select c.relkind from pg_class c where c.oid = to_regclass(${sqlString(`${renames.schema}.${from}`)})) in ('r', 'p')
    and to_regclass(${sqlString(`${renames.schema}.${to}`)}) is null then
    alter table ${q(from)} rename to ${sqlIdent(to)};
  end if;`);

    if (from === table) {
      table = to;
    }
  }

  for (const [from, to] of renames.columns ?? []) {
    lines.push(`  if exists (select 1 from information_schema.columns c
      where c.table_schema = ${schema} and c.table_name = ${sqlString(table)} and c.column_name = ${sqlString(from)})
    and not exists (select 1 from information_schema.columns c
      where c.table_schema = ${schema} and c.table_name = ${sqlString(table)} and c.column_name = ${sqlString(to)}) then
    alter table ${q(table)} rename column ${sqlIdent(from)} to ${sqlIdent(to)};
  end if;`);
  }

  for (const [from, to] of renames.indexes ?? []) {
    lines.push(`  if to_regclass(${sqlString(`${renames.schema}.${from}`)}) is not null
    and to_regclass(${sqlString(`${renames.schema}.${to}`)}) is null then
    alter index ${q(from)} rename to ${sqlIdent(to)};
  end if;`);
  }

  for (const [from, to, args] of renames.functions ?? []) {
    lines.push(`  if to_regprocedure(${sqlString(`${renames.schema}.${from}(${args})`)}) is not null
    and to_regprocedure(${sqlString(`${renames.schema}.${to}(${args})`)}) is null then
    alter function ${q(from)}(${args}) rename to ${sqlIdent(to)};
  end if;`);
  }

  if (lines.length === 0) {
    return "";
  }

  return `do $$
begin
${lines.join("\n")}
end;
$$;`;
}

/**
 * A SQL condition true when `organization` names no row of the installed
 * organizations table. False without the organizations module.
 */
export function organizationMissing(
  ctx: ModuleContext,
  organization: string,
): string {
  if (!ctx.installed("organizations")) {
    return "false";
  }

  const organizations = ctx.of("organizations");

  return `not exists (select 1 from ${organizations.table("organizations")} o where o.${organizations.col("organizations", "id")} = ${organization})`;
}

export function membershipDisabledAt(ctx: ModuleContext): string | undefined {
  if (ctx.module !== "tenant" && !ctx.installed("tenant")) {
    return undefined;
  }

  const tenant = ctx.module === "tenant" ? ctx : ctx.of("tenant");

  if (!tenant.has("memberships", "disabledAt")) {
    return undefined;
  }

  if (
    !tenant.manages &&
    typeof tenant.config.columns["memberships"]?.["disabledAt"] !== "string"
  ) {
    return undefined;
  }

  return tenant.col("memberships", "disabledAt");
}

export function activeMembership(ctx: ModuleContext, alias: string): string {
  const column = membershipDisabledAt(ctx);

  return column === undefined ? "" : ` and ${alias}.${column} is null`;
}

export function membershipSuspended(
  ctx: ModuleContext,
  tenant: string,
  user: string,
): string | undefined {
  const column = membershipDisabledAt(ctx);

  if (column === undefined) {
    return undefined;
  }

  const t = ctx.module === "tenant" ? ctx : ctx.of("tenant");

  return `exists (select 1 from ${t.table("memberships")} sm where sm.${t.col("memberships", "tenant")} = ${tenant} and sm.${t.col("memberships", "user")} = ${user} and sm.${column} is not null)`;
}

/**
 * `tenant_disabled(id)` and `user_disabled(uuid)` from
 * `blocks.access.disabled`. Without a column they return false, so callers
 * don't need to know whether it is configured.
 */
export function disabledHelpers(ctx: ModuleContext): string {
  const disabled = ctx.modules.access?.disabled ?? {};
  const id = ctx.idType;
  const organizations = managedOrganizations(ctx);
  let tenantCheck = "false";

  if (disabled.tenant !== undefined) {
    tenantCheck = disabledCheck(
      "blocks.access.disabled.tenant",
      disabled.tenant,
      { key: '"id"', alias: "t", value: "tenant_disabled.tenant" },
    );
  } else if (organizations) {
    tenantCheck = `exists (select 1 from ${organizations.table} t where t.${organizations.id} = tenant_disabled.tenant and (${organizations.flags.map((column) => `t.${column} is not null`).join(" or ")}))`;
  }

  const userCheck =
    disabled.user === undefined
      ? "false"
      : disabledCheck("blocks.access.disabled.user", disabled.user, {
          key: sqlIdent(disabled.userKey ?? "id"),
          alias: "u",
          value: "user_disabled.user_id",
        });

  return `
-- Disabled tenants and users get no permissions and no membership claims
-- (blocks.access.disabled; with the managed organizations module, its
-- disabled_at and deleted_at columns).
create or replace function better_supabase.tenant_disabled(tenant ${id})
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${tenantCheck}
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${userCheck}
$$;

revoke execute on function better_supabase.tenant_disabled(${id}) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_disabled(${id}) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;`;
}

/**
 * Whether `disabledHelpers` reads the managed organizations table, which a
 * later file creates: the caller turns `check_function_bodies` off around it.
 */
/**
 * The condition that `value` is disabled: a set column (`schema.table.column`,
 * matched on `key`), or no active row (an authorization provider's suspension
 * row, where a missing row counts as disabled).
 */
function disabledCheck(
  where: string,
  config: string | DisabledRow,
  match: {
    readonly key: string;
    readonly alias: string;
    readonly value: string;
  },
): string {
  const { alias: d, value } = match;

  if (typeof config === "string") {
    const ref = columnRef(where, config);

    return `exists (select 1 from ${ref.table} ${d} where ${d}.${match.key} = ${value} and ${d}.${ref.column} is not null)`;
  }

  const parts = config.table.split(".");

  if (parts.length !== 2 || parts.some((part) => part.length === 0)) {
    throw new TypeError(
      `${where}.table must be "schema.table", got "${config.table}"`,
    );
  }

  const active = [`${d}.${sqlIdent(config.id)} = ${value}`];

  if (config.disabledAt !== undefined) {
    active.push(`${d}.${sqlIdent(config.disabledAt)} is null`);
  }

  if (config.status !== undefined) {
    if (!config.active || config.active.length === 0) {
      throw new TypeError(`${where}.status needs the active values in active`);
    }

    active.push(
      `${d}.${sqlIdent(config.status)}::text in (${config.active.map(sqlString).join(", ")})`,
    );
  }

  if (config.disabledAt === undefined && config.status === undefined) {
    throw new TypeError(`${where} needs disabledAt, status or both`);
  }

  return `not exists (select 1 from ${parts.map((part) => sqlIdent(part)).join(".")} ${d} where ${active.join(" and ")})`;
}

/**
 * Whether the `access` module's file defines `tenant_disabled` and
 * `user_disabled`: it does whenever it is installed (or configured) outside
 * custom mode, and the `tenant` module's file then leaves them out, so each
 * function is defined in one file.
 */
export function accessDefinesDisabledHelpers(ctx: ModuleContext): boolean {
  const access = ctx.modules.access;

  if (!ctx.installed("access") && access === undefined) {
    return false;
  }

  return (access?.mode ?? "managed") !== "custom";
}

export function disabledHelpersNeedLaterTables(ctx: ModuleContext): boolean {
  return (
    !ctx.modules.access?.disabled?.tenant &&
    managedOrganizations(ctx) !== undefined
  );
}

/**
 * The managed organizations table and its disabling columns, when installed and
 * managed.
 */
function managedOrganizations(
  ctx: ModuleContext,
):
  | {
      readonly table: string;
      readonly id: string;
      readonly flags: readonly string[];
    }
  | undefined {
  if (!ctx.installed("organizations")) {
    return undefined;
  }

  const organizations = ctx.of("organizations");

  if (!organizations.manages) {
    return undefined;
  }

  const flags = ["disabledAt", "deletedAt"]
    .filter((logical) => organizations.has("organizations", logical))
    .map((logical) => organizations.col("organizations", logical));

  if (flags.length === 0) {
    return undefined;
  }

  return {
    table: organizations.table("organizations"),
    id: organizations.col("organizations", "id"),
    flags,
  };
}

/**
 * Another row trigger on `target` whose function name matches `pattern` does
 * the module trigger's job twice. `track_*` warns about it, or drops it with
 * `replace_trigger => true`.
 */
export const EQUIVALENT_TRIGGERS = `
create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;`;

/**
 * A `pg_jsonschema` check on a jsonb column, for the `jsonb-schemas` module and
 * key-value tables.
 */
export interface JsonSchemaCheck {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly schema: Readonly<Record<string, unknown>>;
  /**
   * Checks only rows whose `where.column` equals `where.value` (a settings
   * key).
   */
  readonly where?: { readonly column: string; readonly value: string };
}

/** FNV-1a, as 8 hex digits: a stable suffix that keeps two names apart. */
function shortHash(text: string): string {
  let hash = 0x81_1c_9d_c5;

  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.codePointAt(index) ?? 0;
    hash = Math.imul(hash, 0x01_00_01_93) >>> 0;
  }

  return hash.toString(16).padStart(8, "0");
}

/**
 * Adds CHECK `name` on `table` (quoted) unless a re-run finds it already
 * checking `expression`: the constraint comment records a hash of the
 * expression, so an unchanged check skips the table scan under ACCESS
 * EXCLUSIVE. `notValid` leaves existing rows unchecked.
 */
export function ensureCheck(
  table: string,
  name: string,
  expression: string,
  options: { readonly notValid?: boolean } = {},
): string {
  const marker = sqlString(
    `better-supabase check ${shortHash(`${expression}|${options.notValid === true}`)}`,
  );

  const constraint = sqlIdent(name);

  return `do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = ${sqlString(table)}::regclass and c.conname = ${sqlString(name)}
  ), 'pg_constraint'), '') <> ${marker} then
    alter table ${table} drop constraint if exists ${constraint};
    alter table ${table} add constraint ${constraint} check (${expression})${options.notValid === true ? " not valid" : ""};
    comment on constraint ${constraint} on ${table} is ${marker};
  end if;
end;
$$;`;
}

/**
 * The constraint and trigger name of a check. A key that sanitizing or the
 * 63-byte limit would change (`notify.email`, `notify-email`, a long key) gets
 * a hash of the key, so two keys never share a name and drop each other's
 * check.
 */
function jsonCheckName(check: JsonSchemaCheck): string {
  const base = `bsb_json_${check.column}`;

  if (!check.where) {
    return base.slice(0, 63);
  }

  const key = check.where.value;
  const clean = key.replaceAll(/[^a-z0-9_]/gi, "_");
  const plain = `${base}_${clean}`;

  if (clean === key && plain.length <= 63) {
    return plain;
  }

  return `${plain.slice(0, 54)}_${shortHash(key)}`;
}

export function jsonSchemaChecks(checks: readonly JsonSchemaCheck[]): string {
  if (checks.length === 0) {
    return "";
  }

  const statements = checks.map((check) => {
    const target = quotedTable(check.table);
    const name = sqlIdent(jsonCheckName(check));
    const schemaText = sqlString(JSON.stringify(check.schema));
    const matches = `extensions.jsonb_matches_schema(${schemaText}::json, ${sqlIdent(check.column)})`;

    const columns = check.where
      ? `${sqlIdent(check.column)}, ${sqlIdent(check.where.column)}`
      : sqlIdent(check.column);

    const args = [
      sqlString(check.column),
      schemaText,
      ...(check.where
        ? [sqlString(check.where.column), sqlString(check.where.value)]
        : []),
    ].join(", ");

    return [
      `alter table ${target} drop constraint if exists ${name};`,
      `alter table ${target} add constraint ${name}`,
      `  check (${check.where ? `${sqlIdent(check.where.column)} <> ${sqlString(check.where.value)} or ` : ""}${matches}) not valid;`,
      `alter table ${target} validate constraint ${name};`,
      `drop trigger if exists ${name} on ${target};`,
      `create trigger ${name} before insert or update of ${columns} on ${target}`,
      `  for each row execute function better_supabase.check_json_schema(${args});`,
    ].join("\n");
  });

  return `\n-- config.json schemas
-- Each check is added not valid and validated separately. On a large table,
-- move the validate statements to a later migration: adding a not valid check
-- blocks writes only briefly, and validating takes a lock that lets writes
-- continue. The trigger of the same name reports which part of the schema failed.
${statements.join("\n\n")}\n`;
}

/** SQL that takes every privilege on a table from `anon` and `authenticated`. */
export const revokeTable = (table: string): string =>
  `revoke all on ${table} from anon, authenticated;`;

/**
 * One policy per command for rows `authenticated` owns. A permissive `for all`
 * policy would also grant writes on its own, so the read-only actor check
 * (which wraps only insert, update and delete policies) could never refuse
 * them. `legacy` is the name of the `for all` policy this replaces.
 */
export function ownRowPolicies(options: {
  readonly table: string;
  readonly legacy: string;
  readonly name: (command: "read" | "insert" | "update" | "delete") => string;
  readonly using: string;
  readonly check: string;
}): string {
  const { table, legacy, name, using, check } = options;

  const create = (
    command: "read" | "insert" | "update" | "delete",
    body: string,
  ): string => `drop policy if exists ${sqlIdent(name(command))} on ${table};
create policy ${sqlIdent(name(command))} on ${table} ${body};`;

  return [
    `drop policy if exists ${sqlIdent(legacy)} on ${table};`,
    create("read", `for select to authenticated using (${using})`),
    create("insert", `for insert to authenticated with check (${check})`),
    create(
      "update",
      `for update to authenticated using (${using}) with check (${check})`,
    ),
    create("delete", `for delete to authenticated using (${using})`),
  ].join("\n");
}

/**
 * SQL that turns on RLS for a table the module manages, takes it from `anon`
 * and `authenticated` and gives it to the service role. `read` grants `select`
 * back to `authenticated`, for tables its policies expose.
 */
export const lockTable = (
  table: string,
  options: { readonly read?: boolean } = {},
): string => `alter table ${table} enable row level security;
${revokeTable(table)}
${options.read ? `grant select on ${table} to authenticated;\n` : ""}grant all on ${table} to service_role;`;

/**
 * Monthly range partitions for any table created `partition by range` on a
 * timestamptz column: a registry, `ensure_partitions(parent, months_ahead)`,
 * which creates `<parent>_pYYYYMM` for this month and the next ones (UTC
 * bounds) with RLS on and the client roles revoked, `maintain_partitions()` for
 * every registered table, and `expired_partitions(parent, cutoff)`, the
 * partitions wholly before `cutoff`. A table that isn't partitioned (one
 * created before the option) is left alone.
 */
export const MONTHLY_PARTITIONS: string = `create table if not exists better_supabase.partitioned_tables (
  parent regclass primary key,
  months_ahead integer not null default 3 check (months_ahead between 1 and 24)
);
${lockTable("better_supabase.partitioned_tables")}

create or replace function better_supabase.ensure_partitions(parent regclass, months_ahead integer default 3)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schema text;
  v_name text;
  v_month timestamp := date_trunc('month', now() at time zone 'UTC');
  v_part text;
  v_made integer := 0;
begin
  select n.nspname, c.relname into v_schema, v_name
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where c.oid = parent and c.relkind = 'p';
  if v_name is null then
    return 0;
  end if;
  for i in 0..months_ahead loop
    v_part := v_name || '_p' || to_char(v_month + make_interval(months => i), 'YYYYMM');
    continue when pg_catalog.to_regclass(format('%I.%I', v_schema, v_part)) is not null;
    begin
      execute format(
        'create table %I.%I partition of %s for values from (%L) to (%L)',
        v_schema, v_part, parent,
        (v_month + make_interval(months => i)) at time zone 'UTC',
        (v_month + make_interval(months => i + 1)) at time zone 'UTC'
      );
    exception when check_violation then
      -- The default partition already holds rows of that month.
      raise notice '% not created: the default partition has rows in its range', v_part;
      continue;
    end;
    execute format('alter table %I.%I enable row level security', v_schema, v_part);
    execute format('revoke all on %I.%I from anon, authenticated', v_schema, v_part);
    v_made := v_made + 1;
  end loop;
  return v_made;
end;
$$;

create or replace function better_supabase.maintain_partitions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_made integer := 0;
  v_table record;
begin
  for v_table in select t.parent, t.months_ahead from better_supabase.partitioned_tables t loop
    v_made := v_made + better_supabase.ensure_partitions(v_table.parent, v_table.months_ahead);
  end loop;
  return v_made;
end;
$$;

create or replace function better_supabase.expired_partitions(parent regclass, cutoff timestamptz)
returns setof regclass
language sql
stable
security definer
set search_path = ''
as $$
  select c.oid::regclass
  from pg_catalog.pg_inherits i
  join pg_catalog.pg_class c on c.oid = i.inhrelid
  where i.inhparent = parent
    and c.relname ~ '_p[0-9]{6}$'
    and cutoff is not null
    and (to_date(right(c.relname, 6), 'YYYYMM')::timestamp + interval '1 month') at time zone 'UTC' <= cutoff
  order by c.relname
$$;
revoke execute on function better_supabase.ensure_partitions(regclass, integer) from public, anon, authenticated;
revoke execute on function better_supabase.maintain_partitions() from public, anon, authenticated;
revoke execute on function better_supabase.expired_partitions(regclass, timestamptz) from public, anon, authenticated;
grant execute on function better_supabase.maintain_partitions() to service_role;`;

/**
 * SQL that registers a partitioned table for `maintain_partitions()` and
 * creates its first partitions.
 */
export const registerPartitions = (table: string, monthsAhead = 3): string =>
  `insert into better_supabase.partitioned_tables (parent, months_ahead)
select ${sqlString(table)}::regclass, ${monthsAhead}
where exists (select 1 from pg_catalog.pg_class c where c.oid = ${sqlString(table)}::regclass and c.relkind = 'p')
on conflict (parent) do nothing;
select better_supabase.ensure_partitions(${sqlString(table)}::regclass, ${monthsAhead});`;

/**
 * The quoted name of a table's default partition: `<name>_default` in its
 * schema.
 */
export const defaultPartitionName = (table: {
  readonly schema: string;
  readonly name: string;
}): string => `${sqlIdent(table.schema)}.${sqlIdent(`${table.name}_default`)}`;

/**
 * SQL that gives a partitioned `table` its `fallback` default partition, for
 * rows outside the monthly ones. A table created unpartitioned is skipped.
 */
export const defaultPartition = (table: string, fallback: string): string =>
  `do $$
begin
  if (select c.relkind from pg_catalog.pg_class c where c.oid = ${sqlString(table)}::regclass) = 'p' then
    create table if not exists ${fallback} partition of ${table} default;
    alter table ${fallback} enable row level security;
    revoke all on ${fallback} from anon, authenticated;
  end if;
end;
$$;`;

/** One argument of a batched function: the key in each element and its type. */
export type BatchArgument = readonly [
  name: string,
  type: string,
  fallback?: string,
];

/**
 * A security definer function that runs `call` once per element of a jsonb
 * array, so a sink sends a whole batch in one round trip. Every element keeps
 * the single-row function's checks and gets its own savepoint: it returns
 * `{"<result>": value}` or `{"error": {code, message, hint}}`, in order, and
 * one bad event never rolls back the others. More than `max` elements fail with
 * 22023 before any is written. The caller adds the grants.
 */
export function batchFunction(options: {
  readonly name: string;
  readonly call: string;
  /** The keys of each element, or the one jsonb parameter that takes it whole. */
  readonly args: readonly BatchArgument[] | string;
  readonly returns: string;
  readonly result: string;
  readonly hint: string;
  readonly max?: number;
}): string {
  const max = options.max ?? MAX_BATCH;

  const value = ([name, type, fallback]: BatchArgument): string => {
    const raw =
      type === "jsonb"
        ? `nullif(batch_event -> ${sqlString(name)}, 'null'::jsonb)`
        : type === "text"
          ? `batch_event ->> ${sqlString(name)}`
          : `(batch_event ->> ${sqlString(name)})::${type}`;

    return fallback === undefined ? raw : `coalesce(${raw}, ${fallback})`;
  };

  return `create or replace function ${options.name}(events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  batch_event jsonb;
  results jsonb := '[]';
  batch_result ${options.returns};
  failed_state text;
  failed_message text;
  failed_hint text;
begin
  if pg_catalog.jsonb_typeof(events) is distinct from 'array' then
    raise exception '${options.name.replace(/^.*\./, "")} takes a jsonb array of events'
      using errcode = '22023', hint = ${sqlString(`${options.hint}_NOT_ARRAY`)};
  end if;
  if pg_catalog.jsonb_array_length(events) > ${max} then
    raise exception '${options.name.replace(/^.*\./, "")} got % events, more than ${max}', pg_catalog.jsonb_array_length(events)
      using errcode = '22023', hint = ${sqlString(`${options.hint}_TOO_LARGE`)};
  end if;
  for batch_event in select e from pg_catalog.jsonb_array_elements(events) e loop
    begin
      batch_result := ${options.call}(
${
  typeof options.args === "string"
    ? `        ${options.args} => batch_event`
    : options.args
        .map((arg) => `        ${arg[0]} => ${value(arg)}`)
        .join(",\n")
}
      );
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(${sqlString(options.result)}, batch_result));
    exception when others then
      get stacked diagnostics
        failed_state = returned_sqlstate,
        failed_message = message_text,
        failed_hint = pg_exception_hint;
      results := results || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'error', pg_catalog.jsonb_build_object('code', failed_state, 'message', failed_message, 'hint', nullif(failed_hint, ''))
      ));
    end;
  end loop;
  return results;
end;
$$;`;
}

/** The PL/pgSQL variables `dropExpiredPartitions` uses, for a `declare` block. */
export const PARTITION_VARIABLES = `
  v_part regclass;
  v_part_rows integer;
  v_part_busy boolean;`;

/**
 * PL/pgSQL that drops each monthly partition of `table` wholly before `cutoff`
 * (null drops none, as `ctx.cutoff` returns under a legal hold) and adds its
 * rows to `purged`. A partition with a row that matches `busy` (a condition
 * over `p`, with `$1`.. bound to `using`) stays for the row deletes, so a purge
 * never drops a row it would keep. Declare `PARTITION_VARIABLES` first.
 */
export function dropExpiredPartitions(options: {
  readonly table: string;
  readonly cutoff: string;
  readonly purged: string;
  readonly busy?: string;
  readonly using?: readonly string[];
  readonly indent?: string;
}): string {
  const indent = options.indent ?? "  ";
  const literal = (sql: string) => sql.replaceAll("'", "''");

  const busy =
    options.busy === undefined
      ? ""
      : `
${indent}  execute format('select exists (select 1 from %s p where ${literal(options.busy).replaceAll("%", "%%")})', v_part) into v_part_busy${
          options.using && options.using.length > 0
            ? ` using ${options.using.join(", ")}`
            : ""
        };
${indent}  continue when v_part_busy;`;

  return `for v_part in
${indent}  select p from better_supabase.expired_partitions(${sqlString(options.table)}::regclass, ${options.cutoff}) p
${indent}loop${busy}
${indent}  execute format('select count(*)::integer from %s', v_part) into v_part_rows;
${indent}  execute format('drop table %s', v_part);
${indent}  ${options.purged} := ${options.purged} + v_part_rows;
${indent}end loop;`;
}

/** SQL that grants a function to signed-in users and the service role. */
export const userGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

/** SQL that grants a function to the service role only. */
export const serviceGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;

/**
 * SQL that revokes a trigger function from every API role. Postgres checks
 * `execute` only when the trigger is created, never when it fires, so the
 * trigger keeps working while the function can't be called through RPC.
 */
export const triggerGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon, authenticated;`;

/**
 * `serviceGrant` for each function in `schema` (as SQL, e.g. `ctx.schema`), one
 * statement per function, so `blocks.<module>.api` sees the grants and writes
 * an entry point for each.
 */
export function serviceOnly(
  signatures: readonly string[],
  schema = "better_supabase",
): string {
  return signatures
    .map((signature) => serviceGrant(`${schema}.${signature}`))
    .join("\n");
}

/**
 * `raise exception` with an errcode and, when given, a hint the TypeScript side
 * maps. Sites that put `using` on its own line, raise without an errcode or
 * compute the hint stay inline: this one-line form would change SQL apps have
 * generated.
 */
export const raise = (
  message: string,
  errcode: string,
  hint?: string,
  ...args: readonly string[]
): string =>
  `raise exception ${sqlString(message)}${args.map((arg) => `, ${arg}`).join("")} using errcode = '${errcode}'${hint === undefined ? "" : `, hint = '${hint}'`};`;

/**
 * `raise` for a module function: the hint first, the errcode defaulting to
 * insufficient privilege.
 */
export const fail = (
  code: string,
  message: string,
  errcode = "42501",
): string => raise(message, errcode, code);

/** The hex SHA-256 of a `text` expression, as tokens and codes are stored. */
export const sha256Hex = (value: string): string =>
  `encode(extensions.digest(${value}, 'sha256'), 'hex')`;

/** A page size: `value`, or `fallback` when null, clamped to `min`..`max`. */
export const pageSize = (
  value: string,
  fallback: number,
  max: number,
  min = 1,
): string =>
  `least(greatest(coalesce(${value}, ${String(fallback)}), ${String(min)}), ${String(max)})`;

/**
 * A row trigger that records writes to a table that callers change through
 * `security invoker` functions or policies, which can't call `emit_event` or
 * `audit_event` themselves. `written` and `removed` are `ctx.record` statements
 * over `v_row`, the new row (or the old one on delete). When both are `null;`
 * the trigger and its function are dropped.
 */
export function recordTrigger(
  ctx: ModuleContext,
  options: {
    readonly name: string;
    readonly table: string;
    readonly written: string;
    readonly removed: string;
  },
): string {
  const fn = ctx.fn(options.name);
  const trigger = ctx.trigger(options.name);

  if (options.written === NOTHING && options.removed === NOTHING) {
    return `drop trigger if exists ${trigger} on ${options.table};
drop function if exists ${fn}();`;
  }

  return `create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${options.table};
begin
  if tg_op = 'DELETE' then
    v_row := old;
    ${options.removed}
  else
    v_row := new;
    ${options.written}
  end if;
  return null;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${options.table};
create trigger ${trigger} after insert or update or delete on ${options.table}
  for each row execute function ${fn}();`;
}
