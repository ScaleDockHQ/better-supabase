import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS, modulePermission } from "./access-model.ts";
import { hasColumn, impersonators } from "./audit-columns.ts";
import { auditRead, isAuditValueColumn } from "./audit-values.ts";

/** Logical log column to the key `list_audit_events` returns it under. */
const ENTRY_KEYS: readonly (readonly [string, string])[] = [
  ["id", "id"],
  ["table", "table"],
  ["record", "record"],
  ["op", "op"],
  ["old", "old"],
  ["new", "new"],
  ["changed", "changed"],
  ["actor", "actorId"],
  ["actorRole", "actorRole"],
  ["actorKind", "actorKind"],
  ["actorLabel", "actorLabel"],
  ["tenant", "tenant"],
  ["tenantLabel", "tenantLabel"],
  ["occurredAt", "occurredAt"],
  ["impersonatedBy", "impersonatedBy"],
  ["impersonationReason", "impersonationReason"],
  ["supportSession", "supportSession"],
  ["eventType", "eventType"],
  ["category", "category"],
  ["outcome", "outcome"],
  ["source", "source"],
  ["targetType", "targetType"],
  ["targetLabel", "targetLabel"],
  ["summary", "summary"],
  ["requestId", "requestId"],
  ["correlationId", "correlationId"],
  ["scope", "scope"],
  ["metadata", "metadata"],
];

/**
 * `list_audit_events` for the TypeScript side: a page of entries the caller
 * can read (security invoker, so the read policy decides), newest first.
 */
