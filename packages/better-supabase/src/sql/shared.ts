import type { BlockContext } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

export const SCHEMA = `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`;

/**
 * A SQL condition true for the service role and for a direct admin
 * connection (no JWT, a privileged session user), which may act for others.
 */
export const SERVICE_CALLER =
  "coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')";

/** Creates the module's schema when it isn't `better_supabase`, then the block schema. */
export function schemaPreamble(ctx: BlockContext): string {
  if (ctx.schemaName === "better_supabase") return SCHEMA;
  return `${SCHEMA}
create schema if not exists ${ctx.schema};
grant usage on schema ${ctx.schema} to anon, authenticated, service_role;`;
}

/** A claim from the top level of the token, then `app_metadata`. */
export function jwtClaim(name: string): string {
  return `coalesce(auth.jwt() ->> ${sqlString(name)}, auth.jwt() -> 'app_metadata' ->> ${sqlString(name)})`;
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
 * Upgrade-step renames for a block table in `schema`. Each runs only while the
 * old name exists and the new one doesn't, so a step can run again.
 */
export interface BlockRenames {
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

export function renameSql(renames: BlockRenames): string {
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
  ctx: BlockContext,
  organization: string,
): string {
  if (!ctx.installed("organizations")) return "false";
  const organizations = ctx.of("organizations");
  return `not exists (select 1 from ${organizations.table("organizations")} o where o.${organizations.col("organizations", "id")} = ${organization})`;
}

/**
 * `tenant_disabled(id)` and `user_disabled(uuid)` from
 * `blocks.access.disabled`. Without a column they return false, so callers
 * don't need to know whether it is configured.
 */
export function disabledHelpers(ctx: BlockContext): string {
  const disabled = ctx.blocks.access?.disabled ?? {};
  const id = ctx.idType;
  const tenant = disabled.tenant
    ? columnRef("blocks.access.disabled.tenant", disabled.tenant)
    : undefined;
  const user = disabled.user
    ? columnRef("blocks.access.disabled.user", disabled.user)
    : undefined;
  const userKey = sqlIdent(disabled.userKey ?? "id");
  const organizations = managedOrganizations(ctx);
  let tenantCheck = "false";
  if (tenant) {
    tenantCheck = `exists (select 1 from ${tenant.table} t where t."id" = tenant_disabled.tenant and t.${tenant.column} is not null)`;
  } else if (organizations) {
    tenantCheck = `exists (select 1 from ${organizations.table} t where t.${organizations.id} = tenant_disabled.tenant and (${organizations.flags.map((column) => `t.${column} is not null`).join(" or ")}))`;
  }
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
  select ${user ? `exists (select 1 from ${user.table} u where u.${userKey} = user_disabled.user_id and u.${user.column} is not null)` : "false"}
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
export function disabledHelpersNeedLaterTables(ctx: BlockContext): boolean {
  return (
    !ctx.blocks.access?.disabled?.tenant &&
    managedOrganizations(ctx) !== undefined
  );
}

/** The managed organizations table and its disabling columns, when installed and managed. */
function managedOrganizations(ctx: BlockContext):
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
 * the block trigger's job twice. `track_*` warns about it, or drops it with
 * `replace_trigger => true`.
 */
export const EQUIVALENT_TRIGGERS = `
create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  block_trigger text,
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
      and t.tgname <> replace_equivalent_triggers.block_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, block_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;`;
