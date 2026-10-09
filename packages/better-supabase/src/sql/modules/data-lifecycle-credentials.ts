import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleTableLifecycle,
} from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { refOutsideTenant } from "./credentials.ts";

/** The columns an export leaves out: `omit` and the credential refs. */
export function exportOmits(
  lifecycle: ModuleTableLifecycle | undefined,
): readonly string[] {
  return [
    ...new Set([...(lifecycle?.omit ?? []), ...(lifecycle?.credentials ?? [])]),
  ];
}

export const CREDENTIALS_CONTRACT: readonly ModuleContractFunction[] = [
  { name: "data_lifecycle_credentials", args: [], returns: "record" },
  { name: "organization_credential_refs", args: ["{id}"], returns: "jsonb" },
];

/** A `credential_ref` column of an installed module's table. */
interface CredentialColumn {
  /** `schema.table`, unquoted, as in `data_lifecycle_tables`. */
  readonly name: string;
  readonly table: string;
  /** Unquoted, for `%I`. */
  readonly column: string;
  /** The user column to revoke for, unquoted; unset to revoke for the app. */
  readonly user: string | undefined;
}

function credentialColumns(ctx: ModuleContext): readonly CredentialColumn[] {
  const list: CredentialColumn[] = [];
  for (const of of ctx.installedModules.map((module) => ctx.of(module))) {
    for (const [logical, spec] of Object.entries(of.names.tables)) {
      const lifecycle = spec.lifecycle;
      if (lifecycle?.credentials === undefined || !of.hasTable(logical)) {
        continue;
      }
      const user =
        lifecycle.credentialSubject === "user" &&
        lifecycle.user !== undefined &&
        of.has(logical, lifecycle.user)
          ? of.col(logical, lifecycle.user).replaceAll('"', "")
          : undefined;
      if (lifecycle.credentialSubject === "user" && user === undefined) {
        throw new TypeError(
          `${of.module}.${logical}: credentialSubject "user" needs a lifecycle user column`,
        );
      }
      for (const column of lifecycle.credentials) {
        if (!of.has(logical, column)) continue;
        list.push({
          name: `${of.tableName(logical).schema}.${of.tableName(logical).name}`,
          table: of.table(logical),
          column: of.col(logical, column).replaceAll('"', ""),
          user,
        });
      }
    }
  }
  return list;
}

/**
 * `data_lifecycle_credentials()` and `organization_credential_refs(tenant)`,
 * which list the refs in the rows a due purge deletes for the purger to
 * revoke first.
 */
export function credentialsSql(ctx: ModuleContext): string {
  const id = ctx.idType;
  const d = ctx.table("deletions");
  const cd = (logical: string): string => ctx.col("deletions", logical);
  const fn = (name: string): string => ctx.fn(name);
  const credentials = credentialColumns(ctx);
  const credentialsBody =
    credentials.length === 0
      ? "select null::text, null::text, null::text, null::text where false"
      : `select * from (values\n    ${credentials
          .map(
            (entry) =>
              `(${sqlString(entry.name)}, ${sqlString(entry.table)}, ${sqlString(entry.column)}, ${entry.user === undefined ? "null::text" : sqlString(entry.user)})`,
          )
          .join(",\n    ")}\n  ) as c(name, tbl, col, user_col)`;
  const inTenant = `not (${refOutsideTenant("r.ref", "$1")})`.replaceAll(
    "'",
    "''",
  );
  return `-- The credential_ref columns of module tables: display name, quoted table,
-- column and the user column a ref is revoked for (null for the app).
drop function if exists ${fn("data_lifecycle_credentials")}();
create or replace function ${fn("data_lifecycle_credentials")}()
returns table (name text, tbl text, col text, user_col text)
language sql
immutable
set search_path = ''
as $$
  ${credentialsBody}
$$;

-- The credential_refs in the rows a due purge deletes (service role), for
-- the purger to revoke through its CredentialProvider first. in_tenant is
-- false for a ref that doesn't carry the organization; those stay unrevoked.
create or replace function ${fn("organization_credential_refs")}(tenant ${id})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_entry record;
  v_type text;
  v_refs jsonb;
  v_all jsonb := '[]'::jsonb;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role purges organizations' using errcode = '42501', hint = 'ORGANIZATION_DELETION_FORBIDDEN';
  end if;
  if not exists (
    select 1 from ${d} x
    where x.${cd("tenant")} = organization_credential_refs.tenant and x.${cd("cancelledAt")} is null
      and x.${cd("purgedAt")} is null and x.${cd("purgeAfter")} <= now()
  ) then
    raise exception 'No due deletion for this organization' using errcode = 'P0002', hint = 'ORGANIZATION_DELETION_NOT_DUE';
  end if;
  for v_entry in
    select c.name, c.tbl, c.col, c.user_col, t.col as tenant_col
    from ${fn("data_lifecycle_credentials")}() c
    join ${fn("data_lifecycle_tables")}() t on t.subject = 'organization' and t.name = c.name and t.purge
    where to_regclass(c.tbl) is not null
    order by c.name, c.col
  loop
    select pg_catalog.format_type(a.atttypid, a.atttypmod) into v_type
    from pg_catalog.pg_attribute a
    where a.attrelid = to_regclass(v_entry.tbl) and a.attname = v_entry.tenant_col and not a.attisdropped;
    execute format(
      'select coalesce(jsonb_agg(jsonb_build_object(''table'', $2, ''column'', $3, ''ref'', r.ref, ''user_id'', r.user_id, ''in_tenant'', ${inTenant})), ''[]''::jsonb)
       from (select t.%I as ref, %s as user_id from %s t where t.%I = $1::%s) r
       where jsonb_typeof(r.ref) = ''object''',
      v_entry.col,
      case when v_entry.user_col is null then 'null::text' else format('t.%I::text', v_entry.user_col) end,
      v_entry.tbl, v_entry.tenant_col, v_type
    ) into v_refs
    using organization_credential_refs.tenant::text, v_entry.name, v_entry.col;
    v_all := v_all || v_refs;
  end loop;
  return v_all;
end;
$$;
revoke execute on function ${fn("data_lifecycle_credentials")}() from public, anon, authenticated;
revoke execute on function ${fn("organization_credential_refs")}(${id}) from public, anon, authenticated;
grant execute on function ${fn("data_lifecycle_credentials")}() to service_role;
grant execute on function ${fn("organization_credential_refs")}(${id}) to service_role;`;
}
