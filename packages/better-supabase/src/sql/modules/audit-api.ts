import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
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
  const filter = (logical: string, param: string) => {
    if (!hasColumn(ctx, "log", logical)) return "";
    const value = `l.${c(logical)}`;
    const read = isAuditValueColumn(logical)
      ? auditRead(ctx, logical, value)
      : value;
    return `
      and (${param} is null or cardinality(${param}) = 0 or ${read} = any (${param}))`;
  };
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
  const search =
    searchable.length === 0
      ? ""
      : `
      and (search is null or search = '' or concat_ws(' ', ${searchable.join(", ")}) ilike '%' || replace(replace(replace(search, '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%')`;
  const where = `(for_tenants is null or cardinality(for_tenants) = 0 or l.${c("tenant")} = any (for_tenants))${filter("eventType", "for_event_types")}${filter("actor", "for_actors")}${filter("targetType", "for_target_types")}${filter("record", "for_records")}${filter("category", "for_categories")}${filter("outcome", "for_outcomes")}${filter("source", "for_sources")}${filter("actorKind", "for_actor_kinds")}${filter("correlationId", "for_correlation_ids")}${search}
      and (since is null or l.${c("occurredAt")} >= since)
      and (until is null or l.${c("occurredAt")} < until)`;
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
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(x.entry order by
    case when ascending then x.occurred_at end, case when ascending then x.id end,
    x.occurred_at desc, x.id desc), '[]')
  from (
    select ${chunks.join(" || ")} as entry, l.${c("occurredAt")} as occurred_at, l.${c("id")}::text as id
    from ${log} l
    where ${where}
      and (cursor_at is null or (
        case when ascending
          then (l.${c("occurredAt")}, l.${c("id")}::text) > (cursor_at, coalesce(cursor_id, ''))
          else (l.${c("occurredAt")}, l.${c("id")}::text) < (cursor_at, coalesce(cursor_id, ''))
        end))
    order by
      case when ascending then l.${c("occurredAt")} end, case when ascending then l.${c("id")}::text end,
      l.${c("occurredAt")} desc, l.${c("id")}::text desc
    limit least(greatest(coalesce(max_items, 50), 1), 1000)
    offset greatest(coalesce(skip, 0), 0)
  ) x
$$;
revoke execute on function ${ctx.fn("list_audit_events")}(${listTypes}) from public, anon;
grant execute on function ${ctx.fn("list_audit_events")}(${listTypes}) to authenticated, service_role;

create or replace function ${ctx.fn("count_audit_events")}(
  ${filters}
)
returns bigint
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*) from ${log} l
  where ${where}
$$;
revoke execute on function ${ctx.fn("count_audit_events")}(${filterTypes}) from public, anon;
grant execute on function ${ctx.fn("count_audit_events")}(${filterTypes}) to authenticated, service_role;`;
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
  const viewAll = ctx.permission("viewAll", MODULE_PERMISSIONS.audit.viewAll);
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
