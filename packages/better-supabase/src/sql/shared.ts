import type { DisabledRow } from "../config/modules.ts";
import type { ModuleContext } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

/** What `record` and the other statement helpers return when there is nothing to do. */
export const NOTHING = "null;";

export const SCHEMA = `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`;

/**
 * A SQL condition true for the service role and for a direct admin
 * connection (no JWT, a privileged session user), which may act for others.
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

/** Creates the module's schema when it isn't `better_supabase`, then the module schema. */
export function schemaPreamble(ctx: ModuleContext): string {
  if (ctx.schemaName === "better_supabase") return SCHEMA;
  return `${SCHEMA}
create schema if not exists ${ctx.schema};
grant usage on schema ${ctx.schema} to anon, authenticated, service_role;`;
}

/**
 * A policy condition for "the caller holds `permission` in this row's
 * tenant". Postgres never inlines `can()` (it is `security definer`), so a
 * `can('tenant', column, ...)` in `using` runs once per row and can't use the
 * tenant index; the `tenant_ids_with` set runs once per statement.
 */
export function tenantIn(tenant: string, permission: string): string {
  return `${tenant} in (select better_supabase.tenant_ids_with(${permission}))`;
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
 * earlier: `create table if not exists` never changes an inline check, and
 * its generated name follows the table's configured name. For upgrade steps.
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
 * Adds a foreign key to a table a module created earlier, once: `create
 * table if not exists` can't add it to a table that already exists, and the
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
 * An `updated_at` column on a managed table, kept current by the
 * `updated-at` module's `set_updated_at()` (the module must require it).
 */
export function updatedAt(table: string, column: string): string {
  return `alter table ${table} add column if not exists ${column} timestamptz not null default now();
drop trigger if exists bs_updated_at on ${table};
create trigger bs_updated_at before update on ${table}
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
    if (from === table) table = to;
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
  if (lines.length === 0) return "";
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
  if (!ctx.installed("organizations")) return "false";
  const organizations = ctx.of("organizations");
  return `not exists (select 1 from ${organizations.table("organizations")} o where o.${organizations.col("organizations", "id")} = ${organization})`;
}

export function membershipDisabledAt(ctx: ModuleContext): string | undefined {
  if (ctx.module !== "tenant" && !ctx.installed("tenant")) return undefined;
  const tenant = ctx.module === "tenant" ? ctx : ctx.of("tenant");
  if (!tenant.has("memberships", "disabledAt")) return undefined;
  if (
    !tenant.manages &&
    typeof tenant.config.columns["memberships"]?.["disabledAt"] !== "string"
  )
    return undefined;
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
  if (column === undefined) return undefined;
  const t = ctx.module === "tenant" ? ctx : ctx.of("tenant");
  return `exists (select 1 from ${t.table("memberships")} sm where sm.${t.col("memberships", "tenant")} = ${tenant} and sm.${t.col("memberships", "user")} = ${user} and sm.${column} is not null)`;
}

/**
 * `tenant_disabled(id)` and `user_disabled(uuid)` from
 * `sql.modules.access.disabled`. Without a column they return false, so callers
 * don't need to know whether it is configured.
 */
export function disabledHelpers(ctx: ModuleContext): string {
  const disabled = ctx.modules.access?.disabled ?? {};
  const id = ctx.idType;
  const organizations = managedOrganizations(ctx);
  let tenantCheck = "false";
  if (disabled.tenant !== undefined) {
    tenantCheck = disabledCheck(
      "sql.modules.access.disabled.tenant",
      disabled.tenant,
      { key: '"id"', alias: "t", value: "tenant_disabled.tenant" },
    );
  } else if (organizations) {
    tenantCheck = `exists (select 1 from ${organizations.table} t where t.${organizations.id} = tenant_disabled.tenant and (${organizations.flags.map((column) => `t.${column} is not null`).join(" or ")}))`;
  }
  const userCheck =
    disabled.user === undefined
      ? "false"
      : disabledCheck("sql.modules.access.disabled.user", disabled.user, {
          key: sqlIdent(disabled.userKey ?? "id"),
          alias: "u",
          value: "user_disabled.user_id",
        });
  return `
-- Disabled tenants and users get no permissions and no membership claims
-- (modules.access.disabled; with the managed organizations module, its
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
 * matched on `key`), or no active row (an authorization provider's
 * suspension row, where a missing row counts as disabled).
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
  if (config.disabledAt !== undefined)
    active.push(`${d}.${sqlIdent(config.disabledAt)} is null`);
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
  if (!ctx.installed("access") && access === undefined) return false;
  return (access?.mode ?? "managed") !== "custom";
}

export function disabledHelpersNeedLaterTables(ctx: ModuleContext): boolean {
  return (
    !ctx.modules.access?.disabled?.tenant &&
    managedOrganizations(ctx) !== undefined
  );
}

/** The managed organizations table and its disabling columns, when installed and managed. */
function managedOrganizations(ctx: ModuleContext):
  | {
      readonly table: string;
      readonly id: string;
      readonly flags: readonly string[];
    }
  | undefined {
  if (!ctx.installed("organizations")) return undefined;
  const organizations = ctx.of("organizations");
  if (!organizations.manages) return undefined;
  const flags = ["disabledAt", "deletedAt"]
    .filter((logical) => organizations.has("organizations", logical))
    .map((logical) => organizations.col("organizations", logical));
  if (flags.length === 0) return undefined;
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

/** A `pg_jsonschema` check on a jsonb column, for the `jsonb-schemas` module and key-value tables. */
export interface JsonSchemaCheck {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly schema: Readonly<Record<string, unknown>>;
  /** Checks only rows whose `where.column` equals `where.value` (a settings key). */
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
 * 63-byte limit would change (`notify.email`, `notify-email`, a long key)
 * gets a hash of the key, so two keys never share a name and drop each
 * other's check.
 */
function jsonCheckName(check: JsonSchemaCheck): string {
  const base = `bs_json_${check.column}`;
  if (!check.where) return base.slice(0, 63);
  const key = check.where.value;
  const clean = key.replaceAll(/[^a-z0-9_]/gi, "_");
  const plain = `${base}_${clean}`;
  if (clean === key && plain.length <= 63) return plain;
  return `${plain.slice(0, 54)}_${shortHash(key)}`;
}

export function jsonSchemaChecks(checks: readonly JsonSchemaCheck[]): string {
  if (checks.length === 0) return "";
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

/** SQL that grants a function to signed-in users and the service role. */
export const userGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon;
grant execute on function ${signature} to authenticated, service_role;`;

/** SQL that grants a function to the service role only. */
export const serviceGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;

/**
 * `serviceGrant` for each function in `schema` (as SQL, e.g. `ctx.schema`),
 * one statement per function, so `sql.modules.<module>.api` sees the grants
 * and writes an entry point for each.
 */
export function serviceOnly(
  signatures: readonly string[],
  schema = "better_supabase",
): string {
  return signatures
    .map((signature) => serviceGrant(`${schema}.${signature}`))
    .join("\n");
}

/** `raise exception` with an errcode and a hint the TypeScript side maps. */
export const raise = (
  message: string,
  errcode: string,
  hint: string,
  ...args: readonly string[]
): string =>
  `raise exception ${sqlString(message)}${args.map((arg) => `, ${arg}`).join("")} using errcode = '${errcode}', hint = '${hint}';`;

/** `coalesce(can('tenant', tenant, permission), false)`. */
export const canIn = (tenant: string, permission: string): string =>
  `coalesce(better_supabase.can('tenant', ${tenant}, ${permission}), false)`;

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
 * `audit_event` themselves. `written` and `removed` are `ctx.record`
 * statements over `v_row`, the new row (or the old one on delete). When
 * both are `null;` the trigger and its function are dropped.
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
