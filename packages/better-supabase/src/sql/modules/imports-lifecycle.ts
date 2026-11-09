import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, serviceGrant } from "../shared.ts";

/** Lease heartbeats, reference rows and the entity list an override can call. */
export function importLifecycleSql(
  ctx: BlockSqlContext,
  entities: readonly string[],
): string {
  const listed = entities.map((entity) => sqlString(entity)).join(", ");
  const fn = (name: string): string => ctx.fn(name);
  const runs = ctx.table("runs");
  const r = (column: string): string => ctx.col("runs", column);

  return `
create or replace function ${fn("heartbeat_import_run")}(run uuid, seconds integer default 30)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  if not (auth.role() = 'service_role') then
    ${fail("IMPORT_FORBIDDEN", "only the service role can heartbeat an import")}
  end if;
  update ${runs} r set ${r("heartbeatAt")} = now(), ${r("leaseUntil")} = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r.${r("id")} = heartbeat_import_run.run and r.${r("status")} = 'running'
  returning r.${r("leaseUntil")} into v_until;
  if v_until is null then
    ${fail("IMPORT_RUN_NOT_RUNNING", "the import is not running", "55000")}
  end if;
  return v_until;
end;
$$;
${serviceGrant(`${fn("heartbeat_import_run")}(uuid, integer)`)}

create or replace function ${fn("import_ensure_ref")}(tenant ${ctx.idType}, kind text, key text, defaults jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (auth.role() = 'service_role') then
    ${fail("IMPORT_FORBIDDEN", "only the service role can ensure an import ref")}
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    ${fail("IMPORT_ITEM_INVALID", "a ref needs a kind and a key", "22023")}
  end if;
  select r."id" into v_id from ${ctx.schema}.import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into ${ctx.schema}.import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from ${ctx.schema}.import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$$;
${serviceGrant(`${fn("import_ensure_ref")}(${ctx.idType}, text, text, jsonb)`)}

create or replace function ${fn("import_entities")}()
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select array[${listed === "" ? "" : listed}]::text[] $$;
${serviceGrant(`${fn("import_entities")}()`)}
`;
}

/** Realigns stored stamps and owned hashes to the current subject. */
export function rebaseImportSql(
  ctx: BlockSqlContext,
  stamp: string,
  owned: string,
): string {
  const fn = (name: string): string => ctx.fn(name);
  const records = ctx.table("records");
  const column = (name: string): string => ctx.col("records", name);

  return `
create or replace function ${fn("rebase_import_records")}(tenant ${ctx.idType}, source text, entities text[] default null, keys text[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (auth.role() = 'service_role') then
    ${fail("IMPORT_FORBIDDEN", "only the service role can rebase import records")}
  end if;
  update ${records} x
  set ${column("subjectUpdatedAt")} = coalesce((${stamp}), x.${column("subjectUpdatedAt")}),
      ${column("ownedHash")} = coalesce((${owned}), x.${column("ownedHash")})
  where x.${column("tenant")} = rebase_import_records.tenant
    and x.${column("source")} = rebase_import_records.source
    and (rebase_import_records.entities is null or x.${column("entity")} = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x.${column("externalKey")} = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("rebase_import_records")}(${ctx.idType}, text, text[], text[])`)}
`;
}
