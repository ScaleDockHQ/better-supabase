import type { KitContext } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

export const SCHEMA = `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`;

/**
 * A SQL condition true for the service role and for a direct admin
 * connection (no JWT, a privileged session user), which may act for others.
 */
export const SERVICE_CALLER =
  "coalesce(nullif(auth.jwt() ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')";

/** Creates the module's schema when it isn't `better_supabase`, then the kit schema. */
export function schemaPreamble(ctx: KitContext): string {
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
 * `tenant_disabled(id)` and `user_disabled(uuid)` from
 * `kits.access.disabled`. Without a column they return false, so callers
 * don't need to know whether it is configured.
 */
export function disabledHelpers(ctx: KitContext): string {
  const disabled = ctx.kits.access?.disabled ?? {};
  const id = ctx.idType;
  const tenant = disabled.tenant
    ? columnRef("kits.access.disabled.tenant", disabled.tenant)
    : undefined;
  const user = disabled.user
    ? columnRef("kits.access.disabled.user", disabled.user)
    : undefined;
  const tenantKey = sqlIdent(disabled.tenantKey ?? "id");
  const userKey = sqlIdent(disabled.userKey ?? "id");
  const orgs = managedOrganizations(ctx);
  let tenantCheck = "false";
  if (tenant) {
    tenantCheck = `exists (select 1 from ${tenant.table} t where t.${tenantKey} = tenant_disabled.tenant and t.${tenant.column} is not null)`;
  } else if (orgs) {
    tenantCheck = `exists (select 1 from ${orgs.table} t where t.${orgs.id} = tenant_disabled.tenant and (${orgs.flags.map((column) => `t.${column} is not null`).join(" or ")}))`;
  }
  return `
-- Disabled tenants and users get no permissions and no membership claims
-- (kits.access.disabled; with the managed organizations module, its
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
export function disabledHelpersNeedLaterTables(ctx: KitContext): boolean {
  return (
    !ctx.kits.access?.disabled?.tenant &&
    managedOrganizations(ctx) !== undefined
  );
}

/** The managed organizations table and its disabling columns, when installed and managed. */
function managedOrganizations(ctx: KitContext):
  | {
      readonly table: string;
      readonly id: string;
      readonly flags: readonly string[];
    }
  | undefined {
  if (!ctx.installed("organizations")) return undefined;
  const orgs = ctx.of("organizations");
  if (!orgs.manages) return undefined;
  const flags = ["disabledAt", "deletedAt"]
    .filter((logical) => orgs.has("organizations", logical))
    .map((logical) => orgs.col("organizations", logical));
  if (flags.length === 0) return undefined;
  return {
    table: orgs.table("organizations"),
    id: orgs.col("organizations", "id"),
    flags,
  };
}

/**
 * Another row trigger on `target` whose function name matches `pattern` does
 * the kit trigger's job twice. `track_*` warns about it, or drops it with
 * `replace_trigger => true`.
 */
export const EQUIVALENT_TRIGGERS = `
create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  kit_trigger text,
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
      and t.tgname <> replace_equivalent_triggers.kit_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, kit_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;`;