export function listEntries(
  ctx: ModuleContext,
  restricted: boolean,
  extra: readonly (readonly [column: string, key: string])[] = [],
): string {
  const id = ctx.idType;
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const hidden = new Set(
    impersonators(ctx) === "hide"
      ? ["impersonatedBy", "impersonationReason", "supportSession"]
      : [],
  );
  const pairs = ENTRY_KEYS.filter(
    ([logical]) =>
      hasColumn(ctx, "log", logical) &&
      !hidden.has(logical) &&
      !(restricted && (logical === "old" || logical === "new")),
  ).map(([logical, key]) => {
    const value = `l.${c(logical)}`;
    return `'${key}', ${isAuditValueColumn(logical) ? auditRead(ctx, logical, value) : value}`;
  });
  if (extra.length > 0)
    pairs.push(
      `'columns', jsonb_build_object(${extra.map(([column]) => `${sqlString(column)}, l.${sqlIdent(column)}`).join(", ")})`,
    );
  // jsonb_build_object takes at most 100 arguments; split in chunks of 20 keys.
  const chunks: string[] = [];
  for (let index = 0; index < pairs.length; index += 20)
    chunks.push(
      `jsonb_build_object(${pairs.slice(index, index + 20).join(", ")})`,
    );
  // The filters and their positions in the dynamic query's `using` list.
  const conditions: string[] = [];
  const filter = (logical: string, param: string, position: number) => {
    if (!hasColumn(ctx, "log", logical)) return;
    const value = `l.${c(logical)}`;
    const read = isAuditValueColumn(logical)
      ? auditRead(ctx, logical, value)
      : value;
    conditions.push(`  if cardinality(${param}) > 0 then
    v_where := v_where || $q$ and ${read} = any ($${position})$q$;
  end if;`);
  };
  filter("tenant", "for_tenants", 1);
  filter("eventType", "for_event_types", 2);
  filter("actor", "for_actors", 3);
  filter("targetType", "for_target_types", 4);
  filter("record", "for_records", 5);
  filter("category", "for_categories", 6);
  filter("outcome", "for_outcomes", 7);
  filter("source", "for_sources", 9);
  filter("actorKind", "for_actor_kinds", 10);
  filter("correlationId", "for_correlation_ids", 11);
  const searchable = (
    [
      "eventType",
      "summary",
      "targetLabel",
      "actorLabel",
      "tenantLabel",
      "record",
      "table",
    ] as const
  )
    .filter((logical) => hasColumn(ctx, "log", logical))
    .map((logical) => `l.${c(logical)}`);
  if (searchable.length > 0) {
    conditions.push(`  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', ${searchable.join(", ")}) ilike '%' || replace(replace(replace($8, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%'$q$;
  end if;`);
  }
  conditions.push(`  if since is not null then
    v_where := v_where || $q$ and l.${c("occurredAt")} >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l.${c("occurredAt")} < $13$q$;
  end if;`);
  const where = conditions.join("\n");
  const using =
    "for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until";
  // A managed log's id is a bigint, so "10" pages after "9"; an adopted
  // log's id compares as text.
  const idKey = ctx.manages ? `l.${c("id")}` : `l.${c("id")}::text`;
  const cursorKey = ctx.manages ? "$15::bigint" : "$15";
  const filters = `for_tenants ${id}[] default null,
  for_event_types text[] default null,
  for_actors uuid[] default null,
  for_target_types text[] default null,
  for_records text[] default null,
  for_categories text[] default null,
  for_outcomes text[] default null,
  search text default null,
  for_sources text[] default null,
  for_actor_kinds text[] default null,
  for_correlation_ids text[] default null,
  since timestamptz default null,
  until timestamptz default null`;
  const filterTypes = `${id}[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamptz, timestamptz`;
  const listTypes = `${filterTypes}, timestamptz, text, integer, boolean, integer`;
  // A managed log without options.readPolicy grants users no select, so the
  // invoker functions would only raise 42501 for them.
  const callers =
    !ctx.manages || ctx.flag("readPolicy", false)
      ? "authenticated, service_role"
      : "service_role";
  const revokeUsers = (fn: string, types: string): string =>
    callers === "service_role"
      ? `revoke execute on function ${fn}(${types}) from authenticated;\n`
      : "";
  return `-- A page of the entries the caller can read, newest first unless ascending:
-- the read policy decides (security invoker). Each filter takes several
-- values; search matches the event type, summary, labels, record and table.
-- Page with the last entry's occurred_at and id as cursor_at and cursor_id,
-- or open page N with skip (an offset) and count_audit_events for the total.
drop function if exists ${ctx.fn("list_audit_events")}(${id}, text, uuid, text, text, timestamptz, timestamptz, timestamptz, text, integer);
drop function if exists ${ctx.fn("list_audit_events")}(${filterTypes}, timestamptz, text, integer, boolean);
create or replace function ${ctx.fn("list_audit_events")}(
  ${filters},
  cursor_at timestamptz default null,
  cursor_id text default null,
  max_items integer default 50,
  ascending boolean default false,
  skip integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_where text := 'true';
  v_order text := case when ascending then 'asc' else 'desc' end;
  result jsonb;
begin
${where}
  if cursor_at is not null then
    v_where := v_where || case when ascending
      then $q$ and (l.${c("occurredAt")}, ${idKey}) > ($14, ${cursorKey})$q$
      else $q$ and (l.${c("occurredAt")}, ${idKey}) < ($14, ${cursorKey})$q$
    end;
  end if;
  -- Only the filters passed reach the query, so the planner sees no
  -- "is null or" branches and can use the (tenant, occurred_at) index.
  execute $q$select coalesce(jsonb_agg(x.entry order by x.occurred_at $q$ || v_order || $q$, x.id $q$ || v_order || $q$), '[]')
  from (
    select ${chunks.join(" || ")} as entry, l.${c("occurredAt")} as occurred_at, ${idKey} as id
    from ${log} l
    where $q$ || v_where || $q$
    order by l.${c("occurredAt")} $q$ || v_order || $q$, ${idKey} $q$ || v_order || $q$
    limit $16
    offset $17
  ) x$q$
  into result
  using ${using}, cursor_at, cursor_id, least(greatest(coalesce(max_items, 50), 1), 1000), greatest(coalesce(skip, 0), 0);
  return result;
end;
$$;
revoke execute on function ${ctx.fn("list_audit_events")}(${listTypes}) from public, anon;
${revokeUsers(ctx.fn("list_audit_events"), listTypes)}grant execute on function ${ctx.fn("list_audit_events")}(${listTypes}) to ${callers};

create or replace function ${ctx.fn("count_audit_events")}(
  ${filters}
)
returns bigint
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_where text := 'true';
  result bigint;
begin
${where}
  execute $q$select count(*) from ${log} l where $q$ || v_where
  into result
  using ${using};
  return result;
end;
$$;
revoke execute on function ${ctx.fn("count_audit_events")}(${filterTypes}) from public, anon;
${revokeUsers(ctx.fn("count_audit_events"), filterTypes)}grant execute on function ${ctx.fn("count_audit_events")}(${filterTypes}) to ${callers};`;
}

