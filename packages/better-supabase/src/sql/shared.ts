import type { KitContext } from "./context.ts";

import { sqlIdent, sqlString } from "../core/template.ts";

export const SCHEMA = `create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;`;

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
  return `
-- Disabled tenants and users get no permissions and no membership claims
-- (kits.access.disabled).
create or replace function better_supabase.tenant_disabled(tenant ${id})
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${tenant ? `exists (select 1 from ${tenant.table} t where t.${tenantKey} = tenant_disabled.tenant and t.${tenant.column} is not null)` : "false"}
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

revoke execute on function better_supabase.tenant_disabled(${id}) from public, anon;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon;
grant execute on function better_supabase.tenant_disabled(${id}) to authenticated, service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to authenticated, service_role, supabase_auth_admin;`;
}

/**
 * Calls the app's `<schema>.<name>(args)` when it exists, so modules expose
 * `before_*` and `after_*` hooks without the app having to define them.
 * `args` are SQL expressions; `types` their types, for the lookup.
 */
export function sqlHook(
  ctx: KitContext,
  name: string,
  args: readonly { readonly sql: string; readonly type: string }[],
): string {
  const signature = `${ctx.schemaName}.${name}(${args.map((arg) => arg.type).join(", ")})`;
  return `if to_regprocedure(${sqlString(signature)}) is not null then
    execute format('select %s(${args.map((_, index) => `$${String(index + 1)}`).join(", ")})', ${sqlString(`${ctx.schema}.${sqlIdent(name)}`)})${args.length > 0 ? ` using ${args.map((arg) => arg.sql).join(", ")}` : ""};
  end if;`;
}

/**
 * Appends to the outbox when the `outbox` module is installed (`emit_event`
 * is looked up at run time, so the module stays optional).
 */
export function emitEvent(
  type: string,
  tenant: string,
  subject: string,
  data: string,
): string {
  return `if to_regprocedure('better_supabase.emit_event(text, text, text, jsonb, text)') is not null then
    perform better_supabase.emit_event(${sqlString(type)}, ${tenant}::text, ${subject}::text, ${data}, null);
  end if;`;
}