/**
 * `reveal_audit_entry(entry)`: the restricted details of one entry, for a
 * member who may reveal them in its tenant (or platform staff), and an
 * `audit.revealed` entry that records who looked.
 */
export function reveal(ctx: ModuleContext, restricted: boolean): string {
  if (!restricted || !ctx.installed("access")) return "";
  const log = ctx.table("log");
  const c = (logical: string) => ctx.col("log", logical);
  const r = (logical: string) => ctx.col("restricted", logical);
  const key = ctx.permission(
    "reveal",
    ctx.permissionKey("view", MODULE_PERMISSIONS.audit.view),
  );
  const viewAll = modulePermission(
    ctx,
    "viewAll",
    MODULE_PERMISSIONS.audit.viewAll,
  );
  const fields = (
    [
      ["old", "old"],
      ["new", "new"],
      ["ip", "ip"],
      ["userAgent", "userAgent"],
      ["metadata", "metadata"],
      ["sessionId", "sessionId"],
      ["changedValues", "changes"],
    ] as const
  )
    .filter(([logical]) => hasColumn(ctx, "restricted", logical))
    .map(([logical, out]) => `, '${out}', d.${r(logical)}`)
    .join("");
  const allowed = (tenant: string) => `(${SERVICE_CALLER})
    or coalesce(better_supabase.is_platform(${viewAll}), false)
    or (${tenant} is not null and coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${key}), false))`;
  return `-- The restricted details of one entry for a member with the reveal
-- permission in its tenant, or platform staff, recorded as audit.revealed.
create or replace function ${ctx.fn("reveal_audit_entry")}(entry text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner ${ctx.idType};
  found_entry boolean;
  details jsonb;
begin
  select true, l.${c("tenant")} into found_entry, owner from ${log} l where l.${c("id")}::text = entry;
  if found_entry is null or not (
    ${allowed("owner")}
  ) then
    raise exception 'No audit entry %', entry using errcode = 'P0002', hint = 'AUDIT_ENTRY_NOT_FOUND';
  end if;
  select jsonb_build_object('entry', entry${fields}) into details
  from ${ctx.table("restricted")} d where d.${r("entry")}::text = entry;
  perform better_supabase.audit_event(
    event_type => 'audit.revealed',
    category => 'audit',
    target_type => 'audit_entry',
    record_id => entry,
    tenant => owner,
    actor_id => auth.uid()
  );
  return coalesce(details, jsonb_build_object('entry', entry));
end;
$$;
revoke execute on function ${ctx.fn("reveal_audit_entry")}(text) from public, anon;
grant execute on function ${ctx.fn("reveal_audit_entry")}(text) to authenticated, service_role;

-- The restricted details of the entries the caller may reveal, for an
-- export; entries it may not reveal are left out. One audit.revealed entry
-- per tenant lists the revealed entry ids.
create or replace function ${ctx.fn("reveal_audit_entries")}(entries text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  visible jsonb;
  details jsonb;
  revealed record;
begin
  select coalesce(jsonb_agg(jsonb_build_object('entry', l.${c("id")}::text, 'owner', l.${c("tenant")})), '[]') into visible
  from ${log} l
  where l.${c("id")}::text = any (entries)
    and (
    ${allowed(`l.${c("tenant")}`)}
    );
  select coalesce(jsonb_agg(jsonb_build_object('entry', v ->> 'entry'${fields})), '[]') into details
  from jsonb_array_elements(visible) v
  left join ${ctx.table("restricted")} d on d.${r("entry")}::text = v ->> 'entry';
  for revealed in
    select v ->> 'owner' as owner, jsonb_agg(v -> 'entry') as ids
    from jsonb_array_elements(visible) v
    group by v ->> 'owner'
  loop
    perform better_supabase.audit_event(
      event_type => 'audit.revealed',
      category => 'audit',
      target_type => 'audit_entry',
      tenant => (revealed.owner)::${ctx.idType},
      actor_id => auth.uid(),
      metadata => jsonb_build_object('entries', revealed.ids)
    );
  end loop;
  return details;
end;
$$;
revoke execute on function ${ctx.fn("reveal_audit_entries")}(text[]) from public, anon;
grant execute on function ${ctx.fn("reveal_audit_entries")}(text[]) to authenticated, service_role;`;
}
